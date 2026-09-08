-- ============================================================================
-- MCR: rename the 36 "srm <Flavor>" syrup PRODUCTS to match the "Monin <Flavor>"
-- distribution consumable each one is cost-linked to (products.source_consumable_id
-- -> consumable_inventory). Company: Maui Coffee Roasters (9ShiyDAXhV)
--
-- Context: these are SELLABLE products (product_type=consumable) the py-migration
-- created from QB syrup sales lines, with QB's "srm" shorthand left on the name.
-- They are REAL + SOLD (1,699 order lines / 583 orders reference them by
-- product_id, so the rename does NOT touch order history) — and every one already
-- points at its matching "Monin …" consumable in the Inventory→Consumables tab.
-- Aligning the product name to that consumable makes the product dropdowns show
-- the same names you see in inventory.
--
-- product_name is built by build_product_name from group_name (these have a group,
-- no size/channel), so we rename the GROUP to the consumable name, then re-touch
-- the product to rebuild product_name.
--
-- ⚠️  PROD DATA CHANGE — run in the transaction, review the before/after, COMMIT
--     (or ROLLBACK). All 36 are verified linked (source_consumable_id NOT NULL).
-- ============================================================================

BEGIN;

-- 1. Rename each srm product's GROUP to its linked consumable's name.
UPDATE public.product_groups pg
   SET group_name = ci.consumable_inventory_item,
       updated_at = now()
  FROM public.products p
  JOIN public.consumable_inventory ci ON ci.consumable_inventory_id = p.source_consumable_id
 WHERE p.group_id = pg.group_id
   AND p.company_id = '9ShiyDAXhV'
   AND p.product_name ~* '^srm\s'
   AND ci.consumable_inventory_item IS NOT NULL;

-- 2. Re-touch the products so build_product_name rebuilds product_name from the
--    renamed group (trigger fires on UPDATE; group_id set + no size/channel =>
--    product_name := group_name).
UPDATE public.products
   SET updated_at = now()
 WHERE company_id = '9ShiyDAXhV'
   AND product_name ~* '^srm\s';

-- ---- VERIFY (review before COMMIT) ----------------------------------------
-- Expect product_name == the linked consumable name for all 36.
SELECT p.product_name, ci.consumable_inventory_item,
       (p.product_name = ci.consumable_inventory_item) AS matched
  FROM public.products p
  JOIN public.consumable_inventory ci ON ci.consumable_inventory_id = p.source_consumable_id
 WHERE p.company_id = '9ShiyDAXhV'
   AND ci.consumable_inventory_item LIKE 'Monin%'
 ORDER BY p.product_name;

-- Expect 0:
SELECT count(*) AS still_srm FROM public.products
 WHERE company_id = '9ShiyDAXhV' AND product_name ~* '^srm\s';

COMMIT;
