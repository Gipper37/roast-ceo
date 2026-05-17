-- Fix: restock category triggers need to be AFTER, not BEFORE
-- BEFORE triggers see old data when functions query the table

BEGIN;

-- Drop the old BEFORE trigger on consumables (the one that includes restock_category_id)
DROP TRIGGER IF EXISTS trg_update_consumable_ordering ON consumable_inventory;

-- Recreate WITHOUT restock_category_id in the column list
-- (this is the original trigger that handles inventory_count, par, etc.)
CREATE TRIGGER trg_update_consumable_ordering
  BEFORE INSERT OR UPDATE OF consumable_inventory_id, facility_id, last_inventory_date, inventory_count, par, restock_level
  ON consumable_inventory
  FOR EACH ROW EXECUTE FUNCTION update_consumable_metrics();

-- New AFTER trigger specifically for restock_category_id changes
CREATE OR REPLACE FUNCTION trg_recalc_consumable_on_category_change()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  -- Row is already committed, so calculate_consumable_par reads new category
  UPDATE consumable_inventory SET
    par = calculate_consumable_par(NEW.consumable_inventory_id, NEW.facility_id),
    restock_level = calculate_consumable_restock_level(NEW.consumable_inventory_id, NEW.facility_id)
  WHERE consumable_inventory_id = NEW.consumable_inventory_id;
  RETURN NULL; -- AFTER trigger returns NULL
END;
$$;

DROP TRIGGER IF EXISTS trg_consumable_restock_category_change ON consumable_inventory;
CREATE TRIGGER trg_consumable_restock_category_change
  AFTER UPDATE OF restock_category_id
  ON consumable_inventory
  FOR EACH ROW EXECUTE FUNCTION trg_recalc_consumable_on_category_change();

-- Fix coffee trigger too — same issue
DROP TRIGGER IF EXISTS trg_coffee_restock_category_change ON coffee_inventory;

CREATE OR REPLACE FUNCTION trg_recalc_coffee_on_category_change()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  -- Row is already committed, so calculate_par reads new category
  UPDATE coffee_inventory SET
    par = calculate_par(NEW.origin_id),
    restock_level = calculate_restock_level(NEW.origin_id),
    to_order = GREATEST(0, calculate_par(NEW.origin_id) - COALESCE(NEW.in_stock, 0))
  WHERE origin_id = NEW.origin_id;
  RETURN NULL;
END;
$$;

CREATE TRIGGER trg_coffee_restock_category_change
  AFTER UPDATE OF restock_category_id
  ON coffee_inventory
  FOR EACH ROW EXECUTE FUNCTION trg_recalc_coffee_on_category_change();

COMMIT;
