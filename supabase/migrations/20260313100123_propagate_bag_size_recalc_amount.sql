-- Migration 00123: Recalculate amount on coffee_inventory_purchased when bag_size changes
--
-- Previously, changing coffee_source.bag_size only updated the display bag_size column
-- on historical purchase rows. The amount (lbs) was left frozen at the original value,
-- meaning a wrong bag_size entry would leave all historical lbs incorrect.
--
-- Fix: also recalculate amount = bags_ordered * new_bag_size on all historical rows.
-- This also triggers the cost cascade (trg_push_last_coffee_cost) which correctly
-- adjusts shipping cost allocation across the updated lbs totals.

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

    -- Update coffee_inventory (operative bag size for the origin category)
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

    -- Update all historical purchases: fix display bag_size and recalculate lbs ordered.
    -- amount = bags_ordered * bag_size is the source of truth for lbs.
    -- This also triggers the cost cascade (shipping allocation recalculates across corrected lbs).
    UPDATE public.coffee_inventory_purchased
    SET bag_size = NEW.bag_size,
        amount   = bags_ordered * NEW.bag_size::numeric
    WHERE coffee_source_id = NEW.coffee_source_id
      AND bags_ordered IS NOT NULL;

    RETURN NEW;
END;
$$;
