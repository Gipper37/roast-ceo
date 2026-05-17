-- Migration 00087: Fix weight_lbs lookup in update_product_total_cogs
--
-- Bug in 00086: products.size stores size_id (e.g. '40edp3ll'), NOT size_name ('8oz').
-- The lookup was: WHERE s.size_name = NEW.size  ← never matches, backfill did nothing.
-- Fix:           WHERE s.size_id   = NEW.size  ← correct.
--
-- Backfill at end corrects weight_lbs on all existing products.

CREATE OR REPLACE FUNCTION public.update_product_total_cogs() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_coffee_cost_total     numeric := 0;
    v_consumable_cost_total numeric := 0;
    v_weight                numeric;
BEGIN
    -- 0. Sync weight_lbs from size table (size table is always canonical).
    --    products.size stores size_id, so join on size_id.
    SELECT s.weight INTO v_weight
    FROM public.size s
    WHERE s.size_id = NEW.size
    LIMIT 1;
    IF v_weight IS NOT NULL THEN
        NEW.weight_lbs := v_weight;
    END IF;

    -- A. Calculate Coffee Cost (Directly from Inventory * Percentage)
    --    Joined using facility_id to prevent double-counting across locations.
    SELECT COALESCE(SUM(ci.latest_cost * rc.percentage), 0)
    INTO v_coffee_cost_total
    FROM public.recipe_components rc
    JOIN public.coffee_inventory ci ON rc.coffee_item = ci.origin_id
    WHERE rc.recipe_id = NEW.recipe_id
      AND ci.facility_id = NEW.facility_id;

    -- B. Calculate Packaging Cost (Directly from Inventory * Quantity)
    --    Joined using facility_id to prevent cross-facility contamination.
    SELECT COALESCE(SUM(ci.last_cost_unit * pc.quantity), 0)
    INTO v_consumable_cost_total
    FROM public.product_consumables pc
    JOIN public.consumable_inventory ci ON pc.consumable_id = ci.consumable_inventory_id
    WHERE pc.product_id = NEW.product_id
      AND ci.facility_id = NEW.facility_id;

    -- C. Set Final Cost on the Product Row
    --    COGS = (Coffee Cost/lb roasted * Product Weight) + Sum of Packaging
    NEW.total_unit_cogs := (v_coffee_cost_total * COALESCE(NEW.weight_lbs, 0)) + v_consumable_cost_total;

    RETURN NEW;
END;
$$;

-- Backfill: re-touch all active products so weight_lbs and total_unit_cogs
-- are recalculated with the corrected size_id lookup.
UPDATE public.products
SET updated_at = now()
WHERE "archived?" = false;
