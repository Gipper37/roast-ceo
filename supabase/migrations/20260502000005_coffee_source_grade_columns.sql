-- ============================================================================
-- Add structured grade columns to coffee_source.
--
-- Background: every origin uses its own grading vocabulary (Brazil SS FC
-- 17/18, Kenya AA, Ethiopia G1, Colombia Supremo EP, Costa Rica SHB,
-- Indonesia Grade 1, Hawaii Extra Fancy, etc.). The legacy `coffee_name`
-- field jammed all of this into one freeform string, which made it
-- impossible to filter ("show me all peaberry coffees" or "all SS-quality
-- Brazilian sources").
--
-- This migration adds 6 structured columns + 1 cached display label, so
-- the UI can render origin-specific grade composers (a separate UI for
-- Brazilian SS/FC/screen vs Kenyan AA/AB) and the data is queryable.
--
-- Column resolution per country:
--   Brazil:       grade_quality (SS/S/HS/RY) + grade_classification (FC/GC)
--                 + grade_screen + is_pulped_natural + is_peaberry
--   Kenya:        grade_quality (AA/AB/C/T/etc.) + is_peaberry
--   Colombia:     grade_quality (Supremo/Excelso/UGQ) + grade_prep (EP)
--                 + is_peaberry
--   Ethiopia:     grade_quality (G1-G5) + is_peaberry
--   Costa Rica:   grade_quality (SHB/HB/MHB/etc.)
--   Honduras etc: grade_quality (SHG/HG/CS)
--   Indonesia:    grade_quality (Grade 1-6)
--   Vietnam:      grade_quality (Grade 1/2/2A/R) + grade_screen
--   India:        grade_prep (Plantation/Cherry/Robusta) + grade_quality
--   Hawaii Kona:  grade_quality (Extra Fancy/Fancy/etc.) + is_peaberry
--
-- The legacy `coffee_name` column is preserved (no data drop) — it
-- continues to display as a fallback when none of the structured columns
-- are populated, and the UI shows a "needs structuring" hint when a row
-- has legacy text but no structured data.
-- ============================================================================

BEGIN;

ALTER TABLE coffee_source
  ADD COLUMN IF NOT EXISTS grade_quality        text,
  ADD COLUMN IF NOT EXISTS grade_classification text,
  ADD COLUMN IF NOT EXISTS grade_screen         text,
  ADD COLUMN IF NOT EXISTS grade_prep           text,
  ADD COLUMN IF NOT EXISTS is_peaberry          boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS is_pulped_natural    boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS grade_label          text;

COMMENT ON COLUMN coffee_source.grade_quality IS
  'Primary grade per origin — Brazil SS/S/HS/RY, Ethiopia G1-G5, Kenya AA/AB, '
  'Colombia Supremo/Excelso, Costa Rica SHB/HB, Indonesia Grade 1-6, Hawaii '
  'Extra Fancy, etc. Drives the per-country grade dropdown. See '
  'lib/coffee-options.ts GRADES_BY_COUNTRY for the per-origin lists.';
COMMENT ON COLUMN coffee_source.grade_classification IS
  'Brazil-specific secondary cup classification (FC = Fine Cup, GC = Good '
  'Cup). NULL for other origins.';
COMMENT ON COLUMN coffee_source.grade_screen IS
  'Sieve size (14/16, 16/18, 17/18, 18+). Used by Brazil and Vietnam where '
  'screen is a separate spec from quality. Most other origins embed screen '
  'in grade_quality (e.g. Kenya AA = 17/18 implicitly).';
COMMENT ON COLUMN coffee_source.grade_prep IS
  'Preparation modifier — Colombia EP (European Prep), India Plantation/Cherry, '
  'Mexico Prime Washed. NULL when no prep classification applies.';
COMMENT ON COLUMN coffee_source.is_peaberry IS
  'Universal flag — peaberry beans (single-bean cherries, e.g. Kenya PB, '
  'Colombia Caracol, Hawaii Peaberry No. 1) occur in every origin. Tracked '
  'as its own boolean rather than a per-country grade so reports can sum '
  '"all peaberry" across origins.';
COMMENT ON COLUMN coffee_source.is_pulped_natural IS
  'Brazil-specific processing modifier — pulped natural is a hybrid wet/dry '
  'process common in Brazil. Other origins use the `process` field for this '
  'kind of distinction.';
COMMENT ON COLUMN coffee_source.grade_label IS
  'Composed display string ("SS FC 17/18 Peaberry"). Set on save by the '
  'GradeInput component. Cache for cheap rendering — the canonical source '
  'of truth is the structured columns above.';

-- Backfill: best-effort parse of the legacy coffee_name string. We only
-- run this for sources where country_of_origin was successfully detected
-- by the previous migration (20260502000004) — without a country, we don't
-- know which grading taxonomy to apply.
--
-- Brazil parsing — looks for SS/S/HS/RY tokens, FC/GC tokens, sieve sizes
-- like "14/16", "17/18", "18+", and the "PN" pulped natural marker.
UPDATE coffee_source SET
  grade_quality = CASE
    WHEN coffee_name ~* '\ySS\y'  THEN 'SS'
    WHEN coffee_name ~* '\yHS\y'  THEN 'HS'
    WHEN coffee_name ~* '\yRY\y'  THEN 'RY'
    WHEN coffee_name ~* '\yS\s+(FC|GC|\d)' THEN 'S'  -- 'S' alone, must be followed by FC/GC/digit
    ELSE NULL
  END,
  grade_classification = CASE
    WHEN coffee_name ~* '\yFC\y' THEN 'FC'
    WHEN coffee_name ~* '\yGC\y' THEN 'GC'
    ELSE NULL
  END,
  grade_screen = (
    SELECT (regexp_match(coffee_name, '(\d{2}/\d{2}|\d{2}\+)', 'i'))[1]
  ),
  is_pulped_natural = (coffee_name ~* '\yPN\y' OR coffee_name ~* 'Pulped Natural')
WHERE country_of_origin = 'Brazil';

-- Kenya parsing — first letter sequence after country prefix.
UPDATE coffee_source SET
  grade_quality = CASE
    WHEN coffee_name ~* '\yAA\y'    THEN 'AA'
    WHEN coffee_name ~* '\yAB\y'    THEN 'AB'
    WHEN coffee_name ~* '\yPB\y'    THEN NULL  -- handled by is_peaberry below
    WHEN coffee_name ~* '\yC\y'     THEN 'C'
    WHEN coffee_name ~* '\yTT\y'    THEN 'TT'
    WHEN coffee_name ~* '\yT\y'     THEN 'T'
    WHEN coffee_name ~* 'MH/ML'     THEN 'MH/ML'
    ELSE NULL
  END,
  is_peaberry = (coffee_name ~* '\yPB\y' OR coffee_name ~* 'Peaberry')
WHERE country_of_origin = 'Kenya';

-- Tanzania parsing — same shape as Kenya.
UPDATE coffee_source SET
  grade_quality = CASE
    WHEN coffee_name ~* '\yAA\y' THEN 'AA'
    WHEN coffee_name ~* '\yAB\y' THEN 'AB'
    WHEN coffee_name ~* '\yPB\y' THEN NULL
    WHEN coffee_name ~* '\yA\y'  THEN 'A'
    WHEN coffee_name ~* '\yB\y'  THEN 'B'
    WHEN coffee_name ~* '\yC\y'  THEN 'C'
    ELSE NULL
  END,
  is_peaberry = (coffee_name ~* '\yPB\y' OR coffee_name ~* 'Peaberry')
WHERE country_of_origin = 'Tanzania';

-- Ethiopia parsing — G1-G5 grade letter.
UPDATE coffee_source SET
  grade_quality = CASE
    WHEN coffee_name ~* '\yG1\y' THEN 'G1'
    WHEN coffee_name ~* '\yG2\y' THEN 'G2'
    WHEN coffee_name ~* '\yG3\y' THEN 'G3'
    WHEN coffee_name ~* '\yG4\y' THEN 'G4'
    WHEN coffee_name ~* '\yG5\y' THEN 'G5'
    WHEN coffee_name ~* 'Grade 1' THEN 'G1'
    WHEN coffee_name ~* 'Grade 2' THEN 'G2'
    WHEN coffee_name ~* 'Grade 3' THEN 'G3'
    WHEN coffee_name ~* 'Grade 4' THEN 'G4'
    WHEN coffee_name ~* 'Grade 5' THEN 'G5'
    ELSE NULL
  END,
  is_peaberry = (coffee_name ~* '\yPeaberry\y' OR coffee_name ~* '\yPB\y')
WHERE country_of_origin = 'Ethiopia';

-- Colombia parsing.
UPDATE coffee_source SET
  grade_quality = CASE
    WHEN coffee_name ~* 'Supremo' THEN 'Supremo'
    WHEN coffee_name ~* 'Excelso' THEN 'Excelso'
    WHEN coffee_name ~* 'UGQ'     THEN 'UGQ'
    ELSE NULL
  END,
  grade_prep = CASE
    WHEN coffee_name ~* '\yEP\y' OR coffee_name ~* 'European Prep' THEN 'EP'
    ELSE NULL
  END,
  is_peaberry = (coffee_name ~* 'Caracol' OR coffee_name ~* 'Peaberry')
WHERE country_of_origin = 'Colombia';

-- Central America altitude grades.
UPDATE coffee_source SET
  grade_quality = CASE
    WHEN coffee_name ~* '\ySHB\y' THEN 'SHB'
    WHEN coffee_name ~* '\yGHB\y' THEN 'GHB'
    WHEN coffee_name ~* '\yHB\y'  THEN 'HB'
    WHEN coffee_name ~* '\yMHB\y' THEN 'MHB'
    WHEN coffee_name ~* '\yLGA\y' THEN 'LGA'
    WHEN coffee_name ~* '\ySH\y'  THEN 'SH'
    ELSE NULL
  END
WHERE country_of_origin IN ('Costa Rica', 'Guatemala');

UPDATE coffee_source SET
  grade_quality = CASE
    WHEN coffee_name ~* '\ySHG\y' THEN 'SHG'
    WHEN coffee_name ~* '\yHG\y'  THEN 'HG'
    WHEN coffee_name ~* '\yCS\y'  THEN 'CS'
    WHEN coffee_name ~* '\yMG\y'  THEN 'MG'
    ELSE NULL
  END
WHERE country_of_origin IN ('Honduras', 'El Salvador', 'Nicaragua', 'Mexico');

-- Hawaii Kona Coffee Council standards.
UPDATE coffee_source SET
  grade_quality = CASE
    WHEN coffee_name ~* 'Extra Fancy' THEN 'Extra Fancy'
    WHEN coffee_name ~* '\yFancy\y'   THEN 'Fancy'
    WHEN coffee_name ~* 'Number 1'    THEN 'Number 1'
    WHEN coffee_name ~* '\ySelect\y'  THEN 'Select'
    WHEN coffee_name ~* '\yPrime\y'   THEN 'Prime'
    ELSE NULL
  END,
  is_peaberry = (coffee_name ~* '\yPeaberry\y' OR coffee_name ~* '\yPB\y')
WHERE country_of_origin IN ('USA – Hawaii', 'USA – Kona');

-- Compose grade_label for every row with at least one structured field
-- populated. Pieces joined by spaces, NULL parts skipped, peaberry/PN
-- flags appended at the end as descriptive suffixes.
UPDATE coffee_source SET grade_label = NULLIF(TRIM(BOTH ' ' FROM concat_ws(' ',
  grade_quality,
  grade_classification,
  grade_screen,
  grade_prep,
  CASE WHEN is_pulped_natural THEN 'PN' ELSE NULL END,
  CASE WHEN is_peaberry THEN 'Peaberry' ELSE NULL END
)), '');

-- Sanity check log line.
DO $$
DECLARE
  total int;
  with_quality int;
  with_peaberry int;
  with_label int;
BEGIN
  SELECT COUNT(*) INTO total FROM coffee_source;
  SELECT COUNT(*) INTO with_quality FROM coffee_source WHERE grade_quality IS NOT NULL;
  SELECT COUNT(*) INTO with_peaberry FROM coffee_source WHERE is_peaberry = true;
  SELECT COUNT(*) INTO with_label FROM coffee_source WHERE grade_label IS NOT NULL;
  RAISE NOTICE 'coffee_source: % rows total, % with grade_quality, % flagged peaberry, % with composed grade_label',
    total, with_quality, with_peaberry, with_label;
END $$;

COMMIT;
