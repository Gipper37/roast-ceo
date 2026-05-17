-- Revert the restock-category backfill from 20260506000005.
--
-- That migration bumped existing tenants' Quick Restock and Standard
-- rows from 1/0.5 → 4/2 and 3/1.5 → 6/3 respectively. Right call for
-- *new* signups (which is why the edge function seed stays at the new
-- numbers), but wrong call for live tenants — those rows are
-- facility-scoped and effectively owned by each tenant. Modifying them
-- under the tenant's feet shifts their reorder behavior without
-- consent.
--
-- This migration restores the rows that 20260506000005 touched. We
-- identify them by the post-bump tuple (name, target_months,
-- reorder_months, is_global=true) — exact inverse of the previous
-- WHERE clause. Tenants who manually adopted 4/2 or 6/3 since the
-- bump (vanishingly unlikely given the short window, but possible)
-- would also be reverted; that's an acceptable rounding error vs
-- leaving the unsolicited change in place.

BEGIN;

-- Standard: 6 / 3  →  3 / 1.5
UPDATE restock_category
SET target_months  = 3,
    reorder_months = 1.5
WHERE name             = 'Standard'
  AND target_months    = 6
  AND reorder_months   = 3
  AND is_global        = true;

-- Quick Restock: 4 / 2  →  1 / 0.5
UPDATE restock_category
SET target_months  = 1,
    reorder_months = 0.5
WHERE name             = 'Quick Restock'
  AND target_months    = 4
  AND reorder_months   = 2
  AND is_global        = true;

COMMIT;
