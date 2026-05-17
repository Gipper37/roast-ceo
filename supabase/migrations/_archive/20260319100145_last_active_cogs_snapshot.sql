-- Migration 00145: last_active_* COGS snapshot columns on products
-- Active products: last_active_* mirrors live columns continuously
-- On archive: last_active_* frozen from last order data (backfill) or
--             calculated snapshot (going forward), live cost columns nulled
-- Already archived: trigger short-circuits, nothing recalculates

-- ── 1. Add columns ────────────────────────────────────────────────────────────

ALTER TABLE public.products
    ADD COLUMN IF NOT EXISTS last_active_unit_cogs          numeric,
    ADD COLUMN IF NOT EXISTS last_active_cogs_pct           numeric,
    ADD COLUMN IF NOT EXISTS last_active_gross_profit_per_unit numeric,
    ADD COLUMN IF NOT EXISTS last_active_margin_pct         numeric;

-- ── 2. Update trigger function ────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.update_product_total_cogs()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_coffee_cost_total     numeric := 0;
    v_consumable_cost_total numeric := 0;
    v_weight                numeric;
    v_total_cogs            numeric;
    v_gross_profit          numeric;
    v_cogs_pct              numeric;
    v_margin_pct            numeric;
BEGIN
    -- ── Already archived: short-circuit, touch nothing ────────────────────────
    IF COALESCE(NEW."archived?", false) = true
       AND COALESCE(OLD."archived?", false) = true THEN
        RETURN NEW;
    END IF;

    -- ── Calculate COGS ────────────────────────────────────────────────────────

    -- 0. Sync weight_lbs from size table
    SELECT s.weight INTO v_weight
    FROM public.size s
    WHERE s.size_id = NEW.size
    LIMIT 1;

    IF v_weight IS NOT NULL THEN
        NEW.weight_lbs := v_weight;
    END IF;

    -- A. Coffee cost
    SELECT COALESCE(SUM(ci.latest_cost * rc.percentage), 0)
    INTO v_coffee_cost_total
    FROM public.recipe_components rc
    JOIN public.coffee_inventory ci ON rc.coffee_item = ci.origin_id
    WHERE rc.recipe_id   = NEW.recipe_id
      AND ci.facility_id = NEW.facility_id;

    -- B. Consumable cost
    SELECT COALESCE(SUM(ci.last_cost_unit * pc.quantity), 0)
    INTO v_consumable_cost_total
    FROM public.product_consumables pc
    JOIN public.consumable_inventory ci ON pc.consumable_id = ci.consumable_inventory_id
    WHERE pc.product_id  = NEW.product_id
      AND ci.facility_id = NEW.facility_id;

    -- C. Totals
    v_total_cogs   := (v_coffee_cost_total * COALESCE(NEW.weight_lbs, 0)) + v_consumable_cost_total;
    v_gross_profit := COALESCE(NEW.price, 0) - v_total_cogs;
    v_cogs_pct     := CASE WHEN COALESCE(NEW.price, 0) > 0
                           THEN ROUND(v_total_cogs / NEW.price * 100, 1)
                           ELSE NULL END;
    v_margin_pct   := CASE WHEN COALESCE(NEW.price, 0) > 0
                           THEN ROUND((1 - v_total_cogs / NEW.price) * 100, 1)
                           ELSE NULL END;

    -- ── Transitioning to archived ─────────────────────────────────────────────
    IF COALESCE(NEW."archived?", false) = true
       AND COALESCE(OLD."archived?", false) = false THEN

        -- Snapshot calculated values into last_active_*
        NEW.last_active_unit_cogs              := v_total_cogs;
        NEW.last_active_cogs_pct               := v_cogs_pct;
        NEW.last_active_gross_profit_per_unit  := v_gross_profit;
        NEW.last_active_margin_pct             := v_margin_pct;

        -- Null out live cost columns
        NEW.total_coffee_cost      := NULL;
        NEW.total_consumable_cost  := NULL;
        NEW.total_unit_cogs        := NULL;
        NEW.gross_profit_per_unit  := NULL;
        NEW.cogs_pct               := NULL;
        NEW.margin_pct             := NULL;

        RETURN NEW;
    END IF;

    -- ── Merged: null everything out ───────────────────────────────────────────
    IF NEW.product_type = 'Merged' THEN
        NEW.total_coffee_cost      := NULL;
        NEW.total_consumable_cost  := NULL;
        NEW.total_unit_cogs        := NULL;
        NEW.gross_profit_per_unit  := NULL;
        NEW.cogs_pct               := NULL;
        NEW.margin_pct             := NULL;
        RETURN NEW;
    END IF;

    -- ── Active: set live columns + keep last_active_* current ─────────────────
    NEW.total_coffee_cost              := v_coffee_cost_total * COALESCE(NEW.weight_lbs, 0);
    NEW.total_consumable_cost          := v_consumable_cost_total;
    NEW.total_unit_cogs                := v_total_cogs;
    NEW.gross_profit_per_unit          := v_gross_profit;
    NEW.cogs_pct                       := v_cogs_pct;
    NEW.margin_pct                     := v_margin_pct;
    NEW.last_active_unit_cogs          := v_total_cogs;
    NEW.last_active_cogs_pct           := v_cogs_pct;
    NEW.last_active_gross_profit_per_unit := v_gross_profit;
    NEW.last_active_margin_pct         := v_margin_pct;

    RETURN NEW;
END;
$function$;

-- ── 3. Backfill last_active_* for currently archived products ─────────────────
-- Use unit_cost_at_sale / total_price from last non-canceled order — the most
-- accurate historical snapshot available after the COGS backfill.

WITH last_order AS (
    SELECT DISTINCT ON (od.product_id)
        od.product_id,
        ROUND(od.unit_cost_at_sale / NULLIF(od.quantity, 0), 4)                          AS unit_cogs,
        ROUND(od.unit_cost_at_sale / NULLIF(od.total_price, 0) * 100, 1)                 AS cogs_pct,
        ROUND((od.total_price - od.unit_cost_at_sale) / NULLIF(od.quantity, 0), 4)       AS gross_profit,
        ROUND((od.total_price - od.unit_cost_at_sale) / NULLIF(od.total_price, 0) * 100, 1) AS margin_pct
    FROM public.order_details od
    JOIN public.orders o ON o.order_id = od.order_id
    WHERE o.order_status != 'Canceled'
      AND COALESCE(od.quantity, 0) > 0
      AND od.total_price > 0
    ORDER BY od.product_id, o.order_date DESC
)
UPDATE public.products p
SET
    last_active_unit_cogs             = lo.unit_cogs,
    last_active_cogs_pct              = lo.cogs_pct,
    last_active_gross_profit_per_unit = lo.gross_profit,
    last_active_margin_pct            = lo.margin_pct,
    -- Null out live cost columns for archived products
    total_coffee_cost                 = NULL,
    total_consumable_cost             = NULL,
    total_unit_cogs                   = NULL,
    gross_profit_per_unit             = NULL,
    cogs_pct                          = NULL,
    margin_pct                        = NULL
FROM last_order lo
WHERE p.product_id = lo.product_id
  AND p."archived?" = true
  AND COALESCE(p.product_type, '') != 'Merged';

-- ── 4. Backfill last_active_* for active products (mirrors live columns) ──────
UPDATE public.products
SET
    last_active_unit_cogs             = total_unit_cogs,
    last_active_cogs_pct              = cogs_pct,
    last_active_gross_profit_per_unit = gross_profit_per_unit,
    last_active_margin_pct            = margin_pct
WHERE ("archived?" = false OR "archived?" IS NULL)
  AND COALESCE(product_type, '') != 'Merged'
  AND total_unit_cogs IS NOT NULL;
