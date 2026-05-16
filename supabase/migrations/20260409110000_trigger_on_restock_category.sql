-- Fire par/restock recalculation when restock_category_id changes
-- on both consumable_inventory and coffee_inventory

-- Consumable: add restock_category_id to the trigger column list
DROP TRIGGER IF EXISTS trg_update_consumable_ordering ON consumable_inventory;
CREATE TRIGGER trg_update_consumable_ordering
  BEFORE INSERT OR UPDATE OF consumable_inventory_id, facility_id, last_inventory_date, inventory_count, par, restock_level, restock_category_id
  ON consumable_inventory
  FOR EACH ROW EXECUTE FUNCTION update_consumable_metrics();

-- Coffee: need a similar trigger for restock_category_id changes
-- The coffee par/restock is calculated by handle_manual_inventory_update or nudge functions
-- Let's create a simple trigger that recalculates when restock_category_id changes
CREATE OR REPLACE FUNCTION trg_recalc_coffee_on_category_change()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.restock_category_id IS DISTINCT FROM NEW.restock_category_id THEN
    NEW.par := calculate_par(NEW.origin_id);
    NEW.restock_level := calculate_restock_level(NEW.origin_id);
    NEW.to_order := GREATEST(0, NEW.par - COALESCE(NEW.in_stock, 0));
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_coffee_restock_category_change ON coffee_inventory;
CREATE TRIGGER trg_coffee_restock_category_change
  BEFORE UPDATE OF restock_category_id
  ON coffee_inventory
  FOR EACH ROW EXECUTE FUNCTION trg_recalc_coffee_on_category_change();
