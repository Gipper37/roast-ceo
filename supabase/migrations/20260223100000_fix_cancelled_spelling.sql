-- Migration: Standardize 'Cancelled' to 'Canceled' in calculate_current_stock_consumables
--
-- Issue 4: calculate_current_stock_consumables() uses 'Cancelled' (British spelling)
-- while all 4 other functions that filter order status use 'Canceled' (American spelling):
--   - update_consumable_metrics()
--   - update_customer_metrics_on_order()
--   - update_order_metrics()
-- Whichever spelling is in the actual data, one set of functions gets it wrong.
-- Standardizing to 'Canceled' (American, used by 4 of 5 functions).

CREATE OR REPLACE FUNCTION public.calculate_current_stock_consumables(p_consumable_id text, p_facility_id text)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
    v_last_inventory_date DATE;
    v_inventory_count NUMERIC;
    v_purchased_amount NUMERIC;
    v_usage_amount NUMERIC;
BEGIN
    -- 1. Get Baseline for THIS facility only
    SELECT last_inventory_date, COALESCE(inventory_count, 0)
    INTO v_last_inventory_date, v_inventory_count
    FROM consumable_inventory
    WHERE consumable_inventory_id = p_consumable_id
      AND facility_id = p_facility_id;

    -- Safety: If never counted, assume start of time
    IF v_last_inventory_date IS NULL THEN
        v_last_inventory_date := '2000-01-01';
    END IF;

    -- 2. Sum Additions (Purchases for THIS facility)
    SELECT COALESCE(SUM(amount), 0)
    INTO v_purchased_amount
    FROM consumable_inventory_purchased cp
    JOIN shipment_received sr ON cp.shipment_id = sr.shipment_id
    WHERE cp.consumable_inventory_item = p_consumable_id
      AND sr.date_received > v_last_inventory_date
      AND cp.facility_id = p_facility_id;

    -- 3. Sum Subtractions (Usage from Orders at THIS facility)
    SELECT COALESCE(SUM(od.quantity * pc.quantity), 0)
    INTO v_usage_amount
    FROM order_details od
    JOIN orders o ON od.order_id = o.order_id
    JOIN product_consumables pc ON od.product_id = pc.product_id
    WHERE pc.consumable_id = p_consumable_id
      AND o.order_date::DATE > v_last_inventory_date
      AND o.order_status != 'Canceled'  -- [FIX] Was 'Cancelled', standardized to 'Canceled'
      AND o.facility_id = p_facility_id;

    -- 4. Final Calculation
    RETURN GREATEST(0, (v_inventory_count + v_purchased_amount - v_usage_amount));
END;
$$;
