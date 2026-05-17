-- Migration 00089: Propagate consumable_inventory cost changes to product COGS
--
-- Bug: When consumable_inventory.last_cost_unit is updated (e.g. a new shipment
--      arrives with a different price), the products using that consumable did NOT
--      have their COGS recalculated. The stale cost sat in products.total_unit_cogs
--      until someone manually re-saved the product.
--
-- This is the consumable equivalent of trg_propagate_coffee_cost (which already
-- handles coffee cost changes propagating to products).
--
-- Fix: AFTER UPDATE OF last_cost_unit on consumable_inventory → touch all products
--      in product_consumables that reference that consumable → fires
--      trg_update_product_cogs on each product.
--
-- Also propagates when last_cost_unit changes on consumable_inventory, which
-- automatically clears those products from data_quality_issues once COGS is > 0.

CREATE OR REPLACE FUNCTION public.propagate_consumable_cost_to_products()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    -- Only act when the unit cost actually changed
    IF OLD.last_cost_unit IS DISTINCT FROM NEW.last_cost_unit THEN
        UPDATE public.products p
        SET updated_at = now()
        FROM public.product_consumables pc
        WHERE pc.consumable_id = NEW.consumable_inventory_id
          AND pc.product_id    = p.product_id;
    END IF;

    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_propagate_consumable_cost
    AFTER UPDATE OF last_cost_unit ON public.consumable_inventory
    FOR EACH ROW EXECUTE FUNCTION public.propagate_consumable_cost_to_products();
