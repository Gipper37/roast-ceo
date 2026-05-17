-- ============================================================================
-- Aggressive cleanup pass over coffee_source — catches all the patterns
-- the previous backfills (20260502000004/005/006/007) missed:
--
--   • "Decaf X" prefix where X is the actual country
--   • Indonesian island as identity (Bali, Sulawesi, Flores, etc.)
--   • Timor → Timor-Leste
--   • Kona alone → USA – Kona
--   • Country at END of name ("Cajamarca 83+ Peru")
--   • Expanded region lists for Honduras, Nicaragua, Peru, PNG
--   • Process detection (Wet Hulled, Honey, Swiss Water)
--   • Cert detection (FT-USA, FT-FLO, ORGANIC, RFA)
--
-- All passes are conservative — only set fields when confident, never
-- overwrite values the user has already touched.
-- ============================================================================

BEGIN;

-- ── Pass 1: "Decaf X" prefix ───────────────────────────────────────────────
-- "Decaf Colombia X" → country='Colombia'. Strip the leading "Decaf"
-- (case-insensitive) and look for known countries in the remainder.
UPDATE coffee_source SET country_of_origin = matched.country
FROM (
  SELECT cs.coffee_source_id,
    CASE
      WHEN cs.coffee_name ~* '^\s*decaf\s+colombia'   THEN 'Colombia'
      WHEN cs.coffee_name ~* '^\s*decaf\s+honduras'   THEN 'Honduras'
      WHEN cs.coffee_name ~* '^\s*decaf\s+mexico'     THEN 'Mexico'
      WHEN cs.coffee_name ~* '^\s*decaf\s+peru'       THEN 'Peru'
      WHEN cs.coffee_name ~* '^\s*decaf\s+brazil'     THEN 'Brazil'
      WHEN cs.coffee_name ~* '^\s*decaf\s+ethiopia'   THEN 'Ethiopia'
      WHEN cs.coffee_name ~* '^\s*decaf\s+guatemala'  THEN 'Guatemala'
      WHEN cs.coffee_name ~* '^\s*decaf\s+nicaragua'  THEN 'Nicaragua'
      ELSE NULL
    END AS country
  FROM coffee_source cs
  WHERE cs.country_of_origin IS NULL
    AND cs.coffee_name ~* '^\s*decaf\s'
) matched
WHERE coffee_source.coffee_source_id = matched.coffee_source_id
  AND matched.country IS NOT NULL;

-- ── Pass 2: Indonesian islands → country='Indonesia' + region=island ───
-- Bali / Sulawesi / Flores / Java / Sumatra / Aceh are all Indonesia.
-- The roaster identifies by island, so we map: country='Indonesia',
-- region=<island name>.
UPDATE coffee_source SET
  country_of_origin = 'Indonesia',
  region = COALESCE(NULLIF(coffee_source.region, ''), matched.matched_region)
FROM (
  SELECT cs.coffee_source_id,
    CASE
      WHEN cs.coffee_name ~* '\ybali\y'     THEN 'Bali'
      WHEN cs.coffee_name ~* '\ysulawesi\y' THEN 'Sulawesi'
      WHEN cs.coffee_name ~* '\yflores\y'   THEN 'Flores'
      WHEN cs.coffee_name ~* '\ysumatra\y'  THEN 'Sumatra'
      WHEN cs.coffee_name ~* '\yjava\y'     THEN 'Java'
      WHEN cs.coffee_name ~* '\yaceh\y'     THEN 'Aceh'
      ELSE NULL
    END AS matched_region
  FROM coffee_source cs
  WHERE cs.country_of_origin IS NULL
    AND (
      cs.coffee_name ~* '\ybali\y' OR
      cs.coffee_name ~* '\ysulawesi\y' OR
      cs.coffee_name ~* '\yflores\y' OR
      cs.coffee_name ~* '\ysumatra\y' OR
      cs.coffee_name ~* '\yjava\y' OR
      cs.coffee_name ~* '\yaceh\y'
    )
) matched
WHERE coffee_source.coffee_source_id = matched.coffee_source_id;

-- ── Pass 3: Timor → Timor-Leste ───────────────────────────────────────
UPDATE coffee_source
SET country_of_origin = 'Timor-Leste'
WHERE country_of_origin IS NULL
  AND coffee_name ~* '^\s*timor\y';

-- ── Pass 4: Kona alone → USA – Kona ───────────────────────────────────
-- When coffee_name starts with "Kona" (no USA prefix), it's Hawaii Kona.
-- Region defaults to "Kona" so the structured pieces compose cleanly.
UPDATE coffee_source SET
  country_of_origin = 'USA – Kona',
  region = COALESCE(NULLIF(coffee_source.region, ''), 'Kona')
WHERE country_of_origin IS NULL
  AND coffee_name ~* '^\s*kona\y';

-- ── Pass 5: Country at END of name ────────────────────────────────────
-- "Cajamarca 83+ Peru" pattern. Run AFTER the start-of-string passes so
-- we don't re-match anything already classified.
UPDATE coffee_source SET country_of_origin = matched.country
FROM (
  SELECT cs.coffee_source_id,
    CASE
      WHEN cs.coffee_name ~* '\yperu\s*$'      THEN 'Peru'
      WHEN cs.coffee_name ~* '\ybrazil\s*$'    THEN 'Brazil'
      WHEN cs.coffee_name ~* '\ycolombia\s*$'  THEN 'Colombia'
      WHEN cs.coffee_name ~* '\yethiopia\s*$'  THEN 'Ethiopia'
      WHEN cs.coffee_name ~* '\ykenya\s*$'     THEN 'Kenya'
      WHEN cs.coffee_name ~* '\yguatemala\s*$' THEN 'Guatemala'
      WHEN cs.coffee_name ~* '\yhonduras\s*$'  THEN 'Honduras'
      WHEN cs.coffee_name ~* '\ymexico\s*$'    THEN 'Mexico'
      ELSE NULL
    END AS country
  FROM coffee_source cs
  WHERE cs.country_of_origin IS NULL
) matched
WHERE coffee_source.coffee_source_id = matched.coffee_source_id
  AND matched.country IS NOT NULL;

-- ── Pass 6: Expanded region detection ──────────────────────────────────
-- Re-run region matching with a fuller list of regions per country. Same
-- DISTINCT ON (longest match wins) pattern as 20260502000007.
WITH region_candidates (country, region) AS (VALUES
  -- Honduras
  ('Honduras', 'Siguatepeque'),
  -- Nicaragua
  ('Nicaragua', 'Las Segovias'),
  ('Nicaragua', 'Nueva Segovia'),
  -- Peru
  ('Peru', 'Cajamarca'),
  ('Peru', 'Amazonas'),
  ('Peru', 'San Martín'),
  ('Peru', 'San Martin'),
  ('Peru', 'Junín'),
  ('Peru', 'Junin'),
  ('Peru', 'Cusco'),
  ('Peru', 'Puno'),
  -- PNG
  ('Papua New Guinea', 'Highlands'),
  ('Papua New Guinea', 'Eastern Highlands'),
  ('Papua New Guinea', 'Western Highlands'),
  ('Papua New Guinea', 'Jiwaka'),
  ('Papua New Guinea', 'Chimbu'),
  ('Papua New Guinea', 'Sianè'),
  ('Papua New Guinea', 'Siane'),
  -- Indonesia (sub-regions within Sulawesi/Bali/etc.)
  ('Indonesia', 'Toraja'),
  ('Indonesia', 'Kintamani'),
  ('Indonesia', 'Mandheling'),
  ('Indonesia', 'Lintong'),
  ('Indonesia', 'Bajawa'),
  ('Indonesia', 'Sapan Minanga'),
  -- Panama (Highlands is altitude-class but commonly named as region)
  ('Panama', 'Boquete'),
  ('Panama', 'Volcán'),
  ('Panama', 'Volcan'),
  ('Panama', 'Highlands'),
  -- El Salvador additions
  ('El Salvador', 'Alotepec-Metapán'),
  ('El Salvador', 'Bálsamo-Quezaltepec'),
  ('El Salvador', 'Tecapa-Chinameca')
)
UPDATE coffee_source cs
SET region = best.region
FROM (
  SELECT DISTINCT ON (cs2.coffee_source_id)
    cs2.coffee_source_id, rc.region
  FROM coffee_source cs2
  JOIN region_candidates rc ON cs2.country_of_origin = rc.country
  WHERE cs2.coffee_name ILIKE '%' || rc.region || '%'
    AND (cs2.region IS NULL OR cs2.region = '')
  ORDER BY cs2.coffee_source_id, length(rc.region) DESC
) best
WHERE cs.coffee_source_id = best.coffee_source_id
  AND (cs.region IS NULL OR cs.region = '');

-- ── Pass 7: Process detection ─────────────────────────────────────────
-- Common processing methods that appear in legacy names. Only sets
-- process when currently NULL — never overwrites.
UPDATE coffee_source SET process = 'Wet Hulled'
WHERE (process IS NULL OR process = '')
  AND coffee_name ~* 'wet\s+hulled';

UPDATE coffee_source SET process = 'Honey'
WHERE (process IS NULL OR process = '')
  AND coffee_name ~* '\yhoney\y';

UPDATE coffee_source SET process = 'Swiss Water Decaf'
WHERE (process IS NULL OR process = '')
  AND (coffee_name ~* 'swiss\s+water' OR coffee_name ~* 'royal\s+select\s+water');

UPDATE coffee_source SET process = 'EA Decaf'
WHERE (process IS NULL OR process = '')
  AND coffee_name ~* '\yea\s+(natural\s+)?process';

-- ── Pass 8: Cert detection ────────────────────────────────────────────
-- Append known cert tokens to the certifications array. Use array_cat
-- + DISTINCT to avoid duplicates if the cert is already present.
--
-- FT-USA / FT USA / Fair Trade USA → 'Fair Trade USA'
UPDATE coffee_source
SET certifications = (
  SELECT ARRAY(SELECT DISTINCT unnest(certifications || ARRAY['Fair Trade USA']))
)
WHERE coffee_name ~* '\yft[-\s]?usa\y'
  AND NOT ('Fair Trade USA' = ANY(certifications));

-- FT-FLO / Fairtrade International → 'Fairtrade International (FLO)'
UPDATE coffee_source
SET certifications = (
  SELECT ARRAY(SELECT DISTINCT unnest(certifications || ARRAY['Fairtrade International (FLO)']))
)
WHERE coffee_name ~* '\yft[-\s]?flo\y'
  AND NOT ('Fairtrade International (FLO)' = ANY(certifications));

-- ORGANIC (standalone word) → 'USDA Organic' (most common in US market)
UPDATE coffee_source
SET certifications = (
  SELECT ARRAY(SELECT DISTINCT unnest(certifications || ARRAY['USDA Organic']))
)
WHERE coffee_name ~* '\yorganic\y'
  AND NOT ('USDA Organic' = ANY(certifications))
  AND NOT ('EU Organic' = ANY(certifications))
  AND NOT ('JAS Organic' = ANY(certifications));

-- RFA → 'Rainforest Alliance'
UPDATE coffee_source
SET certifications = (
  SELECT ARRAY(SELECT DISTINCT unnest(certifications || ARRAY['Rainforest Alliance']))
)
WHERE coffee_name ~* '\yrfa\y'
  AND NOT ('Rainforest Alliance' = ANY(certifications));

-- ── Final pass: recompose grade_label ─────────────────────────────────
-- Some rows that just got country/region set may now compose differently.
-- Same composer as 20260502000005/006.
UPDATE coffee_source SET grade_label = NULLIF(TRIM(BOTH ' ' FROM concat_ws(' ',
  grade_quality,
  grade_classification,
  grade_screen,
  grade_prep,
  CASE WHEN is_peaberry THEN 'Peaberry' ELSE NULL END
)), '');

-- Sanity report.
DO $$
DECLARE
  total int;
  with_country int;
  with_region int;
  no_country int;
BEGIN
  SELECT COUNT(*) INTO total FROM coffee_source;
  SELECT COUNT(*) INTO with_country FROM coffee_source WHERE country_of_origin IS NOT NULL;
  SELECT COUNT(*) INTO with_region FROM coffee_source WHERE region IS NOT NULL AND region <> '';
  SELECT COUNT(*) INTO no_country FROM coffee_source WHERE country_of_origin IS NULL;
  RAISE NOTICE 'coffee_source after aggressive backfill: % total, % with country, % with region, % still missing country',
    total, with_country, with_region, no_country;
END $$;

COMMIT;
