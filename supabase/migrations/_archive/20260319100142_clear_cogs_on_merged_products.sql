-- Migration 00142: Null out COGS columns when product_type = 'Merged'
-- trg_update_product_cogs fires on every products UPDATE (including during merge),
-- so we short-circuit it for merged products instead of fighting the trigger.

CREATE OR REPLACE FUNCTION public.update_product_total_cogs()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_coffee_cost_total     numeric := 0;
    v_consumable_cost_total numeric := 0;
    v_weight                numeric;
BEGIN
    -- Short-circuit for merged products — clear all cost columns
    IF NEW.product_type = 'Merged' THEN
        NEW.total_coffee_cost     := NULL;
        NEW.total_consumable_cost := NULL;
        NEW.total_unit_cogs       := NULL;
        NEW.gross_profit_per_unit := NULL;
        NEW.cogs_pct              := NULL;
        NEW.margin_pct            := NULL;
        RETURN NEW;
    END IF;

    -- 0. Sync weight_lbs from size table
    SELECT s.weight INTO v_weight
    FROM public.size s
    WHERE s.size_id = NEW.size
    LIMIT 1;

    IF v_weight IS NOT NULL THEN
        NEW.weight_lbs := v_weight;
    END IF;

    -- A. Coffee Cost
    SELECT COALESCE(SUM(ci.latest_cost * rc.percentage), 0)
    INTO v_coffee_cost_total
    FROM public.recipe_components rc
    JOIN public.coffee_inventory ci ON rc.coffee_item = ci.origin_id
    WHERE rc.recipe_id = NEW.recipe_id
      AND ci.facility_id = NEW.facility_id;

    -- B. Packaging Cost
    SELECT COALESCE(SUM(ci.last_cost_unit * pc.quantity), 0)
    INTO v_consumable_cost_total
    FROM public.product_consumables pc
    JOIN public.consumable_inventory ci ON pc.consumable_id = ci.consumable_inventory_id
    WHERE pc.product_id = NEW.product_id
      AND ci.facility_id = NEW.facility_id;

    -- C. Store component costs
    NEW.total_coffee_cost     := v_coffee_cost_total * COALESCE(NEW.weight_lbs, 0);
    NEW.total_consumable_cost := v_consumable_cost_total;

    -- D. Total COGS
    NEW.total_unit_cogs := NEW.total_coffee_cost + NEW.total_consumable_cost;

    -- E. Derived margin columns
    NEW.gross_profit_per_unit := COALESCE(NEW.price, 0) - NEW.total_unit_cogs;

    NEW.cogs_pct := CASE
        WHEN COALESCE(NEW.price, 0) > 0
        THEN ROUND(NEW.total_unit_cogs / NEW.price * 100, 1)
        ELSE NULL
    END;

    NEW.margin_pct := CASE
        WHEN COALESCE(NEW.price, 0) > 0
        THEN ROUND((1 - NEW.total_unit_cogs / NEW.price) * 100, 1)
        ELSE NULL
    END;

    RETURN NEW;
END;
$function$;

-- Touch existing merged products to fire the trigger and clear their COGS
UPDATE public.products
SET updated_at = NOW()
WHERE product_type = 'Merged';
