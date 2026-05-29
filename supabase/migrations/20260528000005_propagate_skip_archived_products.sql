-- Cost-propagation triggers must skip archived products
-- ────────────────────────────────────────────────────────────────────────
-- Bug: receiving a coffee shipment fired
--   shipment_received → coffee_inventory_purchased → trg_propagate_coffee_cost
-- which `UPDATE products SET updated_at = now()` over EVERY product on the
-- recipe — including archived ones. SHCR's tenant has 4 archived
-- DEAD/MERGED products with group_id = NULL (legacy data from before the
-- products_group_id_not_null CHECK landed). The UPDATE itself fired the
-- CHECK and rolled back the whole shipment confirm.
--
-- update_product_total_cogs() already short-circuits on is_active=false,
-- so touching archived products serves no purpose — they don't need a
-- cost recompute. Add `is_active = true` to the three propagate paths
-- (coffee cost, consumable cost, consumable BOM) so archived rows are
-- never UPDATEd in the first place. Net effect: same recompute behaviour
-- for live products, archived products left untouched (the right answer
-- regardless of the CHECK).
--
-- If an archived product is later restored, the next cost-relevant event
-- after restore will touch it normally — same as the existing
-- update_product_total_cogs short-circuit semantics.

CREATE OR REPLACE FUNCTION public.propagate_coffee_cost_change()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    -- 1. Performance Check
    IF NEW.latest_cost IS NOT DISTINCT FROM OLD.latest_cost THEN
        RETURN NEW;
    END IF;

    -- 2. "Touch" the Components
    -- We just update 'updated_at'. This is enough to fire the
    -- 'sync_recipe_component_costs' trigger, which will see the
    -- new inventory cost and recalculate the math automatically.
    UPDATE recipe_components rc
    SET updated_at = NOW()
    FROM roast_recipes rr
    WHERE rc.recipe_id = rr.recipe_id
      AND rc.coffee_item = NEW.origin_id
      AND rr.facility_id = NEW.facility_id;

    -- 3. Touch the Products (to sum up the new component costs)
    -- Skip archived products — they short-circuit in update_product_total_cogs
    -- anyway, AND legacy archived rows may have NULL group_id which would
    -- trip the products_group_id_not_null CHECK and roll back the shipment.
    UPDATE products p
    SET updated_at = NOW()
    FROM roast_recipes rr
    WHERE p.recipe_id = rr.recipe_id
      AND rr.facility_id = NEW.facility_id
      AND p.company_id = NEW.company_id
      AND p.is_active = true;

    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.propagate_consumable_cost_to_products()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    -- Only act when the unit cost actually changed
    IF OLD.last_cost_unit IS DISTINCT FROM NEW.last_cost_unit THEN
        UPDATE public.products p
        SET updated_at = now()
        FROM public.product_consumables pc
        WHERE pc.consumable_id = NEW.consumable_inventory_id
          AND pc.product_id    = p.product_id
          AND p.is_active      = true;  -- skip archived (see file header)
    END IF;

    RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.propagate_consumable_bom_to_product()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_product_id text;
BEGIN
    -- On DELETE, NEW is null — use OLD. Otherwise use NEW.
    IF TG_OP = 'DELETE' THEN
        v_product_id := OLD.product_id;
    ELSE
        v_product_id := NEW.product_id;
    END IF;

    -- Touch the parent product row. This fires trg_update_product_cogs
    -- (BEFORE UPDATE on products), which recalculates total_unit_cogs.
    -- Skip if the product is archived (see file header).
    UPDATE public.products
    SET updated_at = now()
    WHERE product_id = v_product_id
      AND is_active  = true;

    RETURN NULL;
END;
$function$;
