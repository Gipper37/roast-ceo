-- Migration 00053: Auto-sync current_shipment_id when a new shipment is created
--
-- When a user adds a new shipment in the "Current Coffee Order" window,
-- recent_coffee_order.current_shipment_id automatically updates to the new shipment.
-- The trg_recent_coffee_order_calcs BEFORE trigger then recalculates lbs_ordered
-- and bags_left for the new shipment in the same transaction.
-- User can still manually override current_shipment_id if needed.

CREATE OR REPLACE FUNCTION public.sync_current_shipment_on_new_order()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.recent_coffee_order
    SET current_shipment_id = NEW.shipment_id
    WHERE facility_id = NEW.facility_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sync_current_shipment
    AFTER INSERT ON public.shipment_received
    FOR EACH ROW EXECUTE FUNCTION public.sync_current_shipment_on_new_order();
