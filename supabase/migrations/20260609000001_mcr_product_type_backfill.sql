-- Backfill product_type for Maui Coffee Roasters (9ShiyDAXhV) products
-- All 379 products were imported with product_type = NULL, which causes
-- .neq('product_type', 'Merged') queries to exclude them (NULL != x is NULL in Postgres).
--
-- Mapping based on channel + size:
--   retail channel                     → Retail DTC
--   wholesale channel + 5lbs size      → Wholesale Bulk
--   wholesale channel + other sizes    → Wholesale Retail

SET LOCAL app.skip_audit = 'true';

UPDATE products
SET product_type = 'd3463359-eb50-4277-acaa-bedadd4dc211'  -- Retail DTC
WHERE company_id = '9ShiyDAXhV'
  AND product_type IS NULL
  AND channel = '87f69426-eb0f-4b67-a160-62c8be988323';    -- retail

UPDATE products
SET product_type = 'a0164cf0-de4c-4993-8e32-2da1287eb67a'  -- Wholesale Bulk
WHERE company_id = '9ShiyDAXhV'
  AND product_type IS NULL
  AND channel = '6e6f4b92-8d17-4858-913a-b38b85b178a6'    -- wholesale
  AND size = '34e787be';                                    -- 5lbs

UPDATE products
SET product_type = '734e6537-0a0b-4248-8720-56768d4e9234'  -- Wholesale Retail
WHERE company_id = '9ShiyDAXhV'
  AND product_type IS NULL
  AND channel = '6e6f4b92-8d17-4858-913a-b38b85b178a6'    -- wholesale
  AND size != '34e787be';                                   -- not 5lbs
