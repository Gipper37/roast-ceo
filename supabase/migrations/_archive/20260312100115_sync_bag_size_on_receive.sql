-- Migration 00115: Auto-sync coffee_inventory.bag_size when shipment is received
--
-- When date_received transitions from NULL → a date on shipment_received,
-- update coffee_inventory.bag_size for each origin in that shipment using
-- the coffee_source.bag_size for that purchase.
--
-- This makes coffee_inventory.bag_size fully automatic — it always reflects
-- the most recently received coffee for that origin/facility. No manual maintenance.
--
-- Only fires on NULL → non-null transition (the actual receiving event).
-- Only updates origins that have a linked coffee_source with a bag_size set.
-- Updating bag_size fires the existing trg_manual_inventory_update and
-- trg_refresh_par_on_bag_size_change triggers, which recalculate in_stock_bags,
-- par, restock_level, and to_order_bags automatically.


CREATE OR REPLACE FUNCTION public.sync_bag_size_on_shipment_received()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    r RECORD;
BEGIN
    -- Only act when date_received transitions NULL → a date (shipment just received)
    IF NEW.date_received IS NULL OR OLD.date_received IS NOT NULL THEN
        RETURN NEW;
    END IF;

    -- For each coffee purchase in this shipment with a coffee_source bag_size,
    -- update the operative bag_size on the matching coffee_inventory row
    FOR r IN
        SELECT p.origin, p.facility_id, cs.bag_size
        FROM public.coffee_inventory_purchased p
        JOIN public.coffee_source cs ON p.coffee_source_id = cs.coffee_source_id
        WHERE p.shipment_id  = NEW.shipment_id
          AND p.facility_id  = NEW.facility_id
          AND cs.bag_size    IS NOT NULL
    LOOP
        UPDATE public.coffee_inventory
        SET bag_size = r.bag_size
        WHERE origin_id   = r.origin
          AND facility_id = r.facility_id;
    END LOOP;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_sync_bag_size_on_shipment_received
    AFTER UPDATE OF date_received
    ON public.shipment_received
    FOR EACH ROW
    EXECUTE FUNCTION public.sync_bag_size_on_shipment_received();
