-- Add Bag (BOM), Label (BOM), Other (BOM) as global consumable type subtypes.
-- These split the existing 'product' type into more specific categories
-- so the inventory page can filter by packaging type.
--
-- Backfill logic:
--   existing 'global_consumable_type_product' items are re-categorised by name:
--     • contains "Label" (case-insensitive)           → Label (BOM)
--     • contains "Bag" (not "Label")                  → Bag (BOM)
--     • tin ties, strip labels, clips                 → Bag (BOM) accessories
--     • flavors / ingredients (HAZELNUT, LAVENDER …)  → Other (BOM)
--     • anything else still 'product'                 → Bag (BOM) as safe default
--   Operational items are untouched.

-- 1. Insert the three new global types
INSERT INTO public.consumable_type (consumable_type_id, consumable_type, company_id)
VALUES
  ('global_consumable_type_bag',       'Bag (BOM)',   NULL),
  ('global_consumable_type_label',     'Label (BOM)', NULL),
  ('global_consumable_type_other_bom', 'Other (BOM)', NULL)
ON CONFLICT (consumable_type_id) DO NOTHING;

-- 2. Backfill: Label (BOM) — name contains "Label" or ends in "Label"
UPDATE public.consumable_inventory
SET consumable_type = 'global_consumable_type_label'
WHERE consumable_type = 'global_consumable_type_product'
  AND (
    consumable_inventory_item ILIKE '%label%'
    OR consumable_inventory_item ILIKE '%strip%'
    OR consumable_inventory_item ILIKE '%oval%'
  );

-- 3. Backfill: Other (BOM) — flavor/ingredient items
UPDATE public.consumable_inventory
SET consumable_type = 'global_consumable_type_other_bom'
WHERE consumable_type = 'global_consumable_type_product'
  AND (
    consumable_inventory_item ILIKE '%hazelnut%'
    OR consumable_inventory_item ILIKE '%macadamia%'
    OR consumable_inventory_item ILIKE '%lavender%'
    OR consumable_inventory_item ILIKE '%vanilla%'
    OR consumable_inventory_item ILIKE '%chocolate%'
    OR consumable_inventory_item ILIKE '%flavor%'
    OR consumable_inventory_item ILIKE '%flavour%'
    OR consumable_inventory_item ILIKE '%coconut%'
    OR consumable_inventory_item ILIKE '%raspberry%'
    OR consumable_inventory_item ILIKE '%coffee back%'
    OR consumable_inventory_item ILIKE '%coffee front%'
  );

-- 4. Backfill: Bag (BOM) — everything remaining under 'product' (bags, tin ties, accessories)
UPDATE public.consumable_inventory
SET consumable_type = 'global_consumable_type_bag'
WHERE consumable_type = 'global_consumable_type_product';
