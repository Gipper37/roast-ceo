-- ============================================================================
-- Drop is_pulped_natural column.
--
-- Migration 20260502000005 added is_pulped_natural as a boolean grade
-- modifier on coffee_source. Turns out Pulped Natural is already a value
-- in the existing `process` column (see PROCESSES in lib/coffee-options.ts)
-- — the boolean is redundant and would split the same concept across two
-- columns.
--
-- This migration:
--   1. Migrates any rows where is_pulped_natural=true → sets process =
--      'Pulped Natural' (only when process is currently NULL, to avoid
--      stomping a more specific process value the user might have set).
--   2. Drops the is_pulped_natural column.
--   3. Recomposes grade_label without the "PN" suffix that the previous
--      migration appended.
-- ============================================================================

BEGIN;

-- 1. Carry the boolean state into the existing process column.
UPDATE coffee_source
SET process = 'Pulped Natural'
WHERE is_pulped_natural = true
  AND (process IS NULL OR process = '');

-- 2. Drop the redundant column.
ALTER TABLE coffee_source DROP COLUMN IF EXISTS is_pulped_natural;

-- 3. Recompose grade_label — same composer as 20260502000005 minus the PN flag.
UPDATE coffee_source SET grade_label = NULLIF(TRIM(BOTH ' ' FROM concat_ws(' ',
  grade_quality,
  grade_classification,
  grade_screen,
  grade_prep,
  CASE WHEN is_peaberry THEN 'Peaberry' ELSE NULL END
)), '');

DO $$
DECLARE
  pn_count int;
BEGIN
  SELECT COUNT(*) INTO pn_count FROM coffee_source WHERE process = 'Pulped Natural';
  RAISE NOTICE 'coffee_source: % rows with process=''Pulped Natural''', pn_count;
END $$;

COMMIT;
