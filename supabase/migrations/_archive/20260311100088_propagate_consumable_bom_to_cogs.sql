-- Migration 00088: Propagate product_consumables changes to product COGS
--
-- Bug: Adding, editing, or removing a row in product_consumables did NOT
--      trigger a COGS recalculation on the parent product. total_unit_cogs
--      was silently stale whenever the BOM changed.
--
-- Fix: AFTER trigger on product_consumables that touches the parent products row,
--      which fires trg_update_product_cogs (BEFORE UPDATE on products).
--
-- Mirrors the coffee propagation pattern (trg_propagate_coffee_cost).

CREATE OR REPLACE FUNCTION public.propagate_consumable_bom_to_product()
RETURNS trigger
LANGUAGE plpgsql
AS $$
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
    UPDATE public.products
    SET updated_at = now()
    WHERE product_id = v_product_id;

    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_propagate_consumable_bom
    AFTER INSERT OR UPDATE OR DELETE ON public.product_consumables
    FOR EACH ROW EXECUTE FUNCTION public.propagate_consumable_bom_to_product();
