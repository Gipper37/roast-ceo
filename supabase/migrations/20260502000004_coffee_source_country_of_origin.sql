-- ============================================================================
-- Add structured country_of_origin to coffee_source.
--
-- Today coffee_source.coffee_name is freeform text — typically something
-- like "Brazil Alta Mogiana SS FC 14/16" where the country is baked into
-- the start of the string. That makes filtering by country impossible
-- and pushes the burden of remembering a naming convention onto the user.
--
-- This migration adds a structured `country_of_origin` column populated
-- from a fixed coffee-producing-countries list (see lib/coffee-options.ts
-- COUNTRIES_OF_ORIGIN). The frontend swaps the freeform "Coffee Name"
-- input for an Origin dropdown bound to this column.
--
-- coffee_name is preserved (no data drop) as the recognizable identifier
-- for the coffee — backwards compatible with everything that reads it
-- today. Existing display labels still work; country_of_origin is
-- additive.
--
-- Backfill strategy: parse the country prefix from each existing
-- coffee_name. If the start of the string matches one of the known
-- countries, set country_of_origin. Otherwise leave NULL — the user
-- will pick a country the next time they edit that source.
-- ============================================================================

BEGIN;

ALTER TABLE coffee_source
  ADD COLUMN IF NOT EXISTS country_of_origin text;

COMMENT ON COLUMN coffee_source.country_of_origin IS
  'Structured country (or US state for Hawaii) that this coffee comes from. '
  'Values come from the COUNTRIES_OF_ORIGIN picker in lib/coffee-options.ts. '
  'NULL is allowed for legacy sources; the dropdown nudges users to fill '
  'it in next time they edit. coffee_name remains as the freeform '
  'recognizable identifier — country_of_origin is purely additive.';

-- Backfill — parse country prefix from coffee_name. The list of countries
-- below mirrors lib/coffee-options.ts; longer names sorted first so
-- "Dominican Republic" matches before "Dominican" alone, and
-- "Papua New Guinea" matches before "Papua".
WITH country_list (country) AS (VALUES
  ('Dominican Republic'),
  ('Papua New Guinea'),
  ('USA – Hawaii'),
  ('USA - Hawaii'),  -- alt dash variant
  ('Costa Rica'),
  ('El Salvador'),
  ('Puerto Rico'),
  ('Sri Lanka'),
  ('Timor-Leste'),
  ('DR Congo'),
  ('Hawaii'),  -- common shorthand
  ('Burundi'), ('Cameroon'), ('Ethiopia'), ('Kenya'), ('Madagascar'),
  ('Malawi'), ('Rwanda'), ('Tanzania'), ('Uganda'), ('Yemen'), ('Zambia'),
  ('Zimbabwe'), ('Cuba'), ('Guatemala'), ('Haiti'), ('Honduras'),
  ('Jamaica'), ('Mexico'), ('Nicaragua'), ('Panama'), ('Bolivia'),
  ('Brazil'), ('Colombia'), ('Ecuador'), ('Peru'), ('Venezuela'),
  ('China'), ('India'), ('Indonesia'), ('Laos'), ('Philippines'),
  ('Thailand'), ('Vanuatu'), ('Vietnam')
)
UPDATE coffee_source cs
SET country_of_origin = CASE
  -- Hawaii shorthand → canonical "USA – Hawaii"
  WHEN cs.coffee_name ILIKE 'Hawaii%' THEN 'USA – Hawaii'
  WHEN cs.coffee_name ILIKE 'USA - Hawaii%' THEN 'USA – Hawaii'
  ELSE matched.country
END
FROM (
  SELECT cs2.coffee_source_id, cl.country
  FROM coffee_source cs2
  JOIN country_list cl
    ON cs2.coffee_name ILIKE cl.country || '%'
  WHERE cs2.country_of_origin IS NULL
) matched
WHERE cs.coffee_source_id = matched.coffee_source_id;

-- Distribution check for the migration log.
DO $$
DECLARE
  total_rows int;
  matched_rows int;
BEGIN
  SELECT COUNT(*) INTO total_rows FROM coffee_source;
  SELECT COUNT(*) INTO matched_rows FROM coffee_source WHERE country_of_origin IS NOT NULL;
  RAISE NOTICE 'coffee_source: % / % rows backfilled with country_of_origin (% NULL)',
    matched_rows, total_rows, total_rows - matched_rows;
END $$;

COMMIT;
