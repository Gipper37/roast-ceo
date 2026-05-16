-- 20260504000009_backfill_roaster_unit_brands.sql
-- One-time backfill of brand + model on existing roaster_units rows
-- whose `name` already encodes the brand + model (the convention up
-- to now). Only updates rows where brand IS NULL — never clobbers a
-- value the user has already set explicitly.
--
-- Backfilling lets the new Roaster Units form, the brand-aware driver
-- picker, and the model dropdowns work immediately for existing data
-- without forcing the user to re-enter every roaster.

BEGIN;

-- Diedrich
UPDATE public.roaster_units
SET brand = 'Diedrich',
    model = NULLIF(TRIM(REGEXP_REPLACE(name, '^Diedrich\s*', '', 'i')), '')
WHERE brand IS NULL
  AND name ILIKE 'Diedrich%';

-- Giesen
UPDATE public.roaster_units
SET brand = 'Giesen',
    model = NULLIF(TRIM(REGEXP_REPLACE(name, '^Giesen\s*', '', 'i')), '')
WHERE brand IS NULL
  AND name ILIKE 'Giesen%';

-- Probat
UPDATE public.roaster_units
SET brand = 'Probat',
    model = NULLIF(TRIM(REGEXP_REPLACE(name, '^Probat\s*', '', 'i')), '')
WHERE brand IS NULL
  AND name ILIKE 'Probat%';

-- Loring
UPDATE public.roaster_units
SET brand = 'Loring',
    model = NULLIF(TRIM(REGEXP_REPLACE(name, '^Loring\s*', '', 'i')), '')
WHERE brand IS NULL
  AND name ILIKE 'Loring%';

-- Huky / Huky500 / Huky 500
UPDATE public.roaster_units
SET brand = 'Huky',
    model = COALESCE(
      NULLIF(TRIM(REGEXP_REPLACE(name, '^Huky\s*', '', 'i')), ''),
      '500'
    )
WHERE brand IS NULL
  AND name ILIKE 'Huky%';

-- San Franciscan
UPDATE public.roaster_units
SET brand = 'San Franciscan',
    model = NULLIF(TRIM(REGEXP_REPLACE(name, '^San\s*Franciscan\s*', '', 'i')), '')
WHERE brand IS NULL
  AND name ILIKE 'San%Franciscan%';

-- Mill City
UPDATE public.roaster_units
SET brand = 'Mill City',
    model = NULLIF(TRIM(REGEXP_REPLACE(name, '^Mill\s*City\s*', '', 'i')), '')
WHERE brand IS NULL
  AND name ILIKE 'Mill%City%';

-- Toper / Has Garanti / IKAWA — same pattern, only fire if any rows exist.
UPDATE public.roaster_units SET brand = 'Toper', model = NULLIF(TRIM(REGEXP_REPLACE(name, '^Toper\s*', '', 'i')), '') WHERE brand IS NULL AND name ILIKE 'Toper%';
UPDATE public.roaster_units SET brand = 'Has Garanti', model = NULLIF(TRIM(REGEXP_REPLACE(name, '^Has\s*Garanti\s*', '', 'i')), '') WHERE brand IS NULL AND name ILIKE 'Has%Garanti%';
UPDATE public.roaster_units SET brand = 'IKAWA', model = NULLIF(TRIM(REGEXP_REPLACE(name, '^IKAWA\s*', '', 'i')), '') WHERE brand IS NULL AND name ILIKE 'IKAWA%';

-- Anything left without a brand → 'Other'. Leave model NULL so the user
-- knows to fill it in.
UPDATE public.roaster_units
SET brand = 'Other'
WHERE brand IS NULL;

DO $$
DECLARE
  v_count integer;
BEGIN
  SELECT COUNT(*) INTO v_count FROM public.roaster_units WHERE brand IS NOT NULL;
  RAISE NOTICE 'roaster_units brand backfill complete: % rows now carry a brand', v_count;
END $$;

COMMIT;
