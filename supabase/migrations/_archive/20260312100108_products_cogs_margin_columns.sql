-- Migration 00108: Add gross_profit_per_unit, cogs_pct, margin_pct to products
--
-- Problem: product_margins and related views don't refresh in AppSheet on UPDATE.
-- Fix: store these three calculated columns directly on products so AppSheet
-- picks them up natively. All three derive from existing columns:
--   gross_profit_per_unit = price - total_unit_cogs
--   cogs_pct              = total_unit_cogs / price * 100  (1 decimal)
--   margin_pct            = (price - total_unit_cogs) / price * 100  (1 decimal)
-- NULL when price is 0 or NULL (prevents division by zero).
--
-- trg_update_product_cogs fires BEFORE INSERT OR UPDATE (no column restriction)
-- so adding calcs to update_product_total_cogs() covers all update paths,
-- including direct price changes.


-- ─── 1. Add columns ──────────────────────────────────────────────────────────

ALTER TABLE public.products
    ADD COLUMN IF NOT EXISTS gross_profit_per_unit numeric,
    ADD COLUMN IF NOT EXISTS cogs_pct              numeric,
    ADD COLUMN IF NOT EXISTS margin_pct            numeric;


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

    -- C. Total COGS
    NEW.total_unit_cogs := (v_coffee_cost_total * COALESCE(NEW.weight_lbs, 0)) + v_consumable_cost_total;

    -- D. Derived margin columns
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


-- ─── 3. Backfill all existing products ───────────────────────────────────────
-- Touch every row to fire trg_update_product_cogs and populate the new columns.

UPDATE public.products SET updated_at = NOW();
