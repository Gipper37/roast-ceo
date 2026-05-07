-- Updated restock-category defaults (v2).
--
-- Replaces the v1 backfill (20260506000005, reverted by 20260506000007)
-- with new numbers and a stricter scope:
--
--   Quick Restock  : 1 / 0.5  →  3 / 0.5
--   Standard       : 3 / 1.5  →  6 / 1.5
--   Extended Lead  : 6 / 3    →  12 / 6
--
-- Scope: only rows still at the *original* seed defaults are bumped.
-- Any tenant who customized their copy (e.g. R7CbqHmA1j has Quick=6/1
-- and Extended=12/6) is deliberately left alone — the WHERE clause
-- matches the exact original tuple so customized rows don't qualify.
--
-- Side effect: changing target_months / reorder_months fires
-- trg_propagate_restock_category_change which recalculates par +
-- restock_level on every coffee_inventory and consumable_inventory
-- row referencing the updated category.

BEGIN;

-- Quick Restock: 1 / 0.5  →  3 / 0.5  (target only — reorder unchanged)
UPDATE restock_category
SET target_months = 3
WHERE name           = 'Quick Restock'
  AND target_months  = 1
  AND reorder_months = 0.5
  AND is_global      = true;

-- Standard: 3 / 1.5  →  6 / 1.5  (target only)
UPDATE restock_category
SET target_months = 6
WHERE name           = 'Standard'
  AND target_months  = 3
  AND reorder_months = 1.5
  AND is_global      = true;

-- Extended Lead: 6 / 3  →  12 / 6
UPDATE restock_category
SET target_months  = 12,
    reorder_months = 6
WHERE name           = 'Extended Lead'
  AND target_months  = 6
  AND reorder_months = 3
  AND is_global      = true;

COMMIT;
