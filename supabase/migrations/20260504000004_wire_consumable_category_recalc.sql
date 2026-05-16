-- 20260504000004_wire_consumable_category_recalc.sql
-- Wire the existing trg_recalc_consumable_on_category_change function
-- to consumable_inventory so changing a row's restock_category_id
-- automatically recomputes par + restock_level.
--
-- WHY
--   The function was written but never attached to a trigger. coffee_
--   inventory has the parallel trg_coffee_restock_category_change wired
--   correctly; consumable_inventory was missed. Result: changing the
--   restock category on the consumables tab leaves par and restock_level
--   stale until the next manual nudge or unrelated update.
--
-- WHAT
--   AFTER UPDATE OF restock_category_id trigger calling the existing
--   function. WHEN clause restricts to actual category changes so we
--   don't refire on unrelated column edits.

BEGIN;

DROP TRIGGER IF EXISTS trg_consumable_restock_category_change
  ON public.consumable_inventory;

CREATE TRIGGER trg_consumable_restock_category_change
  AFTER UPDATE OF restock_category_id ON public.consumable_inventory
  FOR EACH ROW
  WHEN (OLD.restock_category_id IS DISTINCT FROM NEW.restock_category_id)
  EXECUTE FUNCTION public.trg_recalc_consumable_on_category_change();

COMMIT;
