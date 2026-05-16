-- Fix: nudge_all_inventory updates updated_at but that column isn't in
-- the trigger column lists. Add it so hourly nudge triggers recalculation.

-- Coffee: the recalc happens via handle_manual_inventory_update or similar
-- Let's check what trigger handles coffee par recalculation and add updated_at

-- For consumables: add updated_at to the trigger
DROP TRIGGER IF EXISTS trg_update_consumable_ordering ON consumable_inventory;
CREATE TRIGGER trg_update_consumable_ordering
  BEFORE INSERT OR UPDATE OF consumable_inventory_id, facility_id, last_inventory_date, inventory_count, par, restock_level, restock_category_id, updated_at
  ON consumable_inventory
  FOR EACH ROW EXECUTE FUNCTION update_consumable_metrics();

-- For coffee: create a trigger that recalculates par/restock when updated_at changes
-- (The existing handle_manual_inventory_update trigger only fires on specific columns)
CREATE OR REPLACE FUNCTION trg_recalc_coffee_on_nudge()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  -- Only recalculate if this is an updated_at-only change (nudge)
  -- Avoid infinite loops by checking pg_trigger_depth
  IF pg_trigger_depth() > 1 THEN RETURN NEW; END IF;

  NEW.par := calculate_par(NEW.origin_id);
  NEW.restock_level := calculate_restock_level(NEW.origin_id);
  NEW.to_order := GREATEST(0, NEW.par - COALESCE(NEW.in_stock, 0));
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_coffee_nudge_recalc ON coffee_inventory;
CREATE TRIGGER trg_coffee_nudge_recalc
  BEFORE UPDATE OF updated_at
  ON coffee_inventory
  FOR EACH ROW EXECUTE FUNCTION trg_recalc_coffee_on_nudge();
