-- Migration 00050: Update Coffee Order Guide to use coffee_inventory_purchased
--
-- Previously: recent_coffee_order was driven by coffee_inventory.bags_ordered (per-origin manual inputs)
-- Now: lbs_ordered and bags_left come from coffee_inventory_purchased rows in the most recent shipment
--      order_date auto-populates from the most recent shipment_received.order_date
--      recommended_pallets unchanged (still from coffee_inventory.to_order_bags)

-- ═══════════════════════════════════════════════════════════════
-- A. Core helper function: recalculate_green_purchasing_metrics(facility_id)
--    Called by both trigger wrappers below.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.recalculate_green_purchasing_metrics(p_facility_id text)
RETURNS void AS $$
DECLARE
    v_bag_size                NUMERIC;
    v_total_ordered_lbs       NUMERIC;
    v_total_ordered_bags      NUMERIC;
    v_total_to_order_bags     NUMERIC;
    v_most_recent_order_date  DATE;
    v_most_recent_shipment_id TEXT;
BEGIN
    -- 1. Bag size from company_parameters (66526a57, default 154 lbs)
    SELECT value_number INTO v_bag_size
    FROM public.company_parameters
    WHERE parameter_id = '66526a57'
      AND facility_id = p_facility_id;
    IF v_bag_size IS NULL OR v_bag_size = 0 THEN v_bag_size := 154; END IF;

    -- 2. Most recent shipment for this facility (by order_date DESC, created_at as tiebreaker)
    SELECT shipment_id, order_date
    INTO v_most_recent_shipment_id, v_most_recent_order_date
    FROM public.shipment_received
    WHERE facility_id = p_facility_id
    ORDER BY order_date DESC NULLS LAST, created_at DESC
    LIMIT 1;

    -- 3. Sum lbs and bags from coffee_inventory_purchased for that shipment
    SELECT
        COALESCE(SUM(amount), 0),
        COALESCE(SUM(bags_ordered), 0)
    INTO v_total_ordered_lbs, v_total_ordered_bags
    FROM public.coffee_inventory_purchased
    WHERE shipment_id = v_most_recent_shipment_id
      AND facility_id = p_facility_id;

    -- 4. Sum to_order_bags from coffee_inventory for recommended_pallets (unchanged)
    SELECT COALESCE(SUM(to_order_bags), 0)
    INTO v_total_to_order_bags
    FROM public.coffee_inventory
    WHERE facility_id = p_facility_id;

    -- 5. Push all four values to recent_coffee_order
    UPDATE public.recent_coffee_order
    SET
        lbs_ordered         = v_total_ordered_lbs,
        recommended_pallets = CEIL(v_total_to_order_bags / 10.0),
        bags_left           = (COALESCE(total_pallets, 0) * 10) - v_total_ordered_bags,
        order_date          = v_most_recent_order_date
    WHERE facility_id = p_facility_id;
END;
$$ LANGUAGE plpgsql;

-- ═══════════════════════════════════════════════════════════════
-- B. Rewrite trigger wrapper for coffee_inventory (existing trigger stays)
--    Keeps recommended_pallets live when par/stock changes.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.calculate_green_purchasing_metrics()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM public.recalculate_green_purchasing_metrics(
        COALESCE(NEW.facility_id, OLD.facility_id)
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Existing trigger trg_update_green_metrics on coffee_inventory is unchanged.

-- ═══════════════════════════════════════════════════════════════
-- C. New trigger on coffee_inventory_purchased
--    Fires when origins are added/changed/removed from a shipment.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.trg_green_metrics_from_purchased()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM public.recalculate_green_purchasing_metrics(
        COALESCE(NEW.facility_id, OLD.facility_id)
    );
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_green_metrics_from_purchased
    AFTER INSERT OR UPDATE OR DELETE
    ON public.coffee_inventory_purchased
    FOR EACH ROW EXECUTE FUNCTION public.trg_green_metrics_from_purchased();

-- ═══════════════════════════════════════════════════════════════
-- D. Recalculate immediately for all facilities
-- ═══════════════════════════════════════════════════════════════

DO $$
DECLARE v_fid TEXT;
BEGIN
    FOR v_fid IN
        SELECT DISTINCT facility_id FROM public.recent_coffee_order WHERE facility_id IS NOT NULL
    LOOP
        PERFORM public.recalculate_green_purchasing_metrics(v_fid);
    END LOOP;
END;
$$;
