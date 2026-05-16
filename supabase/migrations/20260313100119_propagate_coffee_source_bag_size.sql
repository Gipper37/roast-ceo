-- Migration 00119: Propagate coffee_source.bag_size changes to coffee_inventory
--
-- Previously, editing coffee_source.bag_size had no downstream effect — only the
-- audit triggers fired. The cascade chain (coffee_inventory → PAR → restock) only
-- ran when a shipment was received. This trigger closes that gap.
--
-- When bag_size is updated on a coffee_source record, find every (origin, facility_id)
-- pair in coffee_inventory_purchased that references this coffee_source, and push the
-- new bag_size to coffee_inventory. The existing cascade handles the rest:
--   trg_manual_inventory_update → in_stock, in_stock_lbs, par, restock_level, to_order_bags
--   trg_refresh_par_on_bag_size_change → par, restock_level, to_order_bags (AFTER)

CREATE OR REPLACE FUNCTION public.propagate_coffee_source_bag_size()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    r RECORD;
BEGIN
    -- Skip if bag_size didn't change or has no value to propagate
    IF NEW.bag_size IS NOT DISTINCT FROM OLD.bag_size THEN
        RETURN NEW;
    END IF;
    IF NEW.bag_size IS NULL THEN
        RETURN NEW;
    END IF;

    FOR r IN
        SELECT DISTINCT p.origin, p.facility_id
        FROM public.coffee_inventory_purchased p
        WHERE p.coffee_source_id = NEW.coffee_source_id
          AND p.facility_id IS NOT NULL
    LOOP
        UPDATE public.coffee_inventory
        SET bag_size = NEW.bag_size
        WHERE origin_id   = r.origin
          AND facility_id = r.facility_id;
    END LOOP;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_propagate_coffee_source_bag_size
    AFTER UPDATE OF bag_size
    ON public.coffee_source
    FOR EACH ROW
    EXECUTE FUNCTION public.propagate_coffee_source_bag_size();
