-- Migration: Fix >= boundary bug in calculate_current_stock_lbs()
--
-- Issue 15: The inventory baseline (v_last_inventory_date) is the DATE on which
-- a physical bag count was taken. That count already reflects all activity that
-- happened on or before that date — including purchases and roasts that occurred
-- on the same day as the count.
--
-- Purchases correctly use strict-greater-than (>):
--   s.date_received::DATE > v_last_inventory_date   (line 980 — correct)
--
-- But roast outflows incorrectly use >=:
--   rl.roast_date::DATE >= v_last_inventory_date    (line 988 — BUG)
--   rl.roast_date::DATE >= v_last_inventory_date    (line 1000 — BUG)
--
-- With >=, any roast that occurred ON the inventory date is subtracted even
-- though it was already factored into the physical count. This makes in_stock
-- appear lower than actual by the charge_weight of same-day roasts.
--
-- Fix: Change both >= to > so all three date comparisons are consistent.
-- Only 2 characters change in the entire function body.

CREATE OR REPLACE FUNCTION public.calculate_current_stock_lbs(p_origin_id text, p_facility_id text)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
    v_purchased_lbs NUMERIC;
    v_starting_lbs NUMERIC;
    v_bag_size NUMERIC;
    v_inventory_bags NUMERIC;
    v_last_inventory_date DATE;
    v_roasted_direct_lbs NUMERIC;
    v_roasted_blend_lbs NUMERIC;
BEGIN
    -- 1. Get Bag Size (Facility Specific)
    SELECT value_number INTO v_bag_size
    FROM company_parameters
    WHERE parameter_id = '66526a57'
      AND facility_id = p_facility_id;

    IF v_bag_size IS NULL OR v_bag_size = 0 THEN v_bag_size := 154; END IF;

    -- 2. Get Baseline (Physical Count for THIS Facility)
    SELECT last_inventory::DATE, COALESCE(inventory_count_bags, 0)
    INTO v_last_inventory_date, v_inventory_bags
    FROM coffee_inventory
    WHERE origin_id = p_origin_id
      AND facility_id = p_facility_id;

    IF v_last_inventory_date IS NULL THEN v_last_inventory_date := '2000-01-01'; END IF;

    v_starting_lbs := v_inventory_bags * v_bag_size;

    -- 3. Inflow: Purchases (Facility Specific)
    SELECT COALESCE(SUM(p.amount), 0) INTO v_purchased_lbs
    FROM coffee_inventory_purchased p
    JOIN shipment_received s ON p.shipment_id = s.shipment_id
    WHERE p.origin = p_origin_id
      AND s.date_received::DATE > v_last_inventory_date
      AND p.facility_id = p_facility_id;

    -- 4. Outflow A: Direct Roasts (Facility Specific)
    -- [FIX] Changed >= to >: roasts ON the inventory date are already included
    -- in the physical bag count and must not be subtracted again.
    SELECT COALESCE(SUM(rl.charge_weight), 0) INTO v_roasted_direct_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    WHERE rl.origin_id = p_origin_id
      AND rl.roast_date::DATE > v_last_inventory_date
      AND rl."charged?" = TRUE
      AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend')
      AND rl.facility_id = p_facility_id;

    -- 5. Outflow B: Blend Roasts (Facility Specific)
    -- [FIX] Changed >= to >: same boundary logic as direct roasts above.
    SELECT COALESCE(SUM(rl.charge_weight * rc.percentage), 0) INTO v_roasted_blend_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
    WHERE rc.coffee_item = p_origin_id
      AND rr.roast_type = 'Pre-Blend'
      AND rl.roast_date::DATE > v_last_inventory_date
      AND rl."charged?" = TRUE
      AND rl.facility_id = p_facility_id;

    -- 6. Final Result
    RETURN GREATEST(0, (v_starting_lbs + v_purchased_lbs - v_roasted_direct_lbs - v_roasted_blend_lbs));
END;
$$;
