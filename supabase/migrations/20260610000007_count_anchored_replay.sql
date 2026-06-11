-- ============================================================================
-- Count ↔ lot reconciliation (Phase B): manual counts anchor the replay
-- ============================================================================
-- Before this, recordPerLotCount / markLotDepleted wrote coffee_inventory_
-- purchased.remaining_lbs DIRECTLY — which the replay (…0006) resets on the
-- next roast, silently wiping the count. And group counts never touched lots
-- at all, so lot stock diverged from the in_stock the operator sees.
--
-- This makes a count a durable BASELINE the replay honors, exactly mirroring
-- how calculate_current_stock_lbs anchors in_stock to last_inventory:
--   * a count records each lot's counted remaining at a date (coffee_lot_count)
--   * the replay baselines each lot to its latest counted value (not the full
--     received amount) and replays only roasts AFTER the count date
--   * group counts distribute the counted total across lots newest-first
--     (FIFO-consistent: what physically remains is the newest lots)
-- Result: after a count, the lot total equals the counted total, then deducts
-- forward — and stays in agreement with in_stock.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Per-lot count snapshots.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.coffee_lot_count (
    id                    text PRIMARY KEY DEFAULT (gen_random_uuid())::text,
    origin_purchase_id    text NOT NULL REFERENCES public.coffee_inventory_purchased(origin_purchase_id) ON DELETE CASCADE,
    count_date            date NOT NULL,
    counted_remaining_lbs numeric NOT NULL DEFAULT 0,
    company_id            text,
    created_at            timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_coffee_lot_count_lot ON public.coffee_lot_count(origin_purchase_id, count_date);

ALTER TABLE public.coffee_lot_count ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_company_access ON public.coffee_lot_count;
CREATE POLICY tenant_company_access ON public.coffee_lot_count
  FOR ALL TO authenticated
  USING (company_id IN (SELECT public.auth_company_ids()))
  WITH CHECK (company_id IN (SELECT public.auth_company_ids()));

-- ----------------------------------------------------------------------------
-- 2. Count-anchored replay (supersedes the …0006 version).
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
    v_last_count date;
BEGIN
    IF p_origin_id IS NULL OR p_facility_id IS NULL THEN RETURN; END IF;

    -- Latest count date for this origin (NULL → never counted → baseline = receipts).
    SELECT MAX(clc.count_date) INTO v_last_count
      FROM public.coffee_lot_count clc
      JOIN public.coffee_inventory_purchased cip2 ON cip2.origin_purchase_id = clc.origin_purchase_id
     WHERE cip2.origin = p_origin_id AND cip2.facility_id = p_facility_id;

    -- 2a. Unavailable lots (un-received OR voided shipment) → NULL.
    UPDATE public.coffee_inventory_purchased cip
       SET remaining_lbs = NULL
     WHERE cip.origin = p_origin_id AND cip.facility_id = p_facility_id
       AND cip.shipment_id IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM public.shipment_received sr
          WHERE sr.shipment_id = cip.shipment_id
            AND sr.date_received IS NOT NULL
            AND COALESCE(sr.voided, false) = false);

    -- 2b. Available lots → baseline. With a count: each lot's counted value at
    --     the last count date; lots received after the count → full amount;
    --     lots that existed at the count but weren't counted → 0. No count yet
    --     → full received amount (fresh-receipt behavior).
    UPDATE public.coffee_inventory_purchased cip
       SET remaining_lbs = CASE
            WHEN v_last_count IS NULL THEN cip.amount
            ELSE COALESCE(
              (SELECT clc.counted_remaining_lbs
                 FROM public.coffee_lot_count clc
                WHERE clc.origin_purchase_id = cip.origin_purchase_id
                  AND clc.count_date = v_last_count
                ORDER BY clc.created_at DESC LIMIT 1),
              CASE WHEN COALESCE(
                     (SELECT sr.date_received FROM public.shipment_received sr WHERE sr.shipment_id = cip.shipment_id),
                     cip.created_at::date) > v_last_count
                   THEN cip.amount ELSE 0 END
            )
           END
     WHERE cip.origin = p_origin_id AND cip.facility_id = p_facility_id
       AND cip.amount IS NOT NULL
       AND (
          cip.shipment_id IS NULL
          OR EXISTS (
            SELECT 1 FROM public.shipment_received sr
             WHERE sr.shipment_id = cip.shipment_id
               AND sr.date_received IS NOT NULL
               AND COALESCE(sr.voided, false) = false));

    -- 2c. Clear the consumption ledger for this origin's lots.
    DELETE FROM public.roast_log_lot_consumption rlc
     USING public.coffee_inventory_purchased cip
     WHERE rlc.origin_purchase_id = cip.origin_purchase_id
       AND cip.origin = p_origin_id AND cip.facility_id = p_facility_id;

    -- 2d. Replay charged, non-import roasts AFTER the count (matches
    --     calculate_current_stock_lbs' `roast_date > last_inventory`), oldest first.
    FOR v_roast IN
        SELECT rl.roast_log_id, rl.charge_weight_lbs, rl.coffee_source_id,
               rl.recipe_id, rl.origin_id, rl.roast_date, rl.created_at,
               rr.roast_type
          FROM public.roast_log rl
          LEFT JOIN public.roast_recipes rr ON rr.recipe_id = rl.recipe_id
         WHERE rl.facility_id = p_facility_id
           AND rl."charged?" = true
           AND COALESCE(rl.charge_weight_lbs, 0) > 0
           AND rl.external_roast_id IS NULL
           AND rl.roast_date >= (rl.created_at::date - interval '1 day')
           AND (v_last_count IS NULL OR rl.roast_date > v_last_count)
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
            SELECT v_roast.charge_weight_lbs * COALESCE(rc.percentage, 0)
              INTO v_needed
              FROM public.recipe_components rc
             WHERE rc.recipe_id = v_roast.recipe_id AND rc.coffee_item = p_origin_id
             ORDER BY rc.percentage DESC LIMIT 1;
        ELSE
            v_needed := v_roast.charge_weight_lbs;
        END IF;
        IF COALESCE(v_needed, 0) <= 0 THEN CONTINUE; END IF;

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
-- 3. Distribute a group count total across lots, newest-first (FIFO-consistent).
--    Converts a bag count to lbs via the origin's bag_size and writes per-lot
--    count snapshots in a single INSERT (so the statement trigger fires once).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.apply_group_count_to_lots(
    p_origin_id text,
    p_facility_id text,
    p_count_date date,
    p_bag_count numeric
) RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_company text;
    v_bag_size numeric;
    v_total_lbs numeric;
BEGIN
    SELECT company_id, NULLIF(bag_size, '')::numeric
      INTO v_company, v_bag_size
      FROM public.coffee_inventory
     WHERE origin_id = p_origin_id AND facility_id = p_facility_id
     LIMIT 1;
    v_total_lbs := GREATEST(COALESCE(p_bag_count, 0) * COALESCE(v_bag_size, 0), 0);

    -- Idempotent: clear any existing count rows for this origin on this date.
    DELETE FROM public.coffee_lot_count clc
     USING public.coffee_inventory_purchased cip
     WHERE clc.origin_purchase_id = cip.origin_purchase_id
       AND cip.origin = p_origin_id AND cip.facility_id = p_facility_id
       AND clc.count_date = p_count_date;

    INSERT INTO public.coffee_lot_count (origin_purchase_id, count_date, counted_remaining_lbs, company_id)
    SELECT s.origin_purchase_id, p_count_date,
           LEAST(s.amount, GREATEST(0, v_total_lbs - s.prior_sum)),
           v_company
    FROM (
      SELECT cip.origin_purchase_id, cip.amount,
             COALESCE(SUM(cip.amount) OVER (
                ORDER BY COALESCE(sr.date_received, cip.created_at::date) DESC, cip.created_at DESC
                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) AS prior_sum
        FROM public.coffee_inventory_purchased cip
        LEFT JOIN public.shipment_received sr ON sr.shipment_id = cip.shipment_id
       WHERE cip.origin = p_origin_id AND cip.facility_id = p_facility_id
         AND cip.amount IS NOT NULL
         AND (cip.shipment_id IS NULL
              OR (sr.date_received IS NOT NULL AND COALESCE(sr.voided, false) = false))
    ) s;
    -- recompute fires via the statement trigger on coffee_lot_count.
END;
$$;
GRANT EXECUTE ON FUNCTION public.apply_group_count_to_lots(text, text, date, numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.recompute_origin_lot_consumption(text, text) TO authenticated;

-- ----------------------------------------------------------------------------
-- 4. Statement-level trigger: any batch of count rows recomputes each affected
--    origin exactly once (no per-row recompute storm).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.coffee_lot_count_recompute()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    rec record;
BEGIN
    FOR rec IN
        SELECT DISTINCT cip.origin, cip.facility_id
          FROM new_counts nc
          JOIN public.coffee_inventory_purchased cip ON cip.origin_purchase_id = nc.origin_purchase_id
         WHERE cip.origin IS NOT NULL AND cip.facility_id IS NOT NULL
    LOOP
        PERFORM public.recompute_origin_lot_consumption(rec.origin, rec.facility_id);
    END LOOP;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_coffee_lot_count_recompute ON public.coffee_lot_count;
CREATE TRIGGER trg_coffee_lot_count_recompute
AFTER INSERT ON public.coffee_lot_count
REFERENCING NEW TABLE AS new_counts
FOR EACH STATEMENT EXECUTE FUNCTION public.coffee_lot_count_recompute();
