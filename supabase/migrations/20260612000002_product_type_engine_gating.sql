-- ============================================================================
-- Gate the roast/COGS engine to Coffee only; flat COGS for non-coffee items
-- ----------------------------------------------------------------------------
-- Depends on 20260612000001 (product_type repurposed, products.unit_cost +
-- source_consumable_id added). After this migration:
--   * Coffee products  -> existing recipe->coffee_inventory COGS chain (UNCHANGED).
--   * Non-coffee items -> flat unit_cost COGS (auto-pulled from the linked
--                         consumable_inventory.last_cost_unit when set), and NEVER
--                         touch recipe_components / coffee_inventory.
-- The two cost systems are fully separate; the kind gate decides which path runs.
-- ============================================================================

BEGIN;

-- 1. update_product_total_cogs(): kind-gated COGS ------------------------------
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
    v_kind                  text;
    v_is_coffee             boolean;
BEGIN
    -- Already inactive: short-circuit, touch nothing
    IF COALESCE(NEW.is_active, true) = false
       AND COALESCE(OLD.is_active, true) = false THEN
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

    -- Determine item nature (one PK lookup). Default to Coffee for safety.
    SELECT pt.product_type INTO v_kind
    FROM public.product_type pt
    WHERE pt.product_type_id = NEW.product_type;
    v_is_coffee := (COALESCE(v_kind, 'Coffee') = 'Coffee');

    IF v_is_coffee THEN
        -- ── COFFEE: existing recipe + consumable-BOM COGS (UNCHANGED) ─────────
        SELECT COALESCE(SUM(ci.latest_cost * rc.percentage), 0)
        INTO v_coffee_cost_total
        FROM public.recipe_components rc
        JOIN public.coffee_inventory ci ON rc.coffee_item = ci.origin_id
        WHERE rc.recipe_id   = NEW.recipe_id
          AND ci.facility_id = NEW.facility_id;

        SELECT COALESCE(SUM(ci.last_cost_unit * pc.quantity), 0)
        INTO v_consumable_cost_total
        FROM public.product_consumables pc
        JOIN public.consumable_inventory ci ON pc.consumable_id = ci.consumable_inventory_id
        WHERE pc.product_id  = NEW.product_id
          AND ci.facility_id = NEW.facility_id;

        v_total_cogs := (v_coffee_cost_total * COALESCE(NEW.weight_lbs, 0)) + v_consumable_cost_total;
    ELSE
        -- ── NON-COFFEE: flat unit_cost; no recipe/coffee_inventory joins ──────
        -- Auto-pull unit_cost from the linked consumable's last purchase cost.
        IF NEW.source_consumable_id IS NOT NULL THEN
            SELECT ci.last_cost_unit INTO NEW.unit_cost
            FROM public.consumable_inventory ci
            WHERE ci.consumable_inventory_id = NEW.source_consumable_id
              AND ci.facility_id = NEW.facility_id;
        END IF;
        v_coffee_cost_total     := 0;
        v_consumable_cost_total := 0;
        v_total_cogs            := COALESCE(NEW.unit_cost, 0);
    END IF;

    -- Common derived metrics
    v_gross_profit := COALESCE(NEW.price, 0) - v_total_cogs;
    v_cogs_pct     := CASE WHEN COALESCE(NEW.price, 0) > 0
                           THEN ROUND(v_total_cogs / NEW.price * 100, 1) ELSE NULL END;
    v_margin_pct   := CASE WHEN COALESCE(NEW.price, 0) > 0
                           THEN ROUND((1 - v_total_cogs / NEW.price) * 100, 1) ELSE NULL END;

    -- ── Transitioning to inactive: snapshot last_active_*, null live cols ─────
    IF COALESCE(NEW.is_active, true) = false
       AND COALESCE(OLD.is_active, true) = true THEN
        NEW.last_active_unit_cogs             := v_total_cogs;
        NEW.last_active_cogs_pct              := v_cogs_pct;
        NEW.last_active_gross_profit_per_unit := v_gross_profit;
        NEW.last_active_margin_pct            := v_margin_pct;
        NEW.total_coffee_cost      := NULL;
        NEW.total_consumable_cost  := NULL;
        NEW.total_unit_cogs        := NULL;
        NEW.gross_profit_per_unit  := NULL;
        NEW.cogs_pct               := NULL;
        NEW.margin_pct             := NULL;
        RETURN NEW;
    END IF;

    -- ── Merged: null everything out (was product_type='Merged' [dead]; now the
    --    reliable signal merge_into_id IS NOT NULL) ─────────────────────────────
    IF NEW.merge_into_id IS NOT NULL THEN
        NEW.total_coffee_cost      := NULL;
        NEW.total_consumable_cost  := NULL;
        NEW.total_unit_cogs        := NULL;
        NEW.gross_profit_per_unit  := NULL;
        NEW.cogs_pct               := NULL;
        NEW.margin_pct             := NULL;
        RETURN NEW;
    END IF;

    -- ── Active: set live columns + keep last_active_* current ─────────────────
    IF v_is_coffee THEN
        NEW.total_coffee_cost     := v_coffee_cost_total * COALESCE(NEW.weight_lbs, 0);
        NEW.total_consumable_cost := v_consumable_cost_total;
    ELSE
        NEW.total_coffee_cost     := NULL;   -- non-coffee carries cost in total_unit_cogs only
        NEW.total_consumable_cost := NULL;
    END IF;
    NEW.total_unit_cogs                   := v_total_cogs;
    NEW.gross_profit_per_unit             := v_gross_profit;
    NEW.cogs_pct                          := v_cogs_pct;
    NEW.margin_pct                        := v_margin_pct;
    NEW.last_active_unit_cogs             := v_total_cogs;
    NEW.last_active_cogs_pct              := v_cogs_pct;
    NEW.last_active_gross_profit_per_unit := v_gross_profit;
    NEW.last_active_margin_pct            := v_margin_pct;

    RETURN NEW;
END;
$function$;

-- 2. build_product_name(): don't auto-name groupless (non-coffee) items --------
--    Coffee = [Group] - [Size] - [Channel] (unchanged). Items with no group
--    (Shipping, Sales Discount, a Monin syrup) keep their directly-entered name.
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
  -- No group => unstructured (non-coffee) product: keep provided product_name.
  IF NEW.group_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT group_name INTO v_group_name
    FROM product_groups WHERE group_id = NEW.group_id;

  IF NEW.size IS NOT NULL THEN
    SELECT size_name INTO v_size_name FROM size WHERE size_id = NEW.size;
  END IF;

  IF NEW.channel IS NOT NULL THEN
    SELECT initcap(replace(channel, '_', ' ')) INTO v_channel
      FROM channel WHERE channel_id = NEW.channel;
  END IF;

  IF v_group_name IS NOT NULL THEN
    v_parts := v_parts || v_group_name;
  END IF;
  IF v_size_name IS NOT NULL AND v_size_name != '' THEN
    v_parts := v_parts || v_size_name;
  END IF;
  IF v_channel IS NOT NULL AND v_channel != '' THEN
    v_parts := v_parts || v_channel;
  END IF;

  NEW.product_name := array_to_string(v_parts, ' - ');
  RETURN NEW;
END;
$function$;

-- 3. propagate_consumable_cost_to_products(): also refresh resale-linked items --
--    When a consumable's last_cost_unit changes, touch (a) products using it in a
--    BOM (existing) and (b) products that ARE it (source_consumable_id link). The
--    BEFORE-update COGS trigger then re-pulls unit_cost for the linked items.
CREATE OR REPLACE FUNCTION public.propagate_consumable_cost_to_products()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF OLD.last_cost_unit IS DISTINCT FROM NEW.last_cost_unit THEN
        -- (a) coffee/consumable products that use this consumable in their BOM
        UPDATE public.products p
        SET updated_at = now()
        FROM public.product_consumables pc
        WHERE pc.consumable_id = NEW.consumable_inventory_id
          AND pc.product_id    = p.product_id
          AND p.is_active      = true;

        -- (b) non-coffee resale products sold AS this consumable (auto-pull unit_cost)
        UPDATE public.products p
        SET updated_at = now()
        WHERE p.source_consumable_id = NEW.consumable_inventory_id
          AND p.is_active = true;
    END IF;

    RETURN NULL;
END;
$function$;

COMMIT;
