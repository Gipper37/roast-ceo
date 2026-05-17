-- Migration 00112: Add total_coffee_cost and total_consumable_cost to products
--
-- These are already computed inside update_product_total_cogs() but were not
-- stored. Surfacing them as columns so AppSheet can display cost breakdown.
--   total_coffee_cost     = v_coffee_cost_total × weight_lbs
--   total_consumable_cost = v_consumable_cost_total
-- Their sum equals total_unit_cogs.


-- ─── 1. Add columns ──────────────────────────────────────────────────────────

ALTER TABLE public.products
    ADD COLUMN IF NOT EXISTS total_coffee_cost     numeric,
    ADD COLUMN IF NOT EXISTS total_consumable_cost numeric;


-- ─── 2. Update update_product_total_cogs() ───────────────────────────────────

CREATE OR REPLACE FUNCTION public.update_product_total_cogs()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_coffee_cost_total     numeric := 0;
    v_consumable_cost_total numeric := 0;
    v_weight                numeric;
BEGIN
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


-- ─── 3. Backfill ─────────────────────────────────────────────────────────────

UPDATE public.products SET updated_at = NOW();
