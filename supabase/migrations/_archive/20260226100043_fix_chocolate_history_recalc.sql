-- Migration 00043: Fix Chocolate history entry + recalculate
--
-- The coffee_inventory_history entry for Chocolate (6c752b40) has incorrect
-- test data: Feb 6 / 100 bags. The correct baseline is Jan 7 / 65 bags.
--
-- The parent table (coffee_inventory) was already corrected manually by the
-- user, but the history table still has the wrong data. This migration fixes
-- the history and triggers a recalculation so all derived columns are correct.

-- ═══════════════════════════════════════════════════════════════
-- A. Fix Chocolate history entry
-- ═══════════════════════════════════════════════════════════════

UPDATE public.coffee_inventory_history
SET inventory_date = '2026-01-07',
    bag_count = 65,
    notes = 'Corrected from test data (was Feb 6 / 100 bags)'
WHERE origin_id = '6c752b40'
  AND facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de'
  AND inventory_date = '2026-02-06'
  AND bag_count = 100;

-- ═══════════════════════════════════════════════════════════════
-- B. Recalculate all coffee_inventory rows
-- ═══════════════════════════════════════════════════════════════
-- Touching last_inventory fires trg_manual_inventory_update which
-- recalculates par, restock_level, in_stock_lbs, in_stock, to_order_bags.

UPDATE public.coffee_inventory
SET last_inventory = last_inventory;
