-- ============================================================================
-- Add is_global flag to restock_category.
--
-- Background: the 3 seeded restock categories (Quick Restock, Standard,
-- Extended Lead) are part of the standard system vocabulary — every
-- facility gets them on signup and they shouldn't be deletable. Today
-- the delete gate is `!is_default`, which conflates "non-deletable"
-- with "auto-pick when nothing else is specified" (only Standard
-- carries that latter meaning). Result: Quick Restock and Extended
-- Lead show a Trash icon and read as user-created, even though
-- they're seeded.
--
-- This migration adds `is_global` as the protected-from-delete flag.
-- `is_default` keeps its narrower meaning: the category that
-- auto-applies to new items when the user doesn't pick one (Standard
-- only).
--
-- Backfill: any row whose name matches the 3 seeded names is flagged
-- global. Future facilities seeded by company-signup also get the
-- flag (handled in the edge function).
-- ============================================================================

BEGIN;

ALTER TABLE restock_category
  ADD COLUMN IF NOT EXISTS is_global boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN restock_category.is_global IS
  'Seeded system category — non-deletable in the UI. The 3 standard '
  'categories (Quick Restock, Standard, Extended Lead) are seeded per '
  'facility on signup. Distinct from is_default, which marks the '
  'single category that auto-applies to new items.';

-- Backfill — match the canonical 3 seeded names. We allow company-name
-- variants (Standard / Quick Restock / Extended Lead) but stay strict
-- to avoid promoting a user-created "Standard Plus" or similar.
UPDATE restock_category
SET is_global = true
WHERE name IN ('Quick Restock', 'Standard', 'Extended Lead');

COMMIT;
