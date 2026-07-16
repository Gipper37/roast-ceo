-- ============================================================================
-- MCR resold-consumable cleanup (unification P0 data step). Company 9ShiyDAXhV.
-- RUN ONCE, AFTER migration 20260715000001 (needs the build_product_name guard so
-- the direct product_name rename sticks, and the propagation trigger to keep it).
--
-- (A) Merge the Basil duplicate: "FLV Basil Concentrated" -> "srm Basil" (both
--     point at consumable "Monin Basil Concentrate Flavor"; QB listed it twice).
--     srm Basil (3 lines) survives; FLV (2 lines) merges via merge_into_id (the
--     trg_merge_product trigger repoints its order lines). => source_consumable_id
--     becomes truly 1:1.
-- (B) Rename every resold product to its linked consumable's name (kills "srm"/
--     "FLV" in every product dropdown). History-safe: order_details point at
--     product_id, unchanged.
--
-- ⚠️ PROD DATA CHANGE — run in the transaction, review the verify output, COMMIT.
-- ============================================================================

BEGIN;

-- (A) Merge FLV Basil (loser) into srm Basil (survivor).
UPDATE public.products
   SET merge_into_id = 'mcrimp-prod-d5ead5cc3173ceed'  -- srm Basil (survivor)
 WHERE product_id = 'mcrimp-prod-0326ff1c296899fe'      -- FLV Basil Concentrated (loser)
   AND company_id = '9ShiyDAXhV';

-- (B) Rename every ACTIVE resold product to its consumable's name. Skip the just-
--     merged loser (product_type flips to 'Merged'). build_product_name won't fire
--     on a product_name-only update, and its new guard keeps it from re-deriving.
UPDATE public.products p
   SET product_name = ci.consumable_inventory_item,
       updated_at   = now()
  FROM public.consumable_inventory ci
 WHERE ci.consumable_inventory_id = p.source_consumable_id
   AND p.company_id = '9ShiyDAXhV'
   AND p.source_consumable_id IS NOT NULL
   AND COALESCE(p.product_type, '') <> 'Merged'
   AND p.merge_into_id IS NULL
   AND p.product_name IS DISTINCT FROM ci.consumable_inventory_item;

-- ---- VERIFY (review before COMMIT) ----------------------------------------
-- Every live resold product's name == its consumable's name:
SELECT p.product_name, ci.consumable_inventory_item,
       (p.product_name = ci.consumable_inventory_item) AS matched
  FROM public.products p
  JOIN public.consumable_inventory ci ON ci.consumable_inventory_id = p.source_consumable_id
 WHERE p.company_id = '9ShiyDAXhV' AND p.merge_into_id IS NULL AND COALESCE(p.product_type,'') <> 'Merged'
 ORDER BY p.product_name;

-- Expect 0 srm/FLV left on live products:
SELECT count(*) AS still_prefixed
  FROM public.products
 WHERE company_id = '9ShiyDAXhV' AND merge_into_id IS NULL
   AND (product_name ~* '^(srm|flv)\s');

-- Basil now 1:1 (exactly one live product on that consumable):
SELECT count(*) AS live_basil_products
  FROM public.products
 WHERE company_id = '9ShiyDAXhV' AND merge_into_id IS NULL
   AND source_consumable_id = (SELECT consumable_inventory_id FROM public.consumable_inventory
                                WHERE company_id='9ShiyDAXhV' AND consumable_inventory_item='Monin Basil Concentrate Flavor');

COMMIT;
