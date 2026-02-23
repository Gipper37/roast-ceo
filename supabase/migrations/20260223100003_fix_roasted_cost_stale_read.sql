-- Migration: Fix trigger_sync_roasted_cost() to use NEW.cost_lb_green directly
--
-- Issue 2: This function is a BEFORE trigger on roast_recipes (fires on INSERT OR
-- UPDATE OF cost_lb_green). In a BEFORE trigger, the table row still contains the
-- OLD value — the new value being written is in NEW. The current code does:
--
--   SELECT rr.cost_lb_green INTO v_green_cost FROM roast_recipes rr
--   WHERE rr.recipe_id = NEW.recipe_id AND rr.facility_id = v_facility_id;
--
-- That SELECT reads from the table, which still has the old cost_lb_green. So
-- cost_lb_roasted is always calculated from the PREVIOUS green cost — it is always
-- one update behind.
--
-- Fix: Use NEW.cost_lb_green directly instead of querying the table.
-- facility_id still uses COALESCE(NEW, OLD) to handle both INSERT and UPDATE.

CREATE OR REPLACE FUNCTION public.trigger_sync_roasted_cost()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    -- Calculate and stamp the roasted cost using NEW values directly.
    -- In a BEFORE trigger NEW holds the incoming (not-yet-written) row data.
    -- Querying the table here would return stale (old) values.
    NEW.cost_lb_roasted := calculate_roasted_cost(
        NEW.cost_lb_green,
        COALESCE(NEW.facility_id, OLD.facility_id)
    );

    RETURN NEW;
END;
$$;
