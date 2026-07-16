-- Consumable ↔ product name sync (unification P0 — mechanism only, no data change).
--
-- Root cause of the "srm" drift: a resold (Distribution) consumable is a products
-- row tied to a consumable_inventory row via products.source_consumable_id, but
-- renaming the consumable never propagated to the product name. This adds:
--   (1) products.shop_display_name — an OPTIONAL customer-facing override so the
--       wholesale shop / invoice can show a different name than the internal one.
--   (2) build_product_name skips resold rows — their name is NOT group-derived;
--       it follows the linked consumable (managed by the trigger below).
--   (3) a trigger so renaming a consumable propagates to its linked product(s).
-- Internal name = products.product_name (follows the consumable). Customer-facing
-- name = COALESCE(shop_display_name, product_name) (wired into shop/invoice in P1).

-- (1) Optional customer-facing display override.
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS shop_display_name text;

-- (2) Resold rows opt out of group-derived naming.
CREATE OR REPLACE FUNCTION public.build_product_name()
  RETURNS trigger
  LANGUAGE plpgsql
AS $function$
DECLARE
  v_group_name text;
  v_size_name  text;
  v_channel    text;
  v_parts      text[] := '{}';
BEGIN
  -- Resold consumable/equipment (source_consumable_id set): name follows the
  -- linked consumable and is kept in sync by propagate_consumable_name_to_products
  -- — do NOT group-derive it (that is exactly what produced the "srm" drift).
  IF NEW.source_consumable_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.group_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT group_name INTO v_group_name FROM public.product_groups WHERE group_id = NEW.group_id;
  IF NEW.size IS NOT NULL THEN
    SELECT size_name INTO v_size_name FROM public.size WHERE size_id = NEW.size;
  END IF;
  IF NEW.channel IS NOT NULL THEN
    SELECT initcap(replace(channel, '_', ' ')) INTO v_channel FROM public.channel WHERE channel_id = NEW.channel;
  END IF;

  IF v_group_name IS NOT NULL THEN v_parts := v_parts || v_group_name; END IF;
  IF v_size_name IS NOT NULL AND v_size_name != '' THEN v_parts := v_parts || v_size_name; END IF;
  IF v_channel  IS NOT NULL AND v_channel  != '' THEN v_parts := v_parts || v_channel;   END IF;

  NEW.product_name := array_to_string(v_parts, ' - ');
  RETURN NEW;
END;
$function$;

-- (3) Consumable rename → linked product internal name. (shop_display_name is left
--     alone so an explicit customer-facing override is never clobbered.)
CREATE OR REPLACE FUNCTION public.propagate_consumable_name_to_products()
  RETURNS trigger
  LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.consumable_inventory_item IS DISTINCT FROM OLD.consumable_inventory_item THEN
    UPDATE public.products
       SET product_name = NEW.consumable_inventory_item,
           updated_at   = now()
     WHERE source_consumable_id = NEW.consumable_inventory_id
       AND product_name IS DISTINCT FROM NEW.consumable_inventory_item;
  END IF;
  RETURN NULL; -- AFTER trigger
END;
$function$;

DROP TRIGGER IF EXISTS trg_propagate_consumable_name ON public.consumable_inventory;
CREATE TRIGGER trg_propagate_consumable_name
  AFTER UPDATE OF consumable_inventory_item ON public.consumable_inventory
  FOR EACH ROW EXECUTE FUNCTION public.propagate_consumable_name_to_products();

NOTIFY pgrst, 'reload schema';
