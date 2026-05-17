-- Migration 00051: Recalculate bags_left when total_pallets changes
--
-- Previously: no trigger on recent_coffee_order itself.
-- When a user edits total_pallets, bags_left was never recalculated.
-- Fix: BEFORE UPDATE trigger intercepts total_pallets changes and sets
-- bags_left = (total_pallets × 10) − SUM(bags_ordered in most recent shipment)

CREATE OR REPLACE FUNCTION public.compute_bags_left_on_pallets_change()
RETURNS TRIGGER AS $$
DECLARE
    v_most_recent_shipment_id TEXT;
    v_total_ordered_bags      NUMERIC;
BEGIN
    -- Most recent shipment for this facility (by order_date DESC)
    SELECT shipment_id INTO v_most_recent_shipment_id
    FROM public.shipment_received
    WHERE facility_id = NEW.facility_id
    ORDER BY order_date DESC NULLS LAST, created_at DESC
    LIMIT 1;

    -- Sum bags_ordered from that shipment
    SELECT COALESCE(SUM(bags_ordered), 0) INTO v_total_ordered_bags
    FROM public.coffee_inventory_purchased
    WHERE shipment_id = v_most_recent_shipment_id
      AND facility_id = NEW.facility_id;

    NEW.bags_left := (COALESCE(NEW.total_pallets, 0) * 10) - v_total_ordered_bags;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_bags_left_on_pallets_change
    BEFORE UPDATE OF total_pallets
    ON public.recent_coffee_order
    FOR EACH ROW EXECUTE FUNCTION public.compute_bags_left_on_pallets_change();
