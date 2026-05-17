-- ============================================================================
-- Cleanup pass on coffee_source.certifications.
--
-- The aggressive backfill (20260502000008) added canonical cert tokens
-- (USDA Organic, Fair Trade USA, etc.) to rows whose coffee_name
-- mentioned those certs. But the legacy data had two problems:
--
--   1. Bare "Organic" token alongside the canonical "USDA Organic" —
--      duplicate, displays as "Organic, USDA Organic" in the title.
--
--   2. Single array elements with embedded commas — e.g.
--      `"Organic , Fair Trade"` got dumped in as ONE cert value rather
--      than being split. That's a data-shape bug, not a vocabulary bug.
--
-- This migration:
--   • Splits any cert array element containing ", " into separate values
--   • Maps non-canonical values to canonical ones:
--       "Organic" → "USDA Organic"
--       "Fair Trade" → "Fair Trade USA"
--       "Fairtrade" → "Fairtrade International (FLO)"
--   • Dedupes the resulting array so each cert appears at most once
--
-- After this, the cert picker chips will only show canonical tokens.
-- ============================================================================

BEGIN;

-- Helper function — splits multi-cert strings, normalizes to canonical
-- tokens, dedupes.
CREATE OR REPLACE FUNCTION pg_temp.normalize_certs(certs text[])
RETURNS text[] LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  raw text;
  part text;
  canonical text;
  result text[] := ARRAY[]::text[];
BEGIN
  FOREACH raw IN ARRAY certs LOOP
    -- Split each entry by ", " (with optional surrounding whitespace).
    -- Most arrays have one cert per element; split is a no-op then.
    FOREACH part IN ARRAY regexp_split_to_array(raw, '\s*,\s*') LOOP
      part := trim(part);
      IF part = '' THEN CONTINUE; END IF;

      -- Map common non-canonical to canonical token.
      canonical := CASE
        WHEN part ILIKE 'organic'                THEN 'USDA Organic'
        WHEN part ILIKE 'usda organic'           THEN 'USDA Organic'
        WHEN part ILIKE 'eu organic'             THEN 'EU Organic'
        WHEN part ILIKE 'jas organic'            THEN 'JAS Organic'
        WHEN part ILIKE 'fair trade'             THEN 'Fair Trade USA'
        WHEN part ILIKE 'ft usa' OR part ILIKE 'ft-usa' THEN 'Fair Trade USA'
        WHEN part ILIKE 'fair trade usa'         THEN 'Fair Trade USA'
        WHEN part ILIKE 'fairtrade'              THEN 'Fairtrade International (FLO)'
        WHEN part ILIKE 'fairtrade international%' THEN 'Fairtrade International (FLO)'
        WHEN part ILIKE 'flo'                    THEN 'Fairtrade International (FLO)'
        WHEN part ILIKE 'rainforest alliance'    THEN 'Rainforest Alliance'
        WHEN part ILIKE 'rfa'                    THEN 'Rainforest Alliance'
        WHEN part ILIKE 'utz%'                   THEN 'UTZ Certified'
        WHEN part ILIKE 'bird friendly%'         THEN 'Bird Friendly (SMBC)'
        WHEN part ILIKE 'smithsonian%'           THEN 'Smithsonian Bird Friendly'
        ELSE part  -- unknown token — keep as-is so we don't lose data
      END;

      -- Append only when not already in result (dedupe).
      IF NOT (canonical = ANY(result)) THEN
        result := result || canonical;
      END IF;
    END LOOP;
  END LOOP;

  RETURN result;
END $$;

-- Apply to every row that has at least one cert.
UPDATE coffee_source
SET certifications = pg_temp.normalize_certs(certifications)
WHERE array_length(certifications, 1) > 0;

DO $$
DECLARE
  rows_with_certs int;
  rows_with_organic int;
  rows_with_bare_organic int;
BEGIN
  SELECT COUNT(*) INTO rows_with_certs
    FROM coffee_source WHERE array_length(certifications, 1) > 0;
  SELECT COUNT(*) INTO rows_with_organic
    FROM coffee_source WHERE 'USDA Organic' = ANY(certifications);
  SELECT COUNT(*) INTO rows_with_bare_organic
    FROM coffee_source WHERE 'Organic' = ANY(certifications);
  RAISE NOTICE 'coffee_source after cert dedupe: % rows with certs, % with USDA Organic, % still bare "Organic"',
    rows_with_certs, rows_with_organic, rows_with_bare_organic;
END $$;

COMMIT;
