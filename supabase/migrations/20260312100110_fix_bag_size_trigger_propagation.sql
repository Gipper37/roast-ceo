-- Migration 00110: Fix trigger propagation when bag_size changes on coffee_inventory
--
-- Problem: Two BEFORE triggers on coffee_inventory have UPDATE OF column lists
-- that don't include bag_size, so changing bag_size in AppSheet fires nothing:
--
--   trg_manual_inventory_update  → UPDATE OF origin_id, facility_id,
--                                   last_inventory, inventory_count_bags
--   trigger_calculate_ordered_lbs → UPDATE OF bags_ordered, facility_id
--
-- Additionally, handle_manual_inventory_update calls calculate_par() which reads
-- bag_size from the DB. Since this is a BEFORE trigger, the new bag_size hasn't
-- committed yet — so par/restock_level are computed using the OLD bag_size.
--
-- Fix:
--   1. Add bag_size to both trigger column lists
--   2. New AFTER trigger on UPDATE OF bag_size that recalculates par,
--      restock_level, and to_order_bags AFTER the new bag_size is committed
--   3. Backfill: touch all rows to fire the updated triggers and ensure
--      in_stock, par, restock_level, actual_ordered_lbs are correct


-- ─── 1. Fix trg_manual_inventory_update ─────────────────────────────────────

DROP TRIGGER trg_manual_inventory_update ON public.coffee_inventory;

CREATE TRIGGER trg_manual_inventory_update
    BEFORE INSERT OR UPDATE OF origin_id, facility_id, last_inventory,
                                inventory_count_bags, bag_size
    ON public.coffee_inventory
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_manual_inventory_update();


-- ─── 2. Fix trigger_calculate_ordered_lbs ───────────────────────────────────

DROP TRIGGER trigger_calculate_ordered_lbs ON public.coffee_inventory;

CREATE TRIGGER trigger_calculate_ordered_lbs
    BEFORE INSERT OR UPDATE OF bags_ordered, facility_id, bag_size
    ON public.coffee_inventory
    FOR EACH ROW
    EXECUTE FUNCTION public.update_actual_ordered_lbs();


-- ─── 3. AFTER trigger: recalculate par/restock_level on bag_size change ─────
--
-- calculate_par() and calculate_restock_level() read bag_size from the DB.
-- In a BEFORE trigger the new bag_size hasn't committed yet, so par/restock
-- would use the old value. This AFTER trigger runs once the new bag_size is
-- committed, so the recalculated values are correct.
--
-- Note: this UPDATE of par/restock_level does NOT re-fire handle_manual_
-- inventory_update (par and restock_level are not in its UPDATE OF list),
-- so no recursion.

CREATE OR REPLACE FUNCTION public.refresh_par_on_bag_size_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_par         NUMERIC;
    v_restock     NUMERIC;
BEGIN
    -- Only run when bag_size actually changed
    IF NEW.bag_size IS NOT DISTINCT FROM OLD.bag_size THEN
        RETURN NULL;
    END IF;

    v_par     := public.calculate_par(NEW.origin_id);
    v_restock := public.calculate_restock_level(NEW.origin_id);

    UPDATE public.coffee_inventory
    SET
        par           = v_par,
        restock_level = v_restock,
        to_order_bags = GREATEST(0, COALESCE(v_par, 0) - NEW.in_stock)
    WHERE origin_id = NEW.origin_id
      AND facility_id = NEW.facility_id;

    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_refresh_par_on_bag_size_change
    AFTER UPDATE OF bag_size
    ON public.coffee_inventory
    FOR EACH ROW
    EXECUTE FUNCTION public.refresh_par_on_bag_size_change();


-- ─── 4. Backfill: fire triggers on all rows ──────────────────────────────────
-- Touch inventory_count_bags (same value) to fire trg_manual_inventory_update
-- and recompute in_stock, inventory_lbs, par, restock_level, to_order_bags.
-- This also fires trigger_calculate_ordered_lbs → updates actual_ordered_lbs.
-- All current rows have bag_size = 154 so values will be identical to before.

UPDATE public.coffee_inventory
SET inventory_count_bags = COALESCE(inventory_count_bags, 0);
