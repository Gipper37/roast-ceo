-- Adjust the seeded global restock-category defaults.
--
-- The original numbers (Quick=1mo target / 0.5mo reorder, Standard=3mo / 1.5mo)
-- were too aggressive for typical roasters — Standard dipping to 1.5 months
-- triggered constant reorder alerts and Quick at 1 month rarely matched the
-- "fast supplier" intent it was meant to convey. New defaults bump both up:
--
--   Quick Restock  : 4 months target / 2 months reorder (was 1 / 0.5)
--   Standard       : 6 months target / 3 months reorder (was 3 / 1.5)
--   Extended Lead  : unchanged at 6 / 3 (overlap with new Standard intentional;
--                    a follow-up will rename / repurpose Extended if needed)
--
-- Scope: only rows still at the *original* seed values are updated. Roasters
-- who tweaked their copy keep their tweaked values. Identification is by the
-- (name, target_months, reorder_months, is_global=true) tuple.
--
-- Side-effect: bumping target_months / reorder_months fires
-- trg_propagate_restock_category_change which recalculates par + restock_level
-- on every coffee_inventory and consumable_inventory row referencing the
-- updated category. This is the desired behavior — alerts re-tune to the new
-- defaults automatically.

BEGIN;

-- Quick Restock: 1 / 0.5  →  4 / 2
UPDATE restock_category
SET target_months  = 4,
    reorder_months = 2
WHERE name             = 'Quick Restock'
  AND target_months    = 1
  AND reorder_months   = 0.5
  AND is_global        = true;

-- Standard: 3 / 1.5  →  6 / 3
UPDATE restock_category
SET target_months  = 6,
    reorder_months = 3
WHERE name             = 'Standard'
  AND target_months    = 3
  AND reorder_months   = 1.5
  AND is_global        = true;

COMMIT;
