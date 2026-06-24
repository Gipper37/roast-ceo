-- MCR FLAVOR-GROUP CONSOLIDATION (company 9ShiyDAXhV = Maui Coffee Roasters ONLY).
-- Operator spec: memory/project_mcr_group_consolidation.md. Social Hour
-- (R7CbqHmA1j, 752af3ed-4) is NEVER referenced here.
--
-- Model: a coffee's STOCK HOME = its flavor group (so blends reorder at the flavor
-- level). Kept single-origin groups (Costa Rica, Colombia, Guatemala) hold those
-- same coffees via allowed_origin_ids so single-origin roasts still work (borrow).
-- Moving origin_id / cip.origin / coffee_item fires no recompute, so remaining_lbs
-- is preserved; totals refreshed via recalculate_origin_total_stock (SUM).
--
-- Group ids:  Brazil orig_c655bcaf99a986b1 | Colombia orig_d393e3392710921a
--  CostaRica orig_d5456517bf131c45 | ElSalvador orig_28d3a9afb33fb94a
--  Guatemala orig_b3890561c1c3ba25 | Honduras orig_d669c72ce18c7651
--  Mexico orig_0d75323d13d7e2fe | Nicaragua orig_bd7157c2ff0a76b3
--  Peru orig_5e487c2d0035d0d4 | PNG orig_93f7f73f959de942
--  NEW: Chocolate orig_mcr_chocolate | Fruit orig_mcr_fruit | Organic orig_mcr_organic

-- ── 0. create the 3 new flavor groups (Brazil already exists) ──
INSERT INTO public.coffee_inventory (origin_id, origin, company_id, facility_id, is_active, restock_category_id, bag_size, created_at)
VALUES
 ('orig_mcr_chocolate','Chocolate','9ShiyDAXhV','5cc581b9-2803-42c2-98de-0ba16ae42f8e',true,'9d5a9ee1-9b35-47b5-900f-4a77f771c85e','132',now()),
 ('orig_mcr_fruit','Fruit','9ShiyDAXhV','5cc581b9-2803-42c2-98de-0ba16ae42f8e',true,'9d5a9ee1-9b35-47b5-900f-4a77f771c85e','132',now()),
 ('orig_mcr_organic','Organic','9ShiyDAXhV','5cc581b9-2803-42c2-98de-0ba16ae42f8e',true,'9d5a9ee1-9b35-47b5-900f-4a77f771c85e','132',now())
ON CONFLICT (origin_id) DO NOTHING;

-- ── 1. SOURCE + LOT moves (each: move coffee_source.origin_id [+allowed], then its lots) ──

-- Mexico Veracruz HG (non-organic, non-decaf) -> Brazil
WITH m AS (UPDATE public.coffee_source SET origin_id='orig_c655bcaf99a986b1'
  WHERE company_id='9ShiyDAXhV' AND origin_id='orig_0d75323d13d7e2fe'
    AND NOT 'Organic'=ANY(COALESCE(certifications,'{}')) AND COALESCE(is_decaf,false)=false
  RETURNING coffee_source_id)
UPDATE public.coffee_inventory_purchased SET origin='orig_c655bcaf99a986b1' WHERE coffee_source_id IN (SELECT coffee_source_id FROM m);

-- Mexico HG Organic -> Organic
WITH m AS (UPDATE public.coffee_source SET origin_id='orig_mcr_organic'
  WHERE company_id='9ShiyDAXhV' AND origin_id='orig_0d75323d13d7e2fe' AND 'Organic'=ANY(COALESCE(certifications,'{}'))
  RETURNING coffee_source_id)
UPDATE public.coffee_inventory_purchased SET origin='orig_mcr_organic' WHERE coffee_source_id IN (SELECT coffee_source_id FROM m);

-- Colombia non-organic, non-Gesha -> Chocolate (+ allowed Colombia)
WITH m AS (UPDATE public.coffee_source
    SET origin_id='orig_mcr_chocolate',
        allowed_origin_ids=ARRAY(SELECT DISTINCT unnest(COALESCE(allowed_origin_ids,'{}'::text[])||ARRAY['orig_d393e3392710921a']))
  WHERE company_id='9ShiyDAXhV' AND origin_id='orig_d393e3392710921a'
    AND NOT 'Organic'=ANY(COALESCE(certifications,'{}')) AND coffee_name NOT ILIKE '%Gesha%'
  RETURNING coffee_source_id)
UPDATE public.coffee_inventory_purchased SET origin='orig_mcr_chocolate' WHERE coffee_source_id IN (SELECT coffee_source_id FROM m);

-- Colombia organic -> Organic (+ allowed Colombia)
WITH m AS (UPDATE public.coffee_source
    SET origin_id='orig_mcr_organic',
        allowed_origin_ids=ARRAY(SELECT DISTINCT unnest(COALESCE(allowed_origin_ids,'{}'::text[])||ARRAY['orig_d393e3392710921a']))
  WHERE company_id='9ShiyDAXhV' AND origin_id='orig_d393e3392710921a' AND 'Organic'=ANY(COALESCE(certifications,'{}'))
  RETURNING coffee_source_id)
UPDATE public.coffee_inventory_purchased SET origin='orig_mcr_organic' WHERE coffee_source_id IN (SELECT coffee_source_id FROM m);

-- Honduras non-organic -> Chocolate
WITH m AS (UPDATE public.coffee_source SET origin_id='orig_mcr_chocolate'
  WHERE company_id='9ShiyDAXhV' AND origin_id='orig_d669c72ce18c7651' AND NOT 'Organic'=ANY(COALESCE(certifications,'{}'))
  RETURNING coffee_source_id)
UPDATE public.coffee_inventory_purchased SET origin='orig_mcr_chocolate' WHERE coffee_source_id IN (SELECT coffee_source_id FROM m);

-- Honduras organic -> Organic
WITH m AS (UPDATE public.coffee_source SET origin_id='orig_mcr_organic'
  WHERE company_id='9ShiyDAXhV' AND origin_id='orig_d669c72ce18c7651' AND 'Organic'=ANY(COALESCE(certifications,'{}'))
  RETURNING coffee_source_id)
UPDATE public.coffee_inventory_purchased SET origin='orig_mcr_organic' WHERE coffee_source_id IN (SELECT coffee_source_id FROM m);

-- Peru non-organic (Vida Alta) -> Chocolate
WITH m AS (UPDATE public.coffee_source SET origin_id='orig_mcr_chocolate'
  WHERE company_id='9ShiyDAXhV' AND origin_id='orig_5e487c2d0035d0d4' AND NOT 'Organic'=ANY(COALESCE(certifications,'{}'))
  RETURNING coffee_source_id)
UPDATE public.coffee_inventory_purchased SET origin='orig_mcr_chocolate' WHERE coffee_source_id IN (SELECT coffee_source_id FROM m);

-- Peru organic -> Organic
WITH m AS (UPDATE public.coffee_source SET origin_id='orig_mcr_organic'
  WHERE company_id='9ShiyDAXhV' AND origin_id='orig_5e487c2d0035d0d4' AND 'Organic'=ANY(COALESCE(certifications,'{}'))
  RETURNING coffee_source_id)
UPDATE public.coffee_inventory_purchased SET origin='orig_mcr_organic' WHERE coffee_source_id IN (SELECT coffee_source_id FROM m);

-- El Salvador (all) -> Fruit
WITH m AS (UPDATE public.coffee_source SET origin_id='orig_mcr_fruit'
  WHERE company_id='9ShiyDAXhV' AND origin_id='orig_28d3a9afb33fb94a'
  RETURNING coffee_source_id)
UPDATE public.coffee_inventory_purchased SET origin='orig_mcr_fruit' WHERE coffee_source_id IN (SELECT coffee_source_id FROM m);

-- Nicaragua non-organic -> Fruit
WITH m AS (UPDATE public.coffee_source SET origin_id='orig_mcr_fruit'
  WHERE company_id='9ShiyDAXhV' AND origin_id='orig_bd7157c2ff0a76b3' AND NOT 'Organic'=ANY(COALESCE(certifications,'{}'))
  RETURNING coffee_source_id)
UPDATE public.coffee_inventory_purchased SET origin='orig_mcr_fruit' WHERE coffee_source_id IN (SELECT coffee_source_id FROM m);

-- Nicaragua organic -> Organic
WITH m AS (UPDATE public.coffee_source SET origin_id='orig_mcr_organic'
  WHERE company_id='9ShiyDAXhV' AND origin_id='orig_bd7157c2ff0a76b3' AND 'Organic'=ANY(COALESCE(certifications,'{}'))
  RETURNING coffee_source_id)
UPDATE public.coffee_inventory_purchased SET origin='orig_mcr_organic' WHERE coffee_source_id IN (SELECT coffee_source_id FROM m);

-- Costa Rica -> Fruit (+ allowed Costa Rica)
WITH m AS (UPDATE public.coffee_source
    SET origin_id='orig_mcr_fruit',
        allowed_origin_ids=ARRAY(SELECT DISTINCT unnest(COALESCE(allowed_origin_ids,'{}'::text[])||ARRAY['orig_d5456517bf131c45']))
  WHERE company_id='9ShiyDAXhV' AND origin_id='orig_d5456517bf131c45'
  RETURNING coffee_source_id)
UPDATE public.coffee_inventory_purchased SET origin='orig_mcr_fruit' WHERE coffee_source_id IN (SELECT coffee_source_id FROM m);

-- Guatemala -> Fruit (+ allowed Guatemala)
WITH m AS (UPDATE public.coffee_source
    SET origin_id='orig_mcr_fruit',
        allowed_origin_ids=ARRAY(SELECT DISTINCT unnest(COALESCE(allowed_origin_ids,'{}'::text[])||ARRAY['orig_b3890561c1c3ba25']))
  WHERE company_id='9ShiyDAXhV' AND origin_id='orig_b3890561c1c3ba25'
  RETURNING coffee_source_id)
UPDATE public.coffee_inventory_purchased SET origin='orig_mcr_fruit' WHERE coffee_source_id IN (SELECT coffee_source_id FROM m);

-- PNG organic -> Organic (non-organic PNG + PNG Peaberry stay put)
WITH m AS (UPDATE public.coffee_source SET origin_id='orig_mcr_organic'
  WHERE company_id='9ShiyDAXhV' AND origin_id='orig_93f7f73f959de942' AND 'Organic'=ANY(COALESCE(certifications,'{}'))
  RETURNING coffee_source_id)
UPDATE public.coffee_inventory_purchased SET origin='orig_mcr_organic' WHERE coffee_source_id IN (SELECT coffee_source_id FROM m);

-- ── 2. RECIPE component repoints ──
-- Archived-group recipes: ALL refs move (group is going away)
UPDATE public.recipe_components SET coffee_item='orig_mcr_fruit'     WHERE coffee_item='orig_28d3a9afb33fb94a'; -- El Salvador
UPDATE public.recipe_components SET coffee_item='orig_mcr_chocolate' WHERE coffee_item='orig_d669c72ce18c7651'; -- Honduras
UPDATE public.recipe_components SET coffee_item='orig_mcr_fruit'     WHERE coffee_item='orig_bd7157c2ff0a76b3'; -- Nicaragua
UPDATE public.recipe_components SET coffee_item='orig_mcr_organic'   WHERE coffee_item='orig_5e487c2d0035d0d4'; -- Peru
UPDATE public.recipe_components SET coffee_item='orig_mcr_organic'   WHERE coffee_item='orig_0d75323d13d7e2fe'; -- Mexico
-- Kept-group recipes: only BLENDS move; single-origin recipes keep targeting the kept group
UPDATE public.recipe_components SET coffee_item='orig_mcr_chocolate' WHERE coffee_item='orig_d393e3392710921a' -- Colombia (blends only; NOT Colombian Dark)
  AND recipe_id IN ('rcp-mcr-espresso','rcp-mcr-french-roast','rcp-mcr-kona-bl-dk','rcp-mcr-kona-bl-lt','rcp-mcr-kona-bl-med','rcp-mcr-mama-s-espresso','rcp-mcr-mb-dk','rcp-mcr-mb-lt','rcp-mcr-nokaoi');
UPDATE public.recipe_components SET coffee_item='orig_mcr_fruit' WHERE coffee_item='orig_b3890561c1c3ba25' -- Guatemala (blends only; NOT SW Sup)
  AND recipe_id IN ('rcp-mcr-mama-s-maui-red','rcp-mcr-mcr-hi-blend');

-- ── 3. archive the now-empty origin groups ──
UPDATE public.coffee_inventory SET is_active=false
 WHERE company_id='9ShiyDAXhV'
   AND origin_id IN ('orig_0d75323d13d7e2fe','orig_28d3a9afb33fb94a','orig_d669c72ce18c7651','orig_bd7157c2ff0a76b3','orig_5e487c2d0035d0d4');

-- ── 4. refresh totals (SUM of lots) for every touched group ──
SELECT public.recalculate_origin_total_stock(g, '5cc581b9-2803-42c2-98de-0ba16ae42f8e')
FROM unnest(ARRAY[
  'orig_mcr_chocolate','orig_mcr_fruit','orig_mcr_organic','orig_c655bcaf99a986b1',
  'orig_d393e3392710921a','orig_d5456517bf131c45','orig_b3890561c1c3ba25',
  'orig_0d75323d13d7e2fe','orig_28d3a9afb33fb94a','orig_d669c72ce18c7651',
  'orig_bd7157c2ff0a76b3','orig_5e487c2d0035d0d4','orig_93f7f73f959de942'
]) AS g;
