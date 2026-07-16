-- ============================================================================
-- MCR: rename the resold products' PRODUCT (product_groups) to their consumable
-- name. Company 9ShiyDAXhV. product_groups IS the product; its group_name is the
-- customer-facing product name (invoices/shop/pickers prefer it). P0 renamed the
-- VARIANTS (products.product_name) but left the products (groups) as "srm"/"team".
-- This finishes the job. RUN AFTER migration 20260716000001.
--
-- ⚠️ PROD DATA CHANGE — run in the transaction, review verify, COMMIT.
-- ============================================================================

BEGIN;

UPDATE public.product_groups pg
   SET group_name = ci.consumable_inventory_item,
       updated_at = now()
  FROM public.products p
  JOIN public.consumable_inventory ci ON ci.consumable_inventory_id = p.source_consumable_id
 WHERE p.group_id = pg.group_id
   AND p.company_id = '9ShiyDAXhV'
   AND p.source_consumable_id IS NOT NULL
   AND p.merge_into_id IS NULL
   AND pg.group_name IS DISTINCT FROM ci.consumable_inventory_item;

-- ---- VERIFY (review before COMMIT) ----------------------------------------
-- Expect product (group) name == variant name == consumable name for all resold.
SELECT pg.group_name AS product, p.product_name AS variant, ci.consumable_inventory_item AS consumable,
       (pg.group_name = ci.consumable_inventory_item AND p.product_name = ci.consumable_inventory_item) AS ok
  FROM public.products p
  JOIN public.product_groups pg ON pg.group_id = p.group_id
  JOIN public.consumable_inventory ci ON ci.consumable_inventory_id = p.source_consumable_id
 WHERE p.company_id = '9ShiyDAXhV' AND p.source_consumable_id IS NOT NULL AND p.merge_into_id IS NULL
 ORDER BY pg.group_name;

-- Expect 0 groups still "srm"/"team"/"flv"-prefixed among resold products.
SELECT count(*) AS still_prefixed
  FROM public.product_groups pg
  JOIN public.products p ON p.group_id = pg.group_id
 WHERE p.company_id='9ShiyDAXhV' AND p.source_consumable_id IS NOT NULL AND p.merge_into_id IS NULL
   AND pg.group_name ~* '^(srm|team|flv)\s';

COMMIT;
