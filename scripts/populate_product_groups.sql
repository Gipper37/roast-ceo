-- populate_product_groups.sql
-- Back-fills product_groups + sets group_id / channel / prep_type on existing products.
-- Safe to run multiple times (idempotent via ON CONFLICT DO NOTHING / WHERE group_id IS NULL).
--
-- Review the derived names below before running:
--   SELECT * FROM _pg_staging ORDER BY derived_name, channel;
--
-- Run:
--   PGPASSWORD='SDH-h3FNHXSrxj-' psql "postgresql://postgres@db.pwpslalerytymorcodlv.supabase.co:5432/postgres" -f populate_product_groups.sql

BEGIN;

-- ── Step 1: Build staging table with derived group names ──────────────────

DROP TABLE IF EXISTS _pg_staging;

CREATE TEMP TABLE _pg_staging AS
WITH stripped AS (
  SELECT
    product_id,
    product_name,
    product_type,
    company_id,
    facility_id,
    -- 1. strip channel suffix
    CASE
      WHEN product_name LIKE '% - DTC' THEN rtrim(left(product_name, length(product_name) - 6))
      WHEN product_name LIKE '% - WS'  THEN rtrim(left(product_name, length(product_name) - 5))
      ELSE product_name
    END AS name_no_channel,
    -- channel
    CASE product_type
      WHEN 'Retail DTC'        THEN 'retail'
      WHEN 'Wholesale Retail'  THEN 'wholesale'
      WHEN 'Wholesale Bulk'    THEN 'wholesale'
      ELSE NULL
    END AS channel
  FROM products
  WHERE product_type NOT IN ('Merged', 'Sample')
),
size_stripped AS (
  SELECT
    product_id,
    product_name,
    product_type,
    company_id,
    facility_id,
    channel,
    -- 2. strip trailing size labels (ordered longest-first to avoid partial matches)
    trim(
      regexp_replace(
        name_no_channel,
        E'\\s+(5lbs|5lb|12oz|8oz|100G|2LBS|4\\.5lbs|4\\.5lb)\\s*$',
        '',
        'i'
      )
    ) AS derived_name,
    -- 3. detect prep type from name
    CASE
      WHEN name_no_channel ~* '\\bDrip\\b'       THEN 'Drip'
      WHEN name_no_channel ~* '\\bGround\\b'      THEN 'Ground'
      WHEN name_no_channel ~* '\\bWhole\\s*Bean\\b' THEN 'Whole Bean'
      ELSE NULL
    END AS prep_type
  FROM stripped
)
SELECT * FROM size_stripped;

-- Preview (comment out after review)
-- SELECT derived_name, channel, product_name, prep_type FROM _pg_staging ORDER BY derived_name, channel;

-- ── Step 2: Insert product_groups (one per distinct derived_name + company + facility) ──

INSERT INTO product_groups (group_name, company_id, facility_id)
SELECT DISTINCT
  derived_name,
  company_id,
  facility_id
FROM _pg_staging
WHERE derived_name IS NOT NULL
  AND derived_name <> ''
ON CONFLICT DO NOTHING;

-- ── Step 3: Update products with group_id + channel + prep_type ───────────

UPDATE products p
SET
  group_id  = pg.group_id,
  channel   = s.channel,
  prep_type = s.prep_type
FROM _pg_staging s
JOIN product_groups pg
  ON  pg.group_name  = s.derived_name
  AND pg.company_id  IS NOT DISTINCT FROM s.company_id
  AND pg.facility_id IS NOT DISTINCT FROM s.facility_id
WHERE p.product_id = s.product_id
  AND p.group_id IS NULL;   -- idempotent: skip already-assigned rows

-- ── Step 4: Verification ─────────────────────────────────────────────────

DO $$
DECLARE
  total_active      int;
  mapped            int;
  unmapped          int;
  group_count       int;
BEGIN
  SELECT COUNT(*) INTO total_active  FROM products WHERE product_type NOT IN ('Merged', 'Sample') AND is_active = true;
  SELECT COUNT(*) INTO mapped        FROM products WHERE group_id IS NOT NULL;
  SELECT COUNT(*) INTO unmapped      FROM products WHERE group_id IS NULL AND product_type NOT IN ('Merged', 'Sample') AND is_active = true;
  SELECT COUNT(*) INTO group_count   FROM product_groups;

  RAISE NOTICE 'product_groups created: %', group_count;
  RAISE NOTICE 'active products mapped:  %/%', mapped, total_active;
  RAISE NOTICE 'active products unmapped: %', unmapped;
END;
$$;

-- Show any unmapped active products for review
SELECT product_id, product_name, product_type
FROM products
WHERE group_id IS NULL
  AND product_type NOT IN ('Merged', 'Sample')
  AND is_active = true
ORDER BY product_name;

COMMIT;
