-- Source-true blend-component deduction.
--
-- PROBLEM. A pre-blend component can be planned (planned_lots[component_origin] =
-- a coffee_source_id) to draw from a source whose HOME group differs from the
-- component's own group — a cross-group borrow (e.g. the "Fruit" component of a
-- blend planned to a source that lives in the "Chocolate" group). Today that
-- planned source only reorders candidates INSIDE the component group
-- (_deduct_origin_fifo matched cip.origin = p_origin_id, then preferred
-- cip.coffee_source_id = p_preferred_source). Since the chosen source's lots
-- physically live in a DIFFERENT group, they are never in the candidate set —
-- the preference silently no-ops and the deduct falls back to the component
-- group's native FIFO. Result: the component draws the wrong group's beans.
--
-- Prod evidence (MCR, company 9ShiyDAXhV): 6 charged pre-blend component-
-- instances have a cross-group planned source; 176 same-group + 875 no-pick
-- components must stay byte-identical. One roast (ec29a295-…) even has TWO
-- components landing in the same lender group (one native Chocolate, one Fruit
-- borrowed INTO Chocolate) — the replay of that lender group must deduct BOTH.
--
-- FIX (source-true, FIFO-within-the-source):
--   1. _deduct_origin_fifo gains p_force_source_id. The candidate set widens to
--      include cip.coffee_source_id = p_force_source_id (ANY group). A new
--      ORDER-BY tier draws the forced-source lots FIRST (above group FIFO, below
--      the pinned borrow lot), then keeps receipt-date/created FIFO — i.e. FIFO
--      WITHIN the forced source. Forced-source lots STILL respect the existed-at-
--      roast-date guard (unlike the pinned borrow lot, which is an explicit
--      operator pick and is exempt).
--   2. deduct_one_roast + recompute_origin_lot_consumption: when a pre-blend
--      component's planned source is cross-group (coffee_source.origin_id <> the
--      component origin), pass that source as p_force_source_id (v_pref stays
--      NULL). Same-group / no-pick picks are byte-identical (v_force_source NULL).
--      Because the replay keys on ONE origin, its pre-blend handling is expressed
--      per-effective-group: a borrowed component is OWNED by (deducted during the
--      replay of) its LENDER group, and SKIPPED by the replay of its own group.
--   3. _roast_affected_origins gains an optional p_planned_lots arg; for pre-blend
--      recipes it unions in the lender home group of every cross-group planned
--      source, so every writer locks the lender group and the delete/edit trigger
--      enqueues its recompute.
--   4. roast_log_lot_recompute trigger + delete_roasts already enqueue every
--      _roast_affected_origins entry (now including lender groups) on DELETE /
--      retro-UPDATE; delete_roasts' needs_replay membership is widened to see a
--      lender group as affected by a cross-group pre-blend consumption.
--   5. The explicit borrow_origin_purchase_id (p_force_origin_purchase_id) path
--      is UNCHANGED.
--
-- Usage/par (recipe-driven) and COGS (keys off the consumed lot) are untouched.
--
-- Source bodies (verified newest CREATE OR REPLACE per function):
--   _deduct_origin_fifo              -> 20260623000004
--   deduct_one_roast                 -> 20260707000003
--   recompute_origin_lot_consumption -> 20260707000006
--   _roast_affected_origins          -> 20260707000003
--   roast_log_lot_recompute          -> 20260707000003
--   delete_roasts                    -> 20260707000003

-- ── 1. _deduct_origin_fifo: add forced-source draw ──────────────────────────
-- Drop BOTH pre-existing overloads before installing the 8-arg body, so the new
-- trailing DEFAULT arg can't leave a stale, arity-ambiguous overload behind.
-- Prod currently carries two:
--   (…,timestamp)        — 6-arg, NO defaults. DEAD: its only caller is
--                          deduct_from_lot_on_roast (5-arg call, and that
--                          function is attached to zero live triggers — verified
--                          pg_trigger). Left over from the pre-borrow engine.
--   (…,timestamp,text)   — 7-arg, the current live one (deduct_one_roast +
--                          recompute_origin_lot_consumption call it with 7 args).
-- Dropping the dead 6-arg also removes a latent ambiguity: a bare 6-arg call
-- would otherwise match both the exact 6-arg AND the new 8-arg (args 7–8 default).
DROP FUNCTION IF EXISTS public._deduct_origin_fifo(text, text, text, numeric, text, timestamp without time zone);
DROP FUNCTION IF EXISTS public._deduct_origin_fifo(text, text, text, numeric, text, timestamp without time zone, text);

CREATE OR REPLACE FUNCTION public._deduct_origin_fifo(
    p_roast_log_id text, p_origin_id text, p_facility_id text, p_lbs numeric,
    p_preferred_source text, p_roast_date timestamp without time zone,
    p_force_origin_purchase_id text DEFAULT NULL,
    p_force_source_id text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE
    v_lot record;
    v_alloc_total numeric := 0;
    v_lbs_alloc numeric;
BEGIN
    IF COALESCE(p_lbs, 0) <= 0 THEN RETURN; END IF;
    FOR v_lot IN
        SELECT cip.origin_purchase_id, cip.remaining_lbs
          FROM public.coffee_inventory_purchased cip
          LEFT JOIN public.shipment_received sr ON sr.shipment_id = cip.shipment_id
         WHERE cip.facility_id = p_facility_id
           AND COALESCE(cip.remaining_lbs, 0) > 0
           -- the cited group's lots, PLUS the explicitly-borrowed lot (any group),
           -- PLUS (source-true) every lot of the forced source (any group)
           AND (cip.origin = p_origin_id
                OR cip.origin_purchase_id = p_force_origin_purchase_id
                OR (p_force_source_id IS NOT NULL AND cip.coffee_source_id = p_force_source_id))
           -- existed at roast time — the forced LOT is exempt (deliberate pick);
           -- forced-SOURCE lots are NOT exempt (a source draw still respects
           -- roast-time availability, exactly like an in-group FIFO draw).
           AND (cip.origin_purchase_id = p_force_origin_purchase_id
                OR p_roast_date IS NULL
                OR COALESCE(sr.date_received, cip.created_at::date) <= p_roast_date::date)
         ORDER BY
           -- forced (borrowed) lot first, then the forced source (FIFO within it),
           -- then preferred source, then FIFO
           CASE WHEN cip.origin_purchase_id = p_force_origin_purchase_id THEN 0 ELSE 1 END,
           CASE WHEN p_force_source_id IS NOT NULL
                     AND cip.coffee_source_id = p_force_source_id THEN 0 ELSE 1 END,
           CASE WHEN p_preferred_source IS NOT NULL
                     AND cip.coffee_source_id = p_preferred_source THEN 0 ELSE 1 END,
           COALESCE(sr.date_received, cip.created_at::date) ASC,
           cip.created_at ASC
    LOOP
        IF v_alloc_total >= p_lbs THEN EXIT; END IF;
        v_lbs_alloc := LEAST(v_lot.remaining_lbs, p_lbs - v_alloc_total);
        IF v_lbs_alloc <= 0 THEN CONTINUE; END IF;
        UPDATE public.coffee_inventory_purchased
           SET remaining_lbs = remaining_lbs - v_lbs_alloc
         WHERE origin_purchase_id = v_lot.origin_purchase_id;
        INSERT INTO public.roast_log_lot_consumption (roast_log_id, origin_purchase_id, lbs_consumed)
          VALUES (p_roast_log_id, v_lot.origin_purchase_id, v_lbs_alloc);
        v_alloc_total := v_alloc_total + v_lbs_alloc;
    END LOOP;
END;
$function$;

-- ── 2. _roast_affected_origins: union in cross-group lender homes ────────────
-- New optional p_planned_lots arg (backward compatible — every existing 2-arg
-- call still works). For a Pre-Blend recipe, union in the coffee_source.origin_id
-- (lender home group) of every planned source whose home differs from the
-- component it is planned for. This makes every writer lock the lender group and
-- the delete/edit trigger enqueue its recompute. Drop the stale 2-arg overload
-- first — keeping it alongside the new (text,text,jsonb DEFAULT NULL) makes every
-- 2-arg call ambiguous ("function is not unique"); 2-arg callers now bind here via
-- the default (identical behavior, p_planned_lots = NULL).
DROP FUNCTION IF EXISTS public._roast_affected_origins(text, text);
CREATE OR REPLACE FUNCTION public._roast_affected_origins(
    p_recipe_id text, p_origin_id text, p_planned_lots jsonb DEFAULT NULL)
RETURNS text[] LANGUAGE plpgsql STABLE AS $function$
DECLARE
    v_rt text;
    v_res text[];
    v_lenders text[];
BEGIN
    IF p_recipe_id IS NOT NULL THEN
        SELECT roast_type INTO v_rt FROM public.roast_recipes WHERE recipe_id = p_recipe_id;
    END IF;
    IF v_rt = 'Pre-Blend' THEN
        -- Sorted: every caller locks origins in the same order.
        SELECT array_agg(DISTINCT rc.coffee_item ORDER BY rc.coffee_item) INTO v_res
          FROM public.recipe_components rc
         WHERE rc.recipe_id = p_recipe_id AND rc.coffee_item IS NOT NULL;
        -- Cross-group planned sources: add each lender home group so its lots
        -- (which the borrowed component consumes) are locked + recomputed too.
        IF p_planned_lots IS NOT NULL AND jsonb_typeof(p_planned_lots) = 'object' THEN
            SELECT array_agg(DISTINCT cs.origin_id) INTO v_lenders
              FROM jsonb_each_text(p_planned_lots) pl
              JOIN public.coffee_source cs ON cs.coffee_source_id = pl.value
             WHERE cs.origin_id IS NOT NULL
               AND cs.origin_id IS DISTINCT FROM pl.key;  -- cross-group only
            IF v_lenders IS NOT NULL THEN
                SELECT array_agg(DISTINCT x ORDER BY x) INTO v_res
                  FROM unnest(COALESCE(v_res, '{}') || v_lenders) AS x;
            END IF;
        END IF;
        RETURN COALESCE(v_res, '{}');
    ELSIF p_origin_id IS NOT NULL THEN
        RETURN ARRAY[p_origin_id];
    ELSE
        RETURN '{}';
    END IF;
END;
$function$;

-- ── 3. recompute_origin_lot_consumption: source-true replay ─────────────────
-- Body = 20260707000006 verbatim + the source-true additions:
--   * membership: also pick up a pre-blend roast whose planned source resolves
--     cross-group INTO p_origin_id (this origin is the lender).
--   * per-effective-group deduction: the existing single-component path handles
--     the NATIVE component of p_origin_id but is SKIPPED when that component's
--     planned source is cross-group (it's owned by the lender group instead);
--     a new inner loop then deducts every component borrowed INTO p_origin_id,
--     forcing each planned source.
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
    v_bc record;              -- borrowed-INTO-p_origin_id component (source-true)
    v_native_source text;     -- planned source of the native component of p_origin_id
    v_native_xgroup boolean;  -- is that native component's planned source cross-group?
BEGIN
    IF p_origin_id IS NULL OR p_facility_id IS NULL THEN RETURN; END IF;

    -- Serialize allocation writers per (origin, facility) — see 20260707000003.
    PERFORM pg_advisory_xact_lock(hashtext(p_origin_id), hashtext(p_facility_id));

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

    -- Wipe ONLY what the replay re-derives: consumption of roasts AFTER the
    -- anchor. Pre-anchor rows are preserved as history — deleting them (the
    -- old behavior) permanently erased pre-count lot attribution AND degraded
    -- those roasts' stamped costs on EVERY count (measured: a June-30 blend
    -- dropped green_cost $178.20 -> $92.88 when a count landed on one of its
    -- components). remaining_lbs is re-seeded from counts above (physical
    -- truth), so preserved history never affects the arithmetic — the replay
    -- only allocates post-anchor roasts from the re-seeded values.
    DELETE FROM public.roast_log_lot_consumption rlc
     USING public.coffee_inventory_purchased cip, public.roast_log rl
     WHERE rlc.origin_purchase_id = cip.origin_purchase_id
       AND cip.origin = p_origin_id AND cip.facility_id = p_facility_id
       AND rl.roast_log_id = rlc.roast_log_id
       AND (v_last_count_at IS NULL
            OR COALESCE(rl.roast_date_utc, (rl.roast_date AT TIME ZONE v_tz)) > v_last_count_at);

    <<roast_loop>>
    FOR v_roast IN
        SELECT rl.roast_log_id, rl.charge_weight_lbs, rl.coffee_source_id,
               rl.recipe_id, rl.origin_id, rl.roast_date, rl.created_at,
               rl.borrow_origin_purchase_id, rl.planned_lots, rr.roast_type,
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
                     AND (
                       -- native: a component of THIS origin (unchanged membership)
                       EXISTS (SELECT 1 FROM public.recipe_components rc
                                WHERE rc.recipe_id = rl.recipe_id
                                  AND rc.coffee_item = p_origin_id
                                  AND COALESCE(rc.percentage, 0) > 0)
                       -- source-true: a component BORROWED into this origin (its
                       -- planned source is homed in p_origin_id but the component
                       -- itself is a different group)
                       OR EXISTS (
                            SELECT 1
                              FROM jsonb_each_text(rl.planned_lots) pl
                              JOIN public.coffee_source cs ON cs.coffee_source_id = pl.value
                              JOIN public.recipe_components rc2 ON rc2.recipe_id = rl.recipe_id
                                                              AND rc2.coffee_item = pl.key
                             WHERE jsonb_typeof(rl.planned_lots) = 'object'
                               AND cs.origin_id = p_origin_id
                               AND cs.origin_id IS DISTINCT FROM pl.key
                               AND COALESCE(rc2.percentage, 0) > 0)
                     ))
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
            PERFORM public._deduct_origin_fifo(
                v_roast.roast_log_id, p_origin_id, p_facility_id, v_needed, v_pref, v_roast.roast_date, v_force, NULL);
        ELSIF v_roast.roast_type = 'Pre-Blend' THEN
            -- (a) NATIVE component of p_origin_id. This is the byte-identical
            -- same-group path — UNLESS this component's own planned source is
            -- cross-group, in which case it is owned by the lender group's replay
            -- and must be skipped here (else it would double-count).
            SELECT v_roast.charge_weight_lbs * COALESCE(rc.percentage, 0)
              INTO v_needed
              FROM public.recipe_components rc
             WHERE rc.recipe_id = v_roast.recipe_id AND rc.coffee_item = p_origin_id
             ORDER BY rc.percentage DESC LIMIT 1;

            v_native_source := NULLIF(v_roast.planned_lots ->> p_origin_id, '');
            v_native_xgroup := false;
            IF v_native_source IS NOT NULL THEN
                SELECT (cs.origin_id IS DISTINCT FROM p_origin_id)
                  INTO v_native_xgroup
                  FROM public.coffee_source cs WHERE cs.coffee_source_id = v_native_source;
                v_native_xgroup := COALESCE(v_native_xgroup, false);
            END IF;

            IF COALESCE(v_needed, 0) > 0 AND NOT v_native_xgroup THEN
                -- Per-component planned source (Edit Roast / Add Roast picker) wins:
                -- it's how a blend's individual components get re-attributed.
                -- (Restores 20260625000002, silently dropped by the 20260703000005 rewrite.)
                v_pref := v_native_source;
                IF v_pref IS NULL AND v_roast.coffee_source_id IS NOT NULL THEN
                    SELECT CASE WHEN cs.origin_id = p_origin_id THEN v_roast.coffee_source_id ELSE NULL END
                      INTO v_pref FROM public.coffee_source cs WHERE cs.coffee_source_id = v_roast.coffee_source_id;
                END IF;
                PERFORM public._deduct_origin_fifo(
                    v_roast.roast_log_id, p_origin_id, p_facility_id, v_needed, v_pref, v_roast.roast_date, NULL, NULL);
            END IF;

            -- (b) SOURCE-TRUE: every component BORROWED into p_origin_id. Each
            -- draws its own component percentage, forcing its planned source
            -- (whose lots live here in p_origin_id). One roast can borrow more
            -- than one component into the same lender group.
            -- One row per planned-lots component (jsonb_each_text is already
            -- one-per-key); percentage is a scalar subquery taking the MAX row,
            -- exactly like deduct_one_roast (ORDER BY percentage DESC LIMIT 1). A
            -- plain JOIN to recipe_components would multiply the draw if a recipe
            -- ever carried duplicate (recipe_id, coffee_item) rows.
            FOR v_bc IN
                SELECT pl.key AS component_origin, pl.value AS source_id,
                       v_roast.charge_weight_lbs * (
                         SELECT COALESCE(rc2.percentage, 0)
                           FROM public.recipe_components rc2
                          WHERE rc2.recipe_id = v_roast.recipe_id
                            AND rc2.coffee_item = pl.key
                          ORDER BY rc2.percentage DESC LIMIT 1) AS needed
                  FROM jsonb_each_text(v_roast.planned_lots) pl
                  JOIN public.coffee_source cs ON cs.coffee_source_id = pl.value
                 WHERE jsonb_typeof(v_roast.planned_lots) = 'object'
                   AND cs.origin_id = p_origin_id
                   AND cs.origin_id IS DISTINCT FROM pl.key
                   AND EXISTS (SELECT 1 FROM public.recipe_components rc3
                                WHERE rc3.recipe_id = v_roast.recipe_id
                                  AND rc3.coffee_item = pl.key
                                  AND COALESCE(rc3.percentage, 0) > 0)
            LOOP
                IF COALESCE(v_bc.needed, 0) <= 0 THEN CONTINUE; END IF;
                PERFORM public._deduct_origin_fifo(
                    v_roast.roast_log_id, v_bc.component_origin, p_facility_id,
                    v_bc.needed, NULL, v_roast.roast_date, NULL, v_bc.source_id);
            END LOOP;

            -- (a) and (b) already issued every _deduct_origin_fifo for this roast;
            -- skip the common tail call below (advance the OUTER roast loop).
            CONTINUE roast_loop;
        ELSE
            v_needed := v_roast.charge_weight_lbs;
            v_pref := NULL;
            IF v_roast.coffee_source_id IS NOT NULL THEN
                SELECT CASE WHEN cs.origin_id = p_origin_id THEN v_roast.coffee_source_id ELSE NULL END
                  INTO v_pref FROM public.coffee_source cs WHERE cs.coffee_source_id = v_roast.coffee_source_id;
            END IF;
            -- Single-origin fallback: honor planned_lots[origin] only when there
            -- is no coffee_source_id pick (coffee_source_id stays authoritative).
            IF v_pref IS NULL THEN
                v_pref := NULLIF(v_roast.planned_lots ->> p_origin_id, '');
            END IF;
            PERFORM public._deduct_origin_fifo(
                v_roast.roast_log_id, p_origin_id, p_facility_id, v_needed, v_pref, v_roast.roast_date, v_force, NULL);
        END IF;
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

-- ── 4. deduct_one_roast: source-true first deduct ───────────────────────────
-- Body = 20260707000003 verbatim + the source-true additions:
--   * affected-origins now includes cross-group lender homes (planned_lots
--     passed in) so those groups are locked too.
--   * per-component: if a pre-blend component's planned source is cross-group,
--     force that source (v_force_source); v_pref stays NULL. Same-group / no-pick
--     components are byte-identical (v_force_source NULL, v_pref as before).
-- Note: the FOREACH loop now also visits lender-group origins. A lender origin
-- has no recipe_component (rc.coffee_item = o is empty) so its native v_needed is
-- 0 → CONTINUE; the borrowed component is deducted when the loop reaches the
-- COMPONENT origin o (via v_force_source), keyed to o, drawing the lender lots.
CREATE OR REPLACE FUNCTION public.deduct_one_roast(p_roast_log_id text)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE
    rl record;
    o text;
    v_needed numeric;
    v_pref text;
    v_force text;
    v_force_source text;
    v_borrow_home text;
BEGIN
    SELECT rl2.roast_log_id, rl2.facility_id, rl2.charge_weight_lbs, rl2.coffee_source_id,
           rl2.recipe_id, rl2.origin_id, rl2.roast_date, rl2.created_at,
           rl2."charged?" AS charged, rl2.external_roast_id, rl2.borrow_origin_purchase_id,
           rl2.planned_lots, rr.roast_type
      INTO rl
      FROM public.roast_log rl2
      LEFT JOIN public.roast_recipes rr ON rr.recipe_id = rl2.recipe_id
     WHERE rl2.roast_log_id = p_roast_log_id;
    IF NOT FOUND THEN RETURN; END IF;

    IF rl.charged IS NOT TRUE OR COALESCE(rl.charge_weight_lbs, 0) <= 0 THEN RETURN; END IF;
    IF rl.external_roast_id IS NULL
       AND rl.roast_date < (rl.created_at::date - interval '1 day') THEN RETURN; END IF;
    IF rl.facility_id IS NULL THEN RETURN; END IF;
    IF EXISTS (SELECT 1 FROM public.roast_log_lot_consumption WHERE roast_log_id = p_roast_log_id) THEN RETURN; END IF;

    -- Same per-origin serialization as recompute (see there) — a charge waits
    -- out any in-flight replay on its origins instead of interleaving. Affected
    -- origins now include cross-group lender homes (planned_lots passed in).
    FOREACH o IN ARRAY public._roast_affected_origins(rl.recipe_id, rl.origin_id, rl.planned_lots) LOOP
        PERFORM pg_advisory_xact_lock(hashtext(o), hashtext(rl.facility_id));
    END LOOP;

    FOREACH o IN ARRAY public._roast_affected_origins(rl.recipe_id, rl.origin_id, rl.planned_lots) LOOP
        IF rl.roast_type = 'Pre-Blend' THEN
            SELECT rl.charge_weight_lbs * COALESCE(rc.percentage, 0) INTO v_needed
              FROM public.recipe_components rc
             WHERE rc.recipe_id = rl.recipe_id AND rc.coffee_item = o
             ORDER BY rc.percentage DESC LIMIT 1;
        ELSE
            v_needed := rl.charge_weight_lbs;
        END IF;
        IF COALESCE(v_needed, 0) <= 0 THEN CONTINUE; END IF;

        -- Preferred source: blend components take their planned_lots pick first
        -- (the Add/Edit per-component picker), then the single coffee_source_id;
        -- single-origin keeps coffee_source_id authoritative with planned_lots
        -- as the fallback. Mirrors recompute_origin_lot_consumption.
        --
        -- Source-true: if a pre-blend component's planned source is cross-group
        -- (its home origin_id <> the component origin o), FORCE that source so
        -- the deduct draws the source's own lots (which live in another group),
        -- not this component group's native FIFO. v_pref stays NULL in that case.
        v_pref := NULL;
        v_force_source := NULL;
        IF rl.roast_type = 'Pre-Blend' THEN
            v_pref := NULLIF(rl.planned_lots ->> o, '');
            IF v_pref IS NOT NULL THEN
                SELECT CASE WHEN cs.origin_id IS DISTINCT FROM o THEN v_pref ELSE NULL END
                  INTO v_force_source
                  FROM public.coffee_source cs WHERE cs.coffee_source_id = v_pref;
                -- Cross-group: the planned source becomes a forced source, and the
                -- in-group preference no longer applies (its lots aren't in o).
                IF v_force_source IS NOT NULL THEN
                    v_pref := NULL;
                END IF;
            END IF;
        END IF;
        IF v_pref IS NULL AND v_force_source IS NULL AND rl.coffee_source_id IS NOT NULL THEN
            SELECT CASE WHEN cs.origin_id = o THEN rl.coffee_source_id ELSE NULL END
              INTO v_pref FROM public.coffee_source cs WHERE cs.coffee_source_id = rl.coffee_source_id;
        END IF;
        IF v_pref IS NULL AND v_force_source IS NULL AND rl.roast_type IS DISTINCT FROM 'Pre-Blend' THEN
            v_pref := NULLIF(rl.planned_lots ->> o, '');
        END IF;

        -- Borrow applies to single-origin / post-blend only (one affected origin).
        v_force := NULL;
        IF rl.roast_type IS DISTINCT FROM 'Pre-Blend'
           AND o = rl.origin_id AND rl.borrow_origin_purchase_id IS NOT NULL THEN
            v_force := rl.borrow_origin_purchase_id;
        END IF;

        PERFORM public._deduct_origin_fifo(rl.roast_log_id, o, rl.facility_id, v_needed, v_pref, rl.roast_date, v_force, v_force_source);
        PERFORM public.recalculate_origin_total_stock(o, rl.facility_id);
    END LOOP;

    -- Source-true parity with the replay's per-origin reconcile: a cross-group
    -- component drew from a LENDER group's lots, but the FOREACH iteration for that
    -- lender computed v_needed=0 (it is not a recipe component) and skipped its
    -- recalculate_origin_total_stock. Refresh each cross-group lender home so its
    -- in_stock/total_stock cache is not left stale-high on the first-deduct path.
    IF rl.roast_type = 'Pre-Blend' AND jsonb_typeof(rl.planned_lots) = 'object' THEN
        FOR o IN
            SELECT DISTINCT cs.origin_id
              FROM jsonb_each_text(rl.planned_lots) pl
              JOIN public.coffee_source cs ON cs.coffee_source_id = pl.value
             WHERE cs.origin_id IS DISTINCT FROM pl.key
        LOOP
            PERFORM public.recalculate_origin_total_stock(o, rl.facility_id);
        END LOOP;
    END IF;

    -- Refresh the lender lot's home group (the bean physically left it).
    IF rl.borrow_origin_purchase_id IS NOT NULL THEN
        SELECT cip.origin INTO v_borrow_home
          FROM public.coffee_inventory_purchased cip
         WHERE cip.origin_purchase_id = rl.borrow_origin_purchase_id;
        IF v_borrow_home IS NOT NULL THEN
            PERFORM public.recalculate_origin_total_stock(v_borrow_home, rl.facility_id);
        END IF;
    END IF;
END;
$function$;

-- ── 5. roast_log_lot_recompute trigger: enqueue lender groups ───────────────
-- Body = 20260707000003 verbatim + pass planned_lots into _roast_affected_origins
-- so DELETE / retro-UPDATE enqueue the lender group's recompute (a cross-group
-- pre-blend consumes lots that physically live in the lender group). The explicit
-- borrow_origin_purchase_id lender path is unchanged.
CREATE OR REPLACE FUNCTION public.roast_log_lot_recompute()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    o text;
    v_lender text;
BEGIN
    IF current_setting('app.defer_lot_recompute', true) = 'true' THEN RETURN NULL; END IF;

    IF TG_OP = 'INSERT' THEN
        IF NEW."charged?" = true THEN
            PERFORM public.deduct_one_roast(NEW.roast_log_id);
        END IF;
        RETURN NULL;
    END IF;

    IF TG_OP = 'DELETE' THEN
        IF OLD."charged?" = true AND OLD.facility_id IS NOT NULL THEN
            FOREACH o IN ARRAY public._roast_affected_origins(OLD.recipe_id, OLD.origin_id, OLD.planned_lots) LOOP
                PERFORM public.recompute_or_enqueue(o, OLD.facility_id, OLD.company_id, 'roast delete');
            END LOOP;
            IF OLD.borrow_origin_purchase_id IS NOT NULL THEN
                SELECT origin INTO v_lender FROM public.coffee_inventory_purchased
                 WHERE origin_purchase_id = OLD.borrow_origin_purchase_id;
                IF v_lender IS NOT NULL THEN
                    PERFORM public.recompute_or_enqueue(v_lender, OLD.facility_id, OLD.company_id, 'roast delete (lender)');
                END IF;
            END IF;
        END IF;
        RETURN NULL;
    END IF;

    -- UPDATE: fresh charge (false→true) → fast incremental deduct.
    IF COALESCE(OLD."charged?", false) = false AND NEW."charged?" = true THEN
        PERFORM public.deduct_one_roast(NEW.roast_log_id);
        RETURN NULL;
    END IF;

    -- Retroactive change to a charged roast (or un-charge) → full replay.
    IF (COALESCE(OLD."charged?", false) = true AND COALESCE(NEW."charged?", false) = false)
       OR (NEW."charged?" = true AND (
              NEW.charge_weight_lbs IS DISTINCT FROM OLD.charge_weight_lbs OR
              NEW.charge_weight     IS DISTINCT FROM OLD.charge_weight OR
              NEW.origin_id         IS DISTINCT FROM OLD.origin_id OR
              NEW.recipe_id         IS DISTINCT FROM OLD.recipe_id OR
              NEW.coffee_source_id  IS DISTINCT FROM OLD.coffee_source_id OR
              NEW.planned_lots      IS DISTINCT FROM OLD.planned_lots OR
              NEW.borrow_origin_purchase_id IS DISTINCT FROM OLD.borrow_origin_purchase_id))
    THEN
        -- FAST PATH: a still-charged roast with NO consumption yet has never been
        -- deducted (e.g. an impromptu roast whose recipe/origin/charge were NULL
        -- at charge and are filled in now). This is a FIRST deduct, not a
        -- re-attribution — do it incrementally instead of replaying the whole
        -- origin's history. deduct_one_roast no-ops when charge_weight_lbs<=0.
        IF COALESCE(NEW."charged?", false) = true
           AND NOT EXISTS (SELECT 1 FROM public.roast_log_lot_consumption
                            WHERE roast_log_id = NEW.roast_log_id) THEN
            PERFORM public.deduct_one_roast(NEW.roast_log_id);
            RETURN NULL;
        END IF;

        IF NEW.facility_id IS NOT NULL THEN
            FOREACH o IN ARRAY public._roast_affected_origins(NEW.recipe_id, NEW.origin_id, NEW.planned_lots) LOOP
                PERFORM public.recompute_or_enqueue(o, NEW.facility_id, NEW.company_id, 'retro roast edit');
            END LOOP;
            IF NEW.borrow_origin_purchase_id IS NOT NULL THEN
                SELECT origin INTO v_lender FROM public.coffee_inventory_purchased
                 WHERE origin_purchase_id = NEW.borrow_origin_purchase_id;
                IF v_lender IS NOT NULL THEN
                    PERFORM public.recompute_or_enqueue(v_lender, NEW.facility_id, NEW.company_id, 'retro roast edit (lender)');
                END IF;
            END IF;
        END IF;
        IF OLD.facility_id IS NOT NULL THEN
            FOREACH o IN ARRAY public._roast_affected_origins(OLD.recipe_id, OLD.origin_id, OLD.planned_lots) LOOP
                PERFORM public.recompute_or_enqueue(o, OLD.facility_id, OLD.company_id, 'roast delete');
            END LOOP;
            -- OLD lender (covers re-pointing the borrow to a different lot/group)
            IF OLD.borrow_origin_purchase_id IS NOT NULL
               AND OLD.borrow_origin_purchase_id IS DISTINCT FROM NEW.borrow_origin_purchase_id THEN
                SELECT origin INTO v_lender FROM public.coffee_inventory_purchased
                 WHERE origin_purchase_id = OLD.borrow_origin_purchase_id;
                IF v_lender IS NOT NULL THEN
                    PERFORM public.recompute_or_enqueue(v_lender, OLD.facility_id, OLD.company_id, 'roast delete (lender)');
                END IF;
            END IF;
        END IF;
    END IF;
    RETURN NULL;
END;
$function$;

-- ── 6. delete_roasts: see the lender group as affected ──────────────────────
-- Body = 20260707000003 verbatim + one membership addition. The needs_replay
-- probe checks whether any surviving charged roast still consumes the deleted
-- origin's lots; for a cross-group pre-blend that means a roast whose planned
-- source is homed in d.origin (the lender) — add that to the OR set. Everything
-- else is byte-identical (the explicit borrow_origin_purchase_id path unchanged).
CREATE OR REPLACE FUNCTION public.delete_roasts(p_roast_log_ids text[])
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_o record;
BEGIN
    IF p_roast_log_ids IS NULL OR array_length(p_roast_log_ids, 1) IS NULL THEN
        RETURN;
    END IF;

    CREATE TEMP TABLE _del_cons ON COMMIT DROP AS
    SELECT rlc.origin_purchase_id,
           cip.origin        AS origin,
           rl.facility_id     AS facility_id,
           rl.company_id      AS company_id,
           rlc.lbs_consumed   AS lbs_consumed,
           COALESCE(rl.roast_date_utc,
                    (rl.roast_date AT TIME ZONE COALESCE(NULLIF(f.time_zone, ''), 'UTC'))) AS roast_utc
      FROM public.roast_log_lot_consumption rlc
      JOIN public.coffee_inventory_purchased cip ON cip.origin_purchase_id = rlc.origin_purchase_id
      JOIN public.roast_log rl ON rl.roast_log_id = rlc.roast_log_id
      LEFT JOIN public.facilities f ON f.facility_id = rl.facility_id
     WHERE rlc.roast_log_id = ANY(p_roast_log_ids)
       AND cip.origin IS NOT NULL
       AND rl.facility_id IS NOT NULL;

    CREATE TEMP TABLE _del_origin ON COMMIT DROP AS
    SELECT origin, facility_id,
           MIN(company_id)            AS company_id,
           MIN(roast_utc)             AS min_utc,
           bool_or(roast_utc IS NULL) AS has_null_utc
      FROM _del_cons
     GROUP BY origin, facility_id;

    ALTER TABLE _del_origin ADD COLUMN needs_replay boolean;

    UPDATE _del_origin d
       SET needs_replay = d.has_null_utc OR d.min_utc IS NULL OR EXISTS (
            SELECT 1
              FROM public.roast_log rl2
              LEFT JOIN public.roast_recipes rr2 ON rr2.recipe_id = rl2.recipe_id
              LEFT JOIN public.facilities f2 ON f2.facility_id = rl2.facility_id
             WHERE rl2.facility_id = d.facility_id
               AND rl2."charged?" = true
               AND COALESCE(rl2.charge_weight_lbs, 0) > 0
               AND NOT (rl2.roast_log_id = ANY(p_roast_log_ids))
               AND (rl2.external_roast_id IS NOT NULL
                    OR rl2.roast_date >= (rl2.created_at::date - interval '1 day'))
               AND COALESCE(rl2.roast_date_utc,
                            (rl2.roast_date AT TIME ZONE COALESCE(NULLIF(f2.time_zone, ''), 'UTC'))) >= d.min_utc
               AND (
                    (rl2.borrow_origin_purchase_id IS NULL AND (
                        (rr2.roast_type = 'Pre-Blend'
                           AND (
                             -- native component of the deleted origin
                             EXISTS (SELECT 1 FROM public.recipe_components rc
                                      WHERE rc.recipe_id = rl2.recipe_id
                                        AND rc.coffee_item = d.origin
                                        AND COALESCE(rc.percentage, 0) > 0)
                             -- source-true: a component BORROWED into d.origin
                             -- (its planned source is homed in the deleted origin)
                             OR EXISTS (
                                  SELECT 1
                                    FROM jsonb_each_text(rl2.planned_lots) pl
                                    JOIN public.coffee_source cs ON cs.coffee_source_id = pl.value
                                    JOIN public.recipe_components rc2 ON rc2.recipe_id = rl2.recipe_id
                                                                    AND rc2.coffee_item = pl.key
                                   WHERE jsonb_typeof(rl2.planned_lots) = 'object'
                                     AND cs.origin_id = d.origin
                                     AND cs.origin_id IS DISTINCT FROM pl.key
                                     AND COALESCE(rc2.percentage, 0) > 0)
                           ))
                        OR ((rr2.roast_type IS NULL OR rr2.roast_type <> 'Pre-Blend')
                              AND rl2.origin_id = d.origin)))
                    OR (rl2.borrow_origin_purchase_id IS NOT NULL
                          AND EXISTS (SELECT 1 FROM public.coffee_inventory_purchased b
                                       WHERE b.origin_purchase_id = rl2.borrow_origin_purchase_id
                                         AND b.origin = d.origin))
               )
       )
     WHERE true;  -- update every row; explicit WHERE satisfies pg_safeupdate (REST)

    UPDATE public.coffee_inventory_purchased cip
       SET remaining_lbs = COALESCE(cip.remaining_lbs, 0) + agg.lbs
      FROM (
        SELECT c.origin_purchase_id, SUM(c.lbs_consumed) AS lbs
          FROM _del_cons c
          JOIN _del_origin d ON d.origin = c.origin AND d.facility_id = c.facility_id
         WHERE d.needs_replay = false
         GROUP BY c.origin_purchase_id
      ) agg
     WHERE cip.origin_purchase_id = agg.origin_purchase_id;

    PERFORM set_config('app.defer_lot_recompute', 'true', true);
    DELETE FROM public.roast_log WHERE roast_log_id = ANY(p_roast_log_ids);
    PERFORM set_config('app.defer_lot_recompute', 'false', true);

    FOR v_o IN SELECT origin, facility_id, company_id, needs_replay FROM _del_origin LOOP
        IF v_o.needs_replay THEN
            -- Incremental reversal above already restored this origin's totals;
            -- the exact FIFO re-attribution can go deep — route through the
            -- depth guard (inline when shallow, queued when deep).
            PERFORM public.recompute_or_enqueue(v_o.origin, v_o.facility_id, v_o.company_id, 'mid-history roast delete');
        ELSE
            PERFORM public.recalculate_origin_total_stock(v_o.origin, v_o.facility_id);
        END IF;
        PERFORM public.refresh_coffee_stock_par(v_o.origin, v_o.facility_id);
    END LOOP;
END;
$$;

NOTIFY pgrst, 'reload schema';
