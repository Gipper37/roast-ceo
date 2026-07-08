-- Phase 0 of the lot-engine rearchitecture: batch per-row valuation inside the
-- FIFO replay (fixes the 45s / timeout-rollback completed-roast edit).
--
-- MEASURED ROOT CAUSE: ~98% of recompute_origin_lot_consumption's cost is not
-- the FIFO loop — it's per-row trigger amplification. Every rlc DELETE/INSERT
-- fires trg_value_lot_consumption (~150-195ms: whole-roast cost snapshot +
-- rollup + origin-wide latest_roasted_cost rescan) and every cip.remaining_lbs
-- touch fires trg_refresh_origin_total_on_lot_change (full origin total
-- recompute). Wiping + replaying 46 rows = ~7.2s of a 7.4s replay (0.12s with
-- triggers off); a 4-origin blend edit stacks 4 replays ≈ 45s > timeouts.
--
-- FIX (same proven idiom as app.defer_lot_recompute / app.defer_shipment_recompute,
-- see 20260703000003): a transaction-local defer guard, app.defer_lot_valuation,
-- silences both per-row triggers while the replay rewrites the ledger; the replay
-- then reconciles ONCE per origin — a set-based valuation pass over every
-- affected roast + one total-stock recompute. Valuation is a pure function of
-- the final committed rlc/lot state, so one batched pass == the sum of the
-- per-row firings. Owner-must-reconcile: anything that sets the guard MUST run
-- the reconcile before returning.
--
-- Attribution semantics are UNCHANGED in this migration (validated by
-- state-hash equivalence against the live function, rolled back on prod).

-- ── 1. Defer guards on the two per-row amplifiers ───────────────────────────

CREATE OR REPLACE FUNCTION public.trg_value_lot_consumption()
RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
    -- Batched replays value once per origin at the end (value_origin_lot_consumption).
    IF current_setting('app.defer_lot_valuation', true) = 'true' THEN RETURN NULL; END IF;
    PERFORM public.value_roast_lot_consumption(COALESCE(NEW.roast_log_id, OLD.roast_log_id));
    RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.refresh_origin_total_on_lot_change()
RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
    -- Batched replays recalc the origin total once at the end.
    IF current_setting('app.defer_lot_valuation', true) = 'true' THEN RETURN NEW; END IF;
    IF NEW.origin IS NOT NULL AND NEW.facility_id IS NOT NULL THEN
        PERFORM public.recalculate_origin_total_stock(NEW.origin, NEW.facility_id);
    END IF;
    RETURN NEW;
END;
$function$;

-- Third per-row amplifier: trigger_roast_log_update_inventory has NO column
-- list, so the valuation pass's roast_log cost updates fire the full par/stock
-- refresh (two 92-day scans per component origin) once per revalued roast —
-- measured ~165ms/roast, ~7.5s of a 7.6s batched replay. Valuation never
-- changes stock or usage, so those firings are pure no-op recomputes; the
-- replay reconciles par/stock once per origin at the end instead. Body below is
-- the live prod definition with ONLY the one-line guard added at the top.
CREATE OR REPLACE FUNCTION public.trg_roast_log_inventory_update()
RETURNS trigger LANGUAGE plpgsql AS $function$
DECLARE
    r              RECORD;
    v_bag_size     NUMERIC;
    v_facility_id  TEXT;
    v_current_lbs  NUMERIC;
    v_current_bags NUMERIC;
    v_roast_type   TEXT;
    v_par          NUMERIC;
BEGIN
    -- Batched replays reconcile par/stock once per origin at the end
    -- (refresh_coffee_stock_par); the per-row firing is a pure no-op there.
    IF current_setting('app.defer_lot_valuation', true) = 'true' THEN RETURN NULL; END IF;

    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    -- ── DELETE / UPDATE: revert OLD values ──────────────────────────────────
    IF TG_OP = 'DELETE' OR TG_OP = 'UPDATE' THEN

        v_roast_type := NULL;
        IF OLD.recipe_id IS NOT NULL THEN
            SELECT roast_type INTO v_roast_type FROM roast_recipes WHERE recipe_id = OLD.recipe_id;
        END IF;

        -- Case A: Pre-Blend (per-origin lookup inside loop)
        IF v_roast_type = 'Pre-Blend' THEN
            FOR r IN SELECT coffee_item FROM recipe_components WHERE recipe_id = OLD.recipe_id LOOP

                SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
                FROM coffee_inventory
                WHERE origin_id = r.coffee_item AND facility_id = OLD.facility_id LIMIT 1;

                v_current_lbs  := public.calculate_current_stock_lbs(r.coffee_item, OLD.facility_id);
                v_current_bags := v_current_lbs / NULLIF(v_bag_size, 0);
                v_par          := public.calculate_par(r.coffee_item);

                UPDATE coffee_inventory SET
                    in_stock_lbs  = v_current_lbs,
                    in_stock      = v_current_bags,
                    par           = v_par,
                    to_order_bags = GREATEST(0, COALESCE(v_par, 0) - v_current_bags),
                    restock_level = public.calculate_restock_level(r.coffee_item)
                WHERE origin_id = r.coffee_item AND facility_id = OLD.facility_id;

            END LOOP;

        -- Case B: Single origin / post-blend
        ELSIF OLD.origin_id IS NOT NULL THEN

            SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
            FROM coffee_inventory
            WHERE origin_id = OLD.origin_id AND facility_id = OLD.facility_id LIMIT 1;

            v_current_lbs  := public.calculate_current_stock_lbs(OLD.origin_id, OLD.facility_id);
            v_current_bags := v_current_lbs / NULLIF(v_bag_size, 0);
            v_par          := public.calculate_par(OLD.origin_id);

            UPDATE coffee_inventory SET
                in_stock_lbs  = v_current_lbs,
                in_stock      = v_current_bags,
                par           = v_par,
                to_order_bags = GREATEST(0, COALESCE(v_par, 0) - v_current_bags),
                restock_level = public.calculate_restock_level(OLD.origin_id)
            WHERE origin_id = OLD.origin_id AND facility_id = OLD.facility_id;

        END IF;
    END IF;

    -- ── INSERT / UPDATE: apply NEW values ───────────────────────────────────
    IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN

        v_roast_type := NULL;
        IF NEW.recipe_id IS NOT NULL THEN
            SELECT roast_type INTO v_roast_type FROM roast_recipes WHERE recipe_id = NEW.recipe_id;
        END IF;

        -- Case A: Pre-Blend (per-origin lookup inside loop)
        IF v_roast_type = 'Pre-Blend' THEN
            FOR r IN SELECT coffee_item FROM recipe_components WHERE recipe_id = NEW.recipe_id LOOP

                SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
                FROM coffee_inventory
                WHERE origin_id = r.coffee_item AND facility_id = NEW.facility_id LIMIT 1;

                v_current_lbs  := public.calculate_current_stock_lbs(r.coffee_item, NEW.facility_id);
                v_current_bags := v_current_lbs / NULLIF(v_bag_size, 0);
                v_par          := public.calculate_par(r.coffee_item);

                UPDATE coffee_inventory SET
                    in_stock_lbs  = v_current_lbs,
                    in_stock      = v_current_bags,
                    par           = v_par,
                    to_order_bags = GREATEST(0, COALESCE(v_par, 0) - v_current_bags),
                    restock_level = public.calculate_restock_level(r.coffee_item)
                WHERE origin_id = r.coffee_item AND facility_id = NEW.facility_id;

            END LOOP;

        -- Case B: Single origin / post-blend
        ELSIF NEW.origin_id IS NOT NULL THEN

            SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
            FROM coffee_inventory
            WHERE origin_id = NEW.origin_id AND facility_id = NEW.facility_id LIMIT 1;

            v_current_lbs  := public.calculate_current_stock_lbs(NEW.origin_id, NEW.facility_id);
            v_current_bags := v_current_lbs / NULLIF(v_bag_size, 0);
            v_par          := public.calculate_par(NEW.origin_id);

            UPDATE coffee_inventory SET
                in_stock_lbs  = v_current_lbs,
                in_stock      = v_current_bags,
                par           = v_par,
                to_order_bags = GREATEST(0, COALESCE(v_par, 0) - v_current_bags),
                restock_level = public.calculate_restock_level(NEW.origin_id)
            WHERE origin_id = NEW.origin_id AND facility_id = NEW.facility_id;

        END IF;
    END IF;

    RETURN NULL;
END;
$function$;

-- ── 2. Set-based batch valuation (one pass for N roasts) ────────────────────
-- Reproduces value_roast_lot_consumption exactly, for a SET of roasts:
--   a. re-snapshot green/shipping cost on every rlc row of the open roasts
--   b. roll up green_cost + roasted_cost_lb per roast (NULL when no rows)
--   c. refresh coffee_inventory.latest_roasted_cost once per distinct origin
-- Honors the books-closed freeze: roasts with roast_date <= books_closed_through
-- are untouched (same early-return as the per-roast function).
CREATE OR REPLACE FUNCTION public.value_roasts_lot_consumption(p_roast_ids text[])
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_open text[];
    v_o record;
    v_new_cost numeric;
BEGIN
    IF p_roast_ids IS NULL OR array_length(p_roast_ids, 1) IS NULL THEN RETURN; END IF;

    -- Books-closed guard, set-based: only open-period roasts get revalued.
    SELECT COALESCE(array_agg(rl.roast_log_id), ARRAY[]::text[]) INTO v_open
      FROM public.roast_log rl
      LEFT JOIN public.companies c ON c.company_id = rl.company_id
     WHERE rl.roast_log_id = ANY(p_roast_ids)
       AND NOT (c.books_closed_through IS NOT NULL
                AND rl.roast_date IS NOT NULL
                AND rl.roast_date::date <= c.books_closed_through);
    IF array_length(v_open, 1) IS NULL THEN RETURN; END IF;

    -- a. snapshot each ledger row's green + shipping cost from its lot
    --    (lot_cost is GENERATED from these, so it follows automatically).
    UPDATE public.roast_log_lot_consumption rlc
       SET green_cost_lb    = cip.cost_lb,
           shipping_cost_lb = COALESCE(sr.shipping_cost_unit, 0)
      FROM public.coffee_inventory_purchased cip
      LEFT JOIN public.shipment_received sr ON sr.shipment_id = cip.shipment_id
     WHERE rlc.roast_log_id = ANY(v_open)
       AND cip.origin_purchase_id = rlc.origin_purchase_id;

    -- b. roll up to roast_log (green_cost NULL when a roast has no rows left)
    UPDATE public.roast_log rl
       SET green_cost      = agg.total_green,
           roasted_cost_lb = CASE WHEN agg.total_green IS NOT NULL AND COALESCE(agg.roasted_lbs, 0) > 0
                                  THEN agg.total_green / agg.roasted_lbs
                                  ELSE NULL END
      FROM (
        SELECT rl2.roast_log_id,
               (SELECT SUM(x.lot_cost) FROM public.roast_log_lot_consumption x
                 WHERE x.roast_log_id = rl2.roast_log_id) AS total_green,
               COALESCE(rl2.measured_roasted_weight,
                        rl2.roasted_weight,
                        rl2.charge_weight_lbs * COALESCE(public.get_retention_factor(rl2.facility_id, rl2.recipe_id), 0.82)) AS roasted_lbs
          FROM public.roast_log rl2
         WHERE rl2.roast_log_id = ANY(v_open)
      ) agg
     WHERE rl.roast_log_id = agg.roast_log_id;

    -- c. refresh cached per-origin roasted cost once per distinct (origin, facility)
    FOR v_o IN
        SELECT DISTINCT cip.origin, rl.facility_id
          FROM public.roast_log_lot_consumption rlc
          JOIN public.coffee_inventory_purchased cip ON cip.origin_purchase_id = rlc.origin_purchase_id
          JOIN public.roast_log rl ON rl.roast_log_id = rlc.roast_log_id
         WHERE rlc.roast_log_id = ANY(v_open)
           AND cip.origin IS NOT NULL AND rl.facility_id IS NOT NULL
    LOOP
        v_new_cost := public.get_origin_roasted_cost_on_date(v_o.origin, v_o.facility_id, CURRENT_DATE);
        UPDATE public.coffee_inventory ci
           SET latest_roasted_cost = v_new_cost
         WHERE ci.origin_id = v_o.origin
           AND ci.facility_id = v_o.facility_id
           AND ci.latest_roasted_cost IS DISTINCT FROM v_new_cost;
    END LOOP;
END;
$$;

-- ── 3. The replay: defer per-row work, reconcile once per origin ────────────
-- Body identical to the live 20260703000005 version EXCEPT:
--   * captures the pre-wipe consumer set (roasts that lose rows must be
--     revalued even if the replay gives them none back — matches the per-row
--     DELETE trigger's behavior),
--   * wraps the wipe + reseed + replay in app.defer_lot_valuation,
--   * reconciles once: batched valuation over pre ∪ post consumers, then the
--     existing recalculate_origin_total_stock.
CREATE OR REPLACE FUNCTION public.recompute_origin_lot_consumption(p_origin_id text, p_facility_id text)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE
    v_roast record;
    v_needed numeric;
    v_pref text;
    v_force text;
    v_last_count_at timestamptz;
    v_tz text;
    v_pre_ids text[];
    v_post_ids text[];
    v_all_ids text[];
BEGIN
    IF p_origin_id IS NULL OR p_facility_id IS NULL THEN RETURN; END IF;

    SELECT COALESCE(NULLIF(time_zone, ''), 'UTC') INTO v_tz
      FROM public.facilities WHERE facility_id = p_facility_id;
    v_tz := COALESCE(v_tz, 'UTC');

    SELECT MAX(clc.count_at) INTO v_last_count_at
      FROM public.coffee_lot_count clc
      JOIN public.coffee_inventory_purchased cip2 ON cip2.origin_purchase_id = clc.origin_purchase_id
     WHERE cip2.origin = p_origin_id AND cip2.facility_id = p_facility_id;

    -- Roasts currently consuming this origin's lots — they lose rows in the
    -- wipe, so their cost rollups must be refreshed in the final reconcile.
    SELECT COALESCE(array_agg(DISTINCT rlc.roast_log_id), ARRAY[]::text[]) INTO v_pre_ids
      FROM public.roast_log_lot_consumption rlc
      JOIN public.coffee_inventory_purchased cip ON cip.origin_purchase_id = rlc.origin_purchase_id
     WHERE cip.origin = p_origin_id AND cip.facility_id = p_facility_id;

    -- Silence the per-row valuation + origin-total triggers for the duration of
    -- the rewrite; this function reconciles both once at the end. ALSO set the
    -- shipment-side defer flag: three cip triggers with no column list
    -- (trg_push_last_coffee_cost → recalculate_inventory_cost,
    -- trg_update_green_metrics_from_purchased → green metrics,
    -- update_shipment_on_coffee → shipment totals) fire on EVERY remaining_lbs
    -- touch during the replay; they already honor app.defer_shipment_recompute
    -- (20260703000003). Cost + green metrics are reconciled once below; shipment
    -- totals need no reconcile (they sum cip.amount, which the replay never
    -- changes — the per-row firings were pure no-op recomputes).
    PERFORM set_config('app.defer_lot_valuation', 'true', true);
    PERFORM set_config('app.defer_shipment_recompute', 'true', true);

    UPDATE public.coffee_inventory_purchased cip
       SET remaining_lbs = NULL
     WHERE cip.origin = p_origin_id AND cip.facility_id = p_facility_id
       AND cip.shipment_id IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM public.shipment_received sr
          WHERE sr.shipment_id = cip.shipment_id
            AND sr.date_received IS NOT NULL
            AND COALESCE(sr.voided, false) = false);

    UPDATE public.coffee_inventory_purchased cip
       SET remaining_lbs = CASE
            WHEN v_last_count_at IS NULL THEN cip.amount
            ELSE COALESCE(
              -- this lot's OWN latest count, but ONLY if taken on/after the lot's
              -- receipt (a pre-receipt count can't be the lot's truth).
              (SELECT clc.counted_remaining_lbs
                 FROM public.coffee_lot_count clc
                WHERE clc.origin_purchase_id = cip.origin_purchase_id
                  AND clc.count_at >= COALESCE(
                        (SELECT sr.date_received::timestamptz
                           FROM public.shipment_received sr WHERE sr.shipment_id = cip.shipment_id),
                        cip.created_at)
                ORDER BY clc.count_at DESC, clc.created_at DESC LIMIT 1),
              -- fallback: received ON/AFTER the group's last count → fresh stock
              -- (full amount); strictly earlier uncounted lots stay 0 (assumed
              -- captured by that comprehensive count).
              CASE WHEN COALESCE(
                     (SELECT sr.date_received FROM public.shipment_received sr WHERE sr.shipment_id = cip.shipment_id),
                     cip.created_at::date) >= v_last_count_at::date
                   THEN cip.amount ELSE 0 END
            )
           END
     WHERE cip.origin = p_origin_id AND cip.facility_id = p_facility_id
       AND cip.amount IS NOT NULL
       AND (cip.shipment_id IS NULL
          OR EXISTS (SELECT 1 FROM public.shipment_received sr
                      WHERE sr.shipment_id = cip.shipment_id
                        AND sr.date_received IS NOT NULL
                        AND COALESCE(sr.voided, false) = false));

    DELETE FROM public.roast_log_lot_consumption rlc
     USING public.coffee_inventory_purchased cip
     WHERE rlc.origin_purchase_id = cip.origin_purchase_id
       AND cip.origin = p_origin_id AND cip.facility_id = p_facility_id;

    FOR v_roast IN
        SELECT rl.roast_log_id, rl.charge_weight_lbs, rl.coffee_source_id,
               rl.recipe_id, rl.origin_id, rl.roast_date, rl.created_at,
               rl.borrow_origin_purchase_id, rr.roast_type,
               COALESCE(rl.roast_date_utc, (rl.roast_date AT TIME ZONE v_tz)) AS roast_utc
          FROM public.roast_log rl
          LEFT JOIN public.roast_recipes rr ON rr.recipe_id = rl.recipe_id
         WHERE rl.facility_id = p_facility_id
           AND rl."charged?" = true
           AND COALESCE(rl.charge_weight_lbs, 0) > 0
           AND (rl.external_roast_id IS NOT NULL
                OR rl.roast_date >= (rl.created_at::date - interval '1 day'))
           AND (v_last_count_at IS NULL
                OR COALESCE(rl.roast_date_utc, (rl.roast_date AT TIME ZONE v_tz)) > v_last_count_at)
           AND (
              (rl.borrow_origin_purchase_id IS NULL AND (
                  (rr.roast_type = 'Pre-Blend'
                     AND EXISTS (SELECT 1 FROM public.recipe_components rc
                                  WHERE rc.recipe_id = rl.recipe_id
                                    AND rc.coffee_item = p_origin_id
                                    AND COALESCE(rc.percentage, 0) > 0))
                  OR ((rr.roast_type IS NULL OR rr.roast_type <> 'Pre-Blend')
                        AND rl.origin_id = p_origin_id)))
              OR
              (rl.borrow_origin_purchase_id IS NOT NULL
                 AND EXISTS (SELECT 1 FROM public.coffee_inventory_purchased b
                              WHERE b.origin_purchase_id = rl.borrow_origin_purchase_id
                                AND b.origin = p_origin_id))
           )
         ORDER BY COALESCE(rl.roast_date_utc, (rl.roast_date AT TIME ZONE v_tz)) ASC, rl.created_at ASC
    LOOP
        v_force := NULL;
        IF v_roast.borrow_origin_purchase_id IS NOT NULL THEN
            v_needed := v_roast.charge_weight_lbs;
            v_force  := v_roast.borrow_origin_purchase_id;
            v_pref   := NULL;
        ELSIF v_roast.roast_type = 'Pre-Blend' THEN
            SELECT v_roast.charge_weight_lbs * COALESCE(rc.percentage, 0)
              INTO v_needed
              FROM public.recipe_components rc
             WHERE rc.recipe_id = v_roast.recipe_id AND rc.coffee_item = p_origin_id
             ORDER BY rc.percentage DESC LIMIT 1;
            v_pref := NULL;
            IF v_roast.coffee_source_id IS NOT NULL THEN
                SELECT CASE WHEN cs.origin_id = p_origin_id THEN v_roast.coffee_source_id ELSE NULL END
                  INTO v_pref FROM public.coffee_source cs WHERE cs.coffee_source_id = v_roast.coffee_source_id;
            END IF;
        ELSE
            v_needed := v_roast.charge_weight_lbs;
            v_pref := NULL;
            IF v_roast.coffee_source_id IS NOT NULL THEN
                SELECT CASE WHEN cs.origin_id = p_origin_id THEN v_roast.coffee_source_id ELSE NULL END
                  INTO v_pref FROM public.coffee_source cs WHERE cs.coffee_source_id = v_roast.coffee_source_id;
            END IF;
        END IF;
        IF COALESCE(v_needed, 0) <= 0 THEN CONTINUE; END IF;

        PERFORM public._deduct_origin_fifo(
            v_roast.roast_log_id, p_origin_id, p_facility_id, v_needed, v_pref, v_roast.roast_date, v_force);
    END LOOP;

    -- ── Reconcile once (owner-must-reconcile) ──
    -- Valuation runs with the defer flags STILL SET so its roast_log cost
    -- updates don't fire the per-roast par/stock trigger (no-ops here anyway).
    SELECT COALESCE(array_agg(DISTINCT rlc.roast_log_id), ARRAY[]::text[]) INTO v_post_ids
      FROM public.roast_log_lot_consumption rlc
      JOIN public.coffee_inventory_purchased cip ON cip.origin_purchase_id = rlc.origin_purchase_id
     WHERE cip.origin = p_origin_id AND cip.facility_id = p_facility_id;

    SELECT COALESCE(array_agg(DISTINCT x), ARRAY[]::text[]) INTO v_all_ids
      FROM unnest(v_pre_ids || v_post_ids) AS x;

    PERFORM public.value_roasts_lot_consumption(v_all_ids);

    PERFORM set_config('app.defer_lot_valuation', 'false', true);
    PERFORM set_config('app.defer_shipment_recompute', 'false', true);

    -- Once-per-origin versions of everything the deferred triggers would have
    -- recomputed row-by-row (each a pure recompute of final committed state):
    -- lot totals, par/stock caches, latest cost, green purchasing metrics.
    PERFORM public.recalculate_origin_total_stock(p_origin_id, p_facility_id);
    PERFORM public.refresh_coffee_stock_par(p_origin_id, p_facility_id);
    PERFORM public.recalculate_inventory_cost(p_origin_id, p_facility_id);
    PERFORM public.recalculate_green_purchasing_metrics(p_facility_id);
END;
$function$;

NOTIFY pgrst, 'reload schema';
