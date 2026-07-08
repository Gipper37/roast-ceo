-- Phase 2 of the lot-engine rearchitecture: origin-keyed async reconcile queue.
--
-- Phases 0+1 made replays sub-second for COUNTED origins (valuation batching),
-- but replay depth is operator-behavior-dependent: never/stale-counted origins
-- still replay thousands of roasts (~12-15s loop-bound), and a multi-origin
-- shipment receive stacks one replay per origin inside the operator's save.
--
-- This migration moves the DEEP work off the request path, NetSuite/BC-style:
--   * lot_recompute_queue — one pending row per (origin, facility), coalescing
--     bursts (ON CONFLICT DO NOTHING; the replay is absolute, so one drain
--     covers every edit before it).
--   * recompute_or_enqueue — depth guard: post-watermark charged-roast count
--     <= 400 replays INLINE (counted origins stay instant + synchronous,
--     unchanged UX); deeper goes to the queue and converges in <=~30s.
--   * drain_lot_recompute_queue — pg_cron PROCEDURE every 15s; one queue row
--     per transaction (COMMIT between rows) so row locks never make a user
--     save wait behind a long drain; 3 attempts then status=failed+SQLERRM.
--   * per-(origin,facility) advisory xact locks in recompute + deduct_one_roast
--     so a live charge and a drainer replay can never interleave; components
--     lock in sorted order (deadlock-safe).
-- Count-insert reseeds stay fully synchronous by design (the operator expects
-- counted numbers to BE the stock when the modal closes; a count also SETS the
-- watermark, making its own replay shallow).

-- ── 1. Deterministic origin order (lock ordering => no deadlocks) ───────────
CREATE OR REPLACE FUNCTION public._roast_affected_origins(p_recipe_id text, p_origin_id text)
RETURNS text[] LANGUAGE plpgsql STABLE AS $function$
DECLARE
    v_rt text;
    v_res text[];
BEGIN
    IF p_recipe_id IS NOT NULL THEN
        SELECT roast_type INTO v_rt FROM public.roast_recipes WHERE recipe_id = p_recipe_id;
    END IF;
    IF v_rt = 'Pre-Blend' THEN
        -- Sorted: every caller locks origins in the same order.
        SELECT array_agg(DISTINCT rc.coffee_item ORDER BY rc.coffee_item) INTO v_res
          FROM public.recipe_components rc
         WHERE rc.recipe_id = p_recipe_id AND rc.coffee_item IS NOT NULL;
        RETURN COALESCE(v_res, '{}');
    ELSIF p_origin_id IS NOT NULL THEN
        RETURN ARRAY[p_origin_id];
    ELSE
        RETURN '{}';
    END IF;
END;
$function$;

-- ── 2. The queue ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.lot_recompute_queue (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    company_id   text NOT NULL,
    origin_id    text NOT NULL,
    facility_id  text NOT NULL,
    reason       text,
    requested_at timestamptz NOT NULL DEFAULT now(),
    scheduled_at timestamptz NOT NULL DEFAULT now() + interval '5 seconds',
    status       text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','failed')),
    attempts     int NOT NULL DEFAULT 0,
    last_error   text
);
-- One pending row per origin — bursts coalesce into a single drain.
CREATE UNIQUE INDEX IF NOT EXISTS lot_recompute_queue_pending_key
    ON public.lot_recompute_queue (origin_id, facility_id) WHERE status = 'pending';

ALTER TABLE public.lot_recompute_queue ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_company_access ON public.lot_recompute_queue;
CREATE POLICY tenant_company_access ON public.lot_recompute_queue
    USING (company_id IN (SELECT public.auth_company_ids()))
    WITH CHECK (company_id IN (SELECT public.auth_company_ids()));
-- Tenants enqueue (via triggers in their own transactions) and read (the
-- future "Recalculating" badge). Only the drainer (postgres) updates/deletes.
GRANT SELECT, INSERT ON public.lot_recompute_queue TO authenticated;

CREATE OR REPLACE FUNCTION public.enqueue_lot_recompute(
    p_company text, p_origin text, p_facility text, p_reason text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_company IS NULL OR p_origin IS NULL OR p_facility IS NULL THEN RETURN; END IF;
    -- DO NOTHING (not a debounce UPDATE): recompute is an absolute rebuild of
    -- final committed state, so an existing pending row already covers this
    -- edit — and NOT updating means we never block on a row the drainer holds.
    INSERT INTO public.lot_recompute_queue (company_id, origin_id, facility_id, reason)
    VALUES (p_company, p_origin, p_facility, p_reason)
    ON CONFLICT (origin_id, facility_id) WHERE status = 'pending' DO NOTHING;
END;
$$;

-- ── 3. Depth guard: inline when shallow, queue when deep ───────────────────
CREATE OR REPLACE FUNCTION public.recompute_or_enqueue(
    p_origin text, p_facility text, p_company text, p_reason text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_wm timestamptz;
    v_depth int;
BEGIN
    IF p_origin IS NULL OR p_facility IS NULL THEN RETURN; END IF;
    SELECT MAX(clc.count_at) INTO v_wm
      FROM public.coffee_lot_count clc
      JOIN public.coffee_inventory_purchased cip ON cip.origin_purchase_id = clc.origin_purchase_id
     WHERE cip.origin = p_origin AND cip.facility_id = p_facility;
    -- Facility-wide post-watermark charged-roast count: a cheap, conservative
    -- OVER-estimate of replay depth (the replay filters to this origin).
    SELECT count(*) INTO v_depth
      FROM public.roast_log rl
     WHERE rl.facility_id = p_facility
       AND rl."charged?" = true
       AND COALESCE(rl.charge_weight_lbs, 0) > 0
       AND (v_wm IS NULL OR COALESCE(rl.roast_date_utc, rl.roast_date::timestamptz) > v_wm);
    IF v_depth > 400 AND p_company IS NOT NULL THEN
        PERFORM public.enqueue_lot_recompute(p_company, p_origin, p_facility, p_reason);
    ELSE
        PERFORM public.recompute_origin_lot_consumption(p_origin, p_facility);
    END IF;
END;
$$;

-- ── 4. Rebased engine functions (advisory locks + queue routing) ────────────

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

    -- Serialize allocation writers per (origin, facility): replays, charges and
    -- the queue drainer take the same xact-scoped advisory lock, so a live
    -- charge can never interleave with a replay on the same origin. Xact-level
    -- only — session locks leak under Supavisor transaction pooling.
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

    DELETE FROM public.roast_log_lot_consumption rlc
     USING public.coffee_inventory_purchased cip
     WHERE rlc.origin_purchase_id = cip.origin_purchase_id
       AND cip.origin = p_origin_id AND cip.facility_id = p_facility_id;

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
            -- Per-component planned source (Edit Roast / Add Roast picker) wins:
            -- it's how a blend's individual components get re-attributed.
            -- (Restores 20260625000002, silently dropped by the 20260703000005 rewrite.)
            v_pref := NULLIF(v_roast.planned_lots ->> p_origin_id, '');
            IF v_pref IS NULL AND v_roast.coffee_source_id IS NOT NULL THEN
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
            -- Single-origin fallback: honor planned_lots[origin] only when there
            -- is no coffee_source_id pick (coffee_source_id stays authoritative).
            IF v_pref IS NULL THEN
                v_pref := NULLIF(v_roast.planned_lots ->> p_origin_id, '');
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

CREATE OR REPLACE FUNCTION public.deduct_one_roast(p_roast_log_id text)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE
    rl record;
    o text;
    v_needed numeric;
    v_pref text;
    v_force text;
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
    -- out any in-flight replay on its origins instead of interleaving.
    FOREACH o IN ARRAY public._roast_affected_origins(rl.recipe_id, rl.origin_id) LOOP
        PERFORM pg_advisory_xact_lock(hashtext(o), hashtext(rl.facility_id));
    END LOOP;

    FOREACH o IN ARRAY public._roast_affected_origins(rl.recipe_id, rl.origin_id) LOOP
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
        v_pref := NULL;
        IF rl.roast_type = 'Pre-Blend' THEN
            v_pref := NULLIF(rl.planned_lots ->> o, '');
        END IF;
        IF v_pref IS NULL AND rl.coffee_source_id IS NOT NULL THEN
            SELECT CASE WHEN cs.origin_id = o THEN rl.coffee_source_id ELSE NULL END
              INTO v_pref FROM public.coffee_source cs WHERE cs.coffee_source_id = rl.coffee_source_id;
        END IF;
        IF v_pref IS NULL AND rl.roast_type IS DISTINCT FROM 'Pre-Blend' THEN
            v_pref := NULLIF(rl.planned_lots ->> o, '');
        END IF;

        -- Borrow applies to single-origin / post-blend only (one affected origin).
        v_force := NULL;
        IF rl.roast_type IS DISTINCT FROM 'Pre-Blend'
           AND o = rl.origin_id AND rl.borrow_origin_purchase_id IS NOT NULL THEN
            v_force := rl.borrow_origin_purchase_id;
        END IF;

        PERFORM public._deduct_origin_fifo(rl.roast_log_id, o, rl.facility_id, v_needed, v_pref, rl.roast_date, v_force);
        PERFORM public.recalculate_origin_total_stock(o, rl.facility_id);
    END LOOP;

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
            FOREACH o IN ARRAY public._roast_affected_origins(OLD.recipe_id, OLD.origin_id) LOOP
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
            FOREACH o IN ARRAY public._roast_affected_origins(NEW.recipe_id, NEW.origin_id) LOOP
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
            FOREACH o IN ARRAY public._roast_affected_origins(OLD.recipe_id, OLD.origin_id) LOOP
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
                           AND EXISTS (SELECT 1 FROM public.recipe_components rc
                                        WHERE rc.recipe_id = rl2.recipe_id
                                          AND rc.coffee_item = d.origin
                                          AND COALESCE(rc.percentage, 0) > 0))
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

-- Shipment receive/void: route each origin through the depth guard (receive of
-- a multi-origin shipment stops stacking deep replays inside the save).
CREATE OR REPLACE FUNCTION public.shipment_lot_recompute()
RETURNS trigger LANGUAGE plpgsql AS $function$
DECLARE
    rec record;
BEGIN
    FOR rec IN
        SELECT DISTINCT origin, facility_id, company_id
          FROM public.coffee_inventory_purchased
         WHERE shipment_id = NEW.shipment_id
           AND origin IS NOT NULL AND facility_id IS NOT NULL
         ORDER BY origin
    LOOP
        PERFORM public.recompute_or_enqueue(rec.origin, rec.facility_id, rec.company_id, 'shipment receive/void');
    END LOOP;
    RETURN NULL;
END;
$function$;

-- ── 5. The drainer: pg_cron procedure, one queue row per transaction ────────
CREATE OR REPLACE PROCEDURE public.drain_lot_recompute_queue(p_max int DEFAULT 10)
LANGUAGE plpgsql AS $$
DECLARE
    r record;
BEGIN
    -- Only one drainer at a time (pg_cron does not serialize same-job runs).
    -- Session-level try-lock: released on disconnect (each cron run is its own
    -- connection), survives the per-row COMMITs below.
    IF NOT pg_try_advisory_lock(hashtext('lot_recompute_drainer'), 0) THEN RETURN; END IF;
    -- Session-level: survives COMMITs; a lock wait (origin busy with a live
    -- charge) errors the row into retry instead of stalling the drain.
    PERFORM set_config('lock_timeout', '10s', false);

    FOR i IN 1..p_max LOOP
        SELECT id, origin_id, facility_id INTO r
          FROM public.lot_recompute_queue
         WHERE status = 'pending' AND scheduled_at <= now()
         ORDER BY scheduled_at ASC
         FOR UPDATE SKIP LOCKED
         LIMIT 1;
        EXIT WHEN NOT FOUND;

        BEGIN
            PERFORM public.recompute_origin_lot_consumption(r.origin_id, r.facility_id);
            DELETE FROM public.lot_recompute_queue WHERE id = r.id;
        EXCEPTION WHEN OTHERS THEN
            UPDATE public.lot_recompute_queue
               SET attempts   = attempts + 1,
                   last_error = SQLERRM,
                   status     = CASE WHEN attempts + 1 >= 3 THEN 'failed' ELSE 'pending' END,
                   scheduled_at = now() + interval '60 seconds'
             WHERE id = r.id;
        END;
        -- Row lock (and the replay's advisory locks) released per item, so an
        -- operator save on the same origin never waits behind the whole drain.
        COMMIT;
    END LOOP;

    PERFORM pg_advisory_unlock(hashtext('lot_recompute_drainer'), 0);
END;
$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    -- Re-schedule idempotently.
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'lot_recompute_drain';
    PERFORM cron.schedule(
      'lot_recompute_drain',
      '15 seconds',
      $cron$CALL public.drain_lot_recompute_queue()$cron$
    );
  ELSE
    RAISE NOTICE 'pg_cron not installed — skipping lot_recompute_drain schedule';
  END IF;
END
$$;

NOTIFY pgrst, 'reload schema';
