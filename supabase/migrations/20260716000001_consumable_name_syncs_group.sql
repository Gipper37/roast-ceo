-- Fix consumable→product name propagation to target the PRODUCT (product_groups),
-- not just the variant (products row).
--
-- MODEL: product_groups IS the product (its group_name is the customer-facing
-- product name — shown on invoices/shop/pickers). products rows are VARIANTS
-- (size × channel). A resold distribution consumable links a variant to its
-- consumable_inventory stock via products.source_consumable_id.
--
-- P0 (20260715000001) propagated a consumable rename to products.product_name
-- (the variant) but left the product_groups.group_name (THE product) stale — so
-- "srm"/"team" names still surfaced. Now the trigger renames BOTH the product
-- (group) and its variant(s). Resold consumables are unsized (one variant, no
-- size/channel → variant name = product name), so a flat rename is correct here.
-- The build_product_name guard (source_consumable_id → keep name) stays, so a
-- later group/size edit won't re-derive over the propagated name.

CREATE OR REPLACE FUNCTION public.propagate_consumable_name_to_products()
  RETURNS trigger
  LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.consumable_inventory_item IS DISTINCT FROM OLD.consumable_inventory_item THEN
    -- Rename the PRODUCT (the product_group) of every variant linked to this consumable.
    UPDATE public.product_groups pg
       SET group_name = NEW.consumable_inventory_item,
           updated_at = now()
      FROM public.products p
     WHERE p.group_id = pg.group_id
       AND p.source_consumable_id = NEW.consumable_inventory_id
       AND pg.group_name IS DISTINCT FROM NEW.consumable_inventory_item;

    -- Rename the variant(s) too (resold = unsized: variant name = product name;
    -- leaves shop_display_name untouched so a customer-facing override survives).
    UPDATE public.products
       SET product_name = NEW.consumable_inventory_item,
           updated_at   = now()
     WHERE source_consumable_id = NEW.consumable_inventory_id
       AND product_name IS DISTINCT FROM NEW.consumable_inventory_item;
  END IF;
  RETURN NULL; -- AFTER trigger
END;
$function$;

NOTIFY pgrst, 'reload schema';
