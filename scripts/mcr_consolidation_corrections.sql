-- MCR consolidation corrections (company 9ShiyDAXhV = Maui Coffee Roasters).
-- Operator picks: latest Honduras shipment (Copán SHG) -> Brazil group;
-- latest Nicaragua shipment (Olomega SHG) -> Chocolate group. Plus re-home 5
-- source-less, 0-stock import-scrap lots stranded in archived groups.
-- (Recipes reference GROUPS, not sources, so these source moves orphan nothing.)

-- Honduras Copán SHG -> Brazil
WITH m AS (UPDATE public.coffee_source SET origin_id='orig_c655bcaf99a986b1'
  WHERE company_id='9ShiyDAXhV' AND coffee_name='Honduras Copán SHG'
  RETURNING coffee_source_id)
UPDATE public.coffee_inventory_purchased SET origin='orig_c655bcaf99a986b1' WHERE coffee_source_id IN (SELECT coffee_source_id FROM m);

-- Nicaragua Olomega SHG -> Chocolate
WITH m AS (UPDATE public.coffee_source SET origin_id='orig_mcr_chocolate'
  WHERE company_id='9ShiyDAXhV' AND coffee_name='Nicaragua Olomega SHG'
  RETURNING coffee_source_id)
UPDATE public.coffee_inventory_purchased SET origin='orig_mcr_chocolate' WHERE coffee_source_id IN (SELECT coffee_source_id FROM m);

-- 5 source-less, 0-stock dangling lots -> their group's flavor destination
UPDATE public.coffee_inventory_purchased SET origin='orig_c655bcaf99a986b1'
  WHERE origin_purchase_id IN ('mcr-cip-6134365-8e907e7f','mcr-cip-6120945-bd3cecdf'); -- Mexico -> Brazil
UPDATE public.coffee_inventory_purchased SET origin='orig_mcr_fruit'
  WHERE origin_purchase_id='mcr-cip-6131605-b503ddea'; -- Nicaragua -> Fruit
UPDATE public.coffee_inventory_purchased SET origin='orig_mcr_chocolate'
  WHERE origin_purchase_id IN ('mcr-cip-6134923-0f182c10','mcr-cip-6139141-ce51ceed'); -- Honduras -> Chocolate

-- refresh totals
SELECT public.recalculate_origin_total_stock(g,'5cc581b9-2803-42c2-98de-0ba16ae42f8e')
FROM unnest(ARRAY['orig_c655bcaf99a986b1','orig_mcr_chocolate','orig_mcr_fruit']) g;
