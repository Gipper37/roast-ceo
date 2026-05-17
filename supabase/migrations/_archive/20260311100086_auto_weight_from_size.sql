-- Migration 00086: Auto-populate weight_lbs from size table
--
-- Problem: products.size is a plain text column with no FK to the size table.
--          products.weight_lbs was manually entered. The COGS trigger uses
--          weight_lbs directly, so a missing/wrong value silently breaks COGS.
--
-- Fix: Modify update_product_total_cogs() to look up size.weight by size_name
--      and always overwrite weight_lbs before the COGS calculation.
--      Size table is the single source of truth for weight.
--
-- Backfill at end: updates all existing products so weight_lbs is corrected now.

CREATE OR REPLACE FUNCTION public.update_product_total_cogs() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_coffee_cost_total     numeric := 0;
    v_consumable_cost_total numeric := 0;
    v_weight                numeric;
BEGIN
    -- 0. Sync weight_lbs from size table (size table is always canonical)
    SELECT s.weight INTO v_weight
    FROM public.size s
    WHERE s.size_name = NEW.size
      AND s.company_id = NEW.company_id
    LIMIT 1;
    IF v_weight IS NOT NULL THEN
        NEW.weight_lbs := v_weight;
    END IF;

    -- A. Calculate Coffee Cost (Directly from Inventory * Percentage)
    -- [FIX] Joined using facility_id to prevent double-counting across locations
    SELECT COALESCE(SUM(ci.latest_cost * rc.percentage), 0)
    INTO v_coffee_cost_total
    FROM public.recipe_components rc
    JOIN public.coffee_inventory ci ON rc.coffee_item = ci.origin_id
    WHERE rc.recipe_id = NEW.recipe_id
      AND ci.facility_id = NEW.facility_id;

    -- B. Calculate Packaging Cost (Directly from Inventory * Quantity)
    -- [FIX] Joined using facility_id
    SELECT COALESCE(SUM(ci.last_cost_unit * pc.quantity), 0)
    INTO v_consumable_cost_total
    FROM public.product_consumables pc
    JOIN public.consumable_inventory ci ON pc.consumable_id = ci.consumable_inventory_id
    WHERE pc.product_id = NEW.product_id
      AND ci.facility_id = NEW.facility_id;

    -- C. Set Final Cost on the Product Row
    -- COGS = (Coffee Cost/lb * Product Weight) + Sum of Packaging
    NEW.total_unit_cogs := (v_coffee_cost_total * COALESCE(NEW.weight_lbs, 0)) + v_consumable_cost_total;

    RETURN NEW;
END;
$$;

-- Backfill: update weight_lbs on all existing products where the size table has a match.
-- The trigger fires on UPDATE and will confirm/re-set the value.
UPDATE public.products p
SET weight_lbs = s.weight
FROM public.size s
WHERE s.size_name = p.size
  AND s.company_id = p.company_id;
