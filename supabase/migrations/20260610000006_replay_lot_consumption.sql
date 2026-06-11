-- ============================================================================
-- Replay-based lot consumption (rebuild of the dormant lot-deduction system)
-- ============================================================================
-- The Phase-2 lot deduction (20260608000004) never actually worked:
--   * trg_deduct_from_lot_on_roast fired on INSERT ONLY, but every real roast
--     is charged via the staged-UPDATE path (LFP / copy / logger) — so the
--     trigger never saw the charge. Result: 0 consumption rows across 15,409
--     charged roasts, 54 of them since the lot system went live.
--   * the "skip historical import" guard compared roast_date (timestamp WITHOUT
--     tz, stamped in facility-LOCAL time) against created_at (timestamptz, UTC).
--     For any non-UTC facility (e.g. Pacific/Hawaii, UTC-10) every LIVE roast
--     looked ~10h older than its created_at and was wrongly skipped.
--   * 20260610000005 used pct/100, but recipe_components.percentage is a 0-1
--     fraction (sums to 1.0) — a 100x under-deduction for pre-blends.
--   * delete / un-charge never restored lot stock.
--
-- Rather than patch fragile incremental deduct/restore logic, this rebuilds the
-- lot layer as a REPLAY — exactly how calculate_current_stock_lbs already keeps
-- the (correct) headline in_stock number: reset lots to their received amount,
-- replay every charged live roast chronologically FIFO, rewrite the consumption
-- ledger. Idempotent by construction; delete/un-charge/edit all "just work"
-- because the next event re-derives the whole picture for the affected origin.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. FIFO deductor for ONE origin: drains the preferred (active) source's lots
--    first, then the rest of the origin oldest-first. Writes consumption rows.
--    Floors lots at 0 (never negative); a pre-charge UI check warns on shortfall.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._deduct_origin_fifo(
    p_roast_log_id text,
    p_origin_id text,
    p_facility_id text,
    p_lbs numeric,
    p_preferred_source text
) RETURNS void
LANGUAGE plpgsql
AS $$
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
         WHERE cip.origin = p_origin_id
           AND cip.facility_id = p_facility_id
           AND COALESCE(cip.remaining_lbs, 0) > 0
         ORDER BY
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
$$;

-- ----------------------------------------------------------------------------
-- 2. The replay: reset → replay all charged live roasts → rewrite ledger.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.recompute_origin_lot_consumption(
    p_origin_id text,
    p_facility_id text
) RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_roast record;
    v_needed numeric;
    v_pref text;
BEGIN
    IF p_origin_id IS NULL OR p_facility_id IS NULL THEN RETURN; END IF;

    -- 2a. Lots that are NOT available (un-received OR voided shipment) → NULL.
    UPDATE public.coffee_inventory_purchased cip
       SET remaining_lbs = NULL
     WHERE cip.origin = p_origin_id AND cip.facility_id = p_facility_id
       AND cip.shipment_id IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM public.shipment_received sr
          WHERE sr.shipment_id = cip.shipment_id
            AND sr.date_received IS NOT NULL
            AND COALESCE(sr.voided, false) = false);

    -- 2b. Available lots (received-non-voided OR quick-add) → reset to received amount.
    UPDATE public.coffee_inventory_purchased cip
       SET remaining_lbs = cip.amount
     WHERE cip.origin = p_origin_id AND cip.facility_id = p_facility_id
       AND cip.amount IS NOT NULL
       AND (
          cip.shipment_id IS NULL
          OR EXISTS (
            SELECT 1 FROM public.shipment_received sr
             WHERE sr.shipment_id = cip.shipment_id
               AND sr.date_received IS NOT NULL
               AND COALESCE(sr.voided, false) = false));

    -- 2c. Clear the prior consumption ledger for this origin's lots.
    DELETE FROM public.roast_log_lot_consumption rlc
     USING public.coffee_inventory_purchased cip
     WHERE rlc.origin_purchase_id = cip.origin_purchase_id
       AND cip.origin = p_origin_id AND cip.facility_id = p_facility_id;

    -- 2d. Replay charged, non-import roasts that consume this origin, oldest first.
    FOR v_roast IN
        SELECT rl.roast_log_id, rl.charge_weight_lbs, rl.coffee_source_id,
               rl.recipe_id, rl.origin_id, rl.roast_date, rl.created_at,
               rr.roast_type
          FROM public.roast_log rl
          LEFT JOIN public.roast_recipes rr ON rr.recipe_id = rl.recipe_id
         WHERE rl.facility_id = p_facility_id
           AND rl."charged?" = true
           AND COALESCE(rl.charge_weight_lbs, 0) > 0
           AND rl.external_roast_id IS NULL                       -- skip Artisan imports
           -- Skip historical/migration imports. Compare DATES (roast_date is
           -- local time, created_at is UTC) with a 1-day grace so timezone skew
           -- never flags a live roast: only roasts logged for a date more than
           -- a day before they were created are treated as imports.
           AND rl.roast_date >= (rl.created_at::date - interval '1 day')
           AND (
              (rr.roast_type = 'Pre-Blend'
                 AND EXISTS (SELECT 1 FROM public.recipe_components rc
                              WHERE rc.recipe_id = rl.recipe_id
                                AND rc.coffee_item = p_origin_id
                                AND COALESCE(rc.percentage, 0) > 0))
              OR
              ((rr.roast_type IS NULL OR rr.roast_type <> 'Pre-Blend')
                 AND rl.origin_id = p_origin_id)
           )
         ORDER BY rl.roast_date ASC, rl.created_at ASC
    LOOP
        IF v_roast.roast_type = 'Pre-Blend' THEN
            -- percentage is a 0-1 fraction (NOT 0-100) — no division.
            SELECT v_roast.charge_weight_lbs * COALESCE(rc.percentage, 0)
              INTO v_needed
              FROM public.recipe_components rc
             WHERE rc.recipe_id = v_roast.recipe_id AND rc.coffee_item = p_origin_id
             ORDER BY rc.percentage DESC
             LIMIT 1;
        ELSE
            v_needed := v_roast.charge_weight_lbs;
        END IF;
        IF COALESCE(v_needed, 0) <= 0 THEN CONTINUE; END IF;

        -- Preferred source: the roast's own pick (if it belongs to this origin),
        -- else the group's active source pointer.
        v_pref := NULL;
        IF v_roast.coffee_source_id IS NOT NULL THEN
            SELECT CASE WHEN cs.origin_id = p_origin_id THEN v_roast.coffee_source_id ELSE NULL END
              INTO v_pref FROM public.coffee_source cs
             WHERE cs.coffee_source_id = v_roast.coffee_source_id;
        END IF;
        IF v_pref IS NULL THEN
            SELECT active_coffee_source_id INTO v_pref
              FROM public.coffee_inventory
             WHERE origin_id = p_origin_id AND facility_id = p_facility_id;
        END IF;

        PERFORM public._deduct_origin_fifo(
            v_roast.roast_log_id, p_origin_id, p_facility_id, v_needed, v_pref);
    END LOOP;

    PERFORM public.recalculate_origin_total_stock(p_origin_id, p_facility_id);
END;
$$;

-- ----------------------------------------------------------------------------
-- 3. Which origins does a roast consume? (pre-blend → all components, else origin)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._roast_affected_origins(
    p_recipe_id text,
    p_origin_id text
) RETURNS text[]
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_rt text;
    v_res text[];
BEGIN
    IF p_recipe_id IS NOT NULL THEN
        SELECT roast_type INTO v_rt FROM public.roast_recipes WHERE recipe_id = p_recipe_id;
    END IF;
    IF v_rt = 'Pre-Blend' THEN
        SELECT array_agg(DISTINCT rc.coffee_item) INTO v_res
          FROM public.recipe_components rc
         WHERE rc.recipe_id = p_recipe_id AND rc.coffee_item IS NOT NULL;
        RETURN COALESCE(v_res, '{}');
    ELSIF p_origin_id IS NOT NULL THEN
        RETURN ARRAY[p_origin_id];
    ELSE
        RETURN '{}';
    END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- 4. Roast trigger: recompute affected origins on charge / un-charge / edit /
--    delete. AFTER INSERT, UPDATE of the deduction-relevant columns, or DELETE.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.roast_log_lot_recompute()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    o text;
BEGIN
    IF TG_OP IN ('INSERT', 'UPDATE') AND NEW.facility_id IS NOT NULL THEN
        FOREACH o IN ARRAY public._roast_affected_origins(NEW.recipe_id, NEW.origin_id) LOOP
            PERFORM public.recompute_origin_lot_consumption(o, NEW.facility_id);
        END LOOP;
    END IF;
    IF TG_OP IN ('UPDATE', 'DELETE') AND OLD.facility_id IS NOT NULL THEN
        FOREACH o IN ARRAY public._roast_affected_origins(OLD.recipe_id, OLD.origin_id) LOOP
            PERFORM public.recompute_origin_lot_consumption(o, OLD.facility_id);
        END LOOP;
    END IF;
    RETURN NULL;
END;
$$;

-- Retire the old INSERT-only deduction; the replay supersedes it entirely.
DROP TRIGGER IF EXISTS trg_deduct_from_lot_on_roast ON public.roast_log;
DROP TRIGGER IF EXISTS trg_lot_consumption_recompute ON public.roast_log;
CREATE TRIGGER trg_lot_consumption_recompute
AFTER INSERT OR DELETE OR
      UPDATE OF "charged?", charge_weight_lbs, charge_weight, origin_id, recipe_id, coffee_source_id
ON public.roast_log
FOR EACH ROW EXECUTE FUNCTION public.roast_log_lot_recompute();

-- ----------------------------------------------------------------------------
-- 5. Recompute on shipment receive / void too (replaces the init-on-receive
--    trigger): receiving or voiding a shipment redistributes the whole origin.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.shipment_lot_recompute()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    rec record;
BEGIN
    FOR rec IN
        SELECT DISTINCT origin, facility_id
          FROM public.coffee_inventory_purchased
         WHERE shipment_id = NEW.shipment_id
           AND origin IS NOT NULL AND facility_id IS NOT NULL
    LOOP
        PERFORM public.recompute_origin_lot_consumption(rec.origin, rec.facility_id);
    END LOOP;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_init_lot_remaining_on_receive ON public.shipment_received;
DROP TRIGGER IF EXISTS trg_shipment_lot_recompute ON public.shipment_received;
CREATE TRIGGER trg_shipment_lot_recompute
AFTER UPDATE OF date_received, voided
ON public.shipment_received
FOR EACH ROW EXECUTE FUNCTION public.shipment_lot_recompute();
