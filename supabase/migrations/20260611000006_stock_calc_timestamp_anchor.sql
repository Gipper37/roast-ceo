-- ============================================================================
-- Displayed-stock calc: timestamp count anchor (match the lot layer)
-- ============================================================================
-- 20260611000004 moved the LOT count anchor to a UTC instant (count_at +
-- roast_date_utc) so you can count at 2pm, keep roasting at 3pm, and only the
-- 3pm+ roasts come off the count. But calculate_current_stock_lbs — the
-- function that drives the displayed bag counts / par / restock — still
-- compared roast_date::DATE > last_inventory::DATE. So the two layers
-- disagreed at sub-day granularity: a same-day post-count roast wouldn't
-- reduce the displayed stock until the next day.
--
-- This aligns the display with the lot layer:
--   * coffee_inventory gains last_inventory_at (the count's UTC instant).
--   * calculate_current_stock_lbs compares the roast's UTC time
--     (roast_date_utc, falling back to roast_date AT TIME ZONE facility_tz)
--     against last_inventory_at — falling back, when last_inventory_at is
--     null, to END of the last_inventory day in facility-local time, which is
--     exactly the old date-based boundary. So existing data is unchanged;
--     new counts get true timestamp precision.
--   * apply_group_count_to_lots stamps the count moment: now() for a same-day
--     count, end-of-day for a back-dated baseline count — on BOTH the group
--     (last_inventory_at) and the per-lot anchors (count_at), so they agree.
-- ============================================================================

ALTER TABLE public.coffee_inventory
  ADD COLUMN IF NOT EXISTS last_inventory_at timestamptz;

-- ─── 1. Timestamp-aware displayed-stock calc ────────────────────────────────
CREATE OR REPLACE FUNCTION public.calculate_current_stock_lbs(p_origin_id text, p_facility_id text)
RETURNS numeric
LANGUAGE plpgsql
AS $function$
DECLARE
    v_purchased_lbs       NUMERIC;
    v_starting_lbs        NUMERIC;
    v_bag_size            NUMERIC;
    v_inventory_bags      NUMERIC;
    v_last_inventory_date DATE;
    v_last_inventory_at   TIMESTAMPTZ;
    v_roasted_direct_lbs  NUMERIC;
    v_roasted_blend_lbs   NUMERIC;
    v_tz                  TEXT;
BEGIN
    SELECT COALESCE(NULLIF(time_zone, ''), 'UTC') INTO v_tz
    FROM public.facilities WHERE facility_id = p_facility_id;
    v_tz := COALESCE(v_tz, 'UTC');

    SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
    FROM coffee_inventory WHERE origin_id = p_origin_id AND facility_id = p_facility_id LIMIT 1;

    SELECT last_inventory::DATE, COALESCE(inventory_count_bags, 0), last_inventory_at
    INTO v_last_inventory_date, v_inventory_bags, v_last_inventory_at
    FROM coffee_inventory WHERE origin_id = p_origin_id AND facility_id = p_facility_id;

    IF v_last_inventory_date IS NULL THEN v_last_inventory_date := '2000-01-01'; END IF;

    -- Count moment: the recorded instant, else END of the count day in
    -- facility-local time (= the old `roast_date::DATE > last_inventory` rule).
    IF v_last_inventory_at IS NULL THEN
        v_last_inventory_at := (v_last_inventory_date + 1)::timestamp AT TIME ZONE v_tz;
    END IF;

    v_starting_lbs := v_inventory_bags * v_bag_size;

    -- Purchases stay date-keyed: receipts carry a date, not a sub-day instant.
    SELECT COALESCE(SUM(p.amount), 0) INTO v_purchased_lbs
    FROM coffee_inventory_purchased p
    JOIN shipment_received s ON p.shipment_id = s.shipment_id
    WHERE p.origin = p_origin_id
      AND s.date_received IS NOT NULL
      AND s.date_received::DATE > v_last_inventory_date
      AND COALESCE(s.voided, false) = false
      AND p.facility_id = p_facility_id;

    -- Single-origin / post-blend consumption, by UTC instant after the count.
    SELECT COALESCE(SUM(rl.charge_weight_lbs), 0) INTO v_roasted_direct_lbs
    FROM roast_log rl
    LEFT JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    WHERE rl.origin_id = p_origin_id
      AND COALESCE(rl.roast_date_utc, rl.roast_date AT TIME ZONE v_tz) >= v_last_inventory_at
      AND rl."charged?" = TRUE
      AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend' OR rr.roast_type IS NULL)
      AND rl.facility_id = p_facility_id;

    -- Pre-blend consumption, by UTC instant after the count.
    SELECT COALESCE(SUM(rl.charge_weight_lbs * rc.percentage), 0) INTO v_roasted_blend_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
    WHERE rc.coffee_item = p_origin_id
      AND rr.roast_type = 'Pre-Blend'
      AND COALESCE(rl.roast_date_utc, rl.roast_date AT TIME ZONE v_tz) >= v_last_inventory_at
      AND rl."charged?" = TRUE
      AND rl.facility_id = p_facility_id;

    RETURN GREATEST(0, (v_starting_lbs + v_purchased_lbs - v_roasted_direct_lbs - v_roasted_blend_lbs));
END;
$function$;

-- ─── 2. Stamp the count moment on the group + per-lot anchors ────────────────
CREATE OR REPLACE FUNCTION public.apply_group_count_to_lots(p_origin_id text, p_facility_id text, p_count_date date, p_bag_count numeric)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_company text;
    v_bag_size numeric;
    v_total_lbs numeric;
    v_tz text;
    v_count_moment timestamptz;
BEGIN
    SELECT company_id, NULLIF(bag_size, '')::numeric
      INTO v_company, v_bag_size
      FROM public.coffee_inventory
     WHERE origin_id = p_origin_id AND facility_id = p_facility_id
     LIMIT 1;
    v_total_lbs := GREATEST(COALESCE(p_bag_count, 0) * COALESCE(v_bag_size, 0), 0);

    SELECT COALESCE(NULLIF(time_zone, ''), 'UTC') INTO v_tz
      FROM public.facilities WHERE facility_id = p_facility_id;
    v_tz := COALESCE(v_tz, 'UTC');

    -- Same-day count → the exact moment (now). Back-dated baseline count →
    -- end of that day, facility-local. Both layers share this instant.
    IF p_count_date >= (now() AT TIME ZONE v_tz)::date THEN
        v_count_moment := now();
    ELSE
        v_count_moment := (p_count_date + 1)::timestamp AT TIME ZONE v_tz;
    END IF;

    UPDATE public.coffee_inventory
       SET last_inventory_at = v_count_moment
     WHERE origin_id = p_origin_id AND facility_id = p_facility_id;

    DELETE FROM public.coffee_lot_count clc
     USING public.coffee_inventory_purchased cip
     WHERE clc.origin_purchase_id = cip.origin_purchase_id
       AND cip.origin = p_origin_id AND cip.facility_id = p_facility_id
       AND clc.count_date = p_count_date;

    INSERT INTO public.coffee_lot_count (origin_purchase_id, count_date, count_at, counted_remaining_lbs, company_id)
    SELECT s.origin_purchase_id, p_count_date, v_count_moment,
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
$function$;
