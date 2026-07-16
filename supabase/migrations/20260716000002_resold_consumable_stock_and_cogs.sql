-- Unification P2: resold (distribution) consumable sales must DEPLETE STOCK and
-- COST correctly. A resold consumable is a product linked to its stock via
-- products.source_consumable_id, sold as-is (NO BOM — it's not made of parts).
--
-- Today three engines only follow the BOM (product_consumables), so a resold sale
-- (a) never decrements its own consumable stock and (b) resolves to NULL COGS at
-- point-in-time (so unit_cost_at_sale = 0 and backfill skips it). This teaches all
-- three to ALSO follow source_consumable_id (1 consumable unit per unit sold).
--
-- Safe retroactively: stock usage only counts sales AFTER the last physical count
-- (all resold consumables counted 2026-04-30), so pre-count history is excluded.
-- The COGS function change affects only NEW orders + explicit (books-close-aware)
-- backfills; existing cached unit_cost_at_sale rows are untouched.
--
-- Each function is reproduced verbatim from the live prod definition; the ONLY
-- additions are the clearly-marked resold branches.

-- ── 1. Stock: resold sales deplete the linked consumable ─────────────────────
CREATE OR REPLACE FUNCTION public.calculate_current_stock_consumables(p_consumable_id text, p_facility_id text)
  RETURNS numeric
  LANGUAGE plpgsql
AS $function$
DECLARE
    v_last_inventory_date DATE;
    v_inventory_count     NUMERIC;
    v_purchased_amount    NUMERIC;
    v_usage_amount        NUMERIC;
    v_resold_usage        NUMERIC;
BEGIN
    SELECT last_inventory_date, COALESCE(inventory_count, 0)
    INTO v_last_inventory_date, v_inventory_count
    FROM consumable_inventory
    WHERE consumable_inventory_id = p_consumable_id
      AND facility_id = p_facility_id;
    IF v_last_inventory_date IS NULL THEN v_last_inventory_date := '2000-01-01'; END IF;

    SELECT COALESCE(SUM(amount), 0)
    INTO v_purchased_amount
    FROM consumable_inventory_purchased cp
    JOIN shipment_received sr ON cp.shipment_id = sr.shipment_id
    WHERE cp.consumable_inventory_item = p_consumable_id
      AND sr.date_received > v_last_inventory_date
      AND sr.date_received IS NOT NULL
      AND COALESCE(sr.voided, false) = false
      AND cp.facility_id = p_facility_id;

    -- BOM usage (this consumable is an ingredient of a made good).
    SELECT COALESCE(SUM(od.quantity * pc.quantity), 0)
    INTO v_usage_amount
    FROM order_details od
    JOIN orders o ON od.order_id = o.order_id
    JOIN product_consumables pc ON od.product_id = pc.product_id
    WHERE pc.consumable_id = p_consumable_id
      AND o.order_date::DATE > v_last_inventory_date
      AND o.order_status != 'Canceled'
      AND COALESCE(o.is_legacy_import, false) = false
      AND o.facility_id = p_facility_id;

    -- ▼▼ RESOLD usage: a product that IS this consumable (source_consumable_id)
    --    depletes 1 unit per unit sold. Same exclusions as BOM usage. ▼▼
    SELECT COALESCE(SUM(od.quantity), 0)
    INTO v_resold_usage
    FROM order_details od
    JOIN orders o   ON od.order_id = o.order_id
    JOIN products p ON od.product_id = p.product_id
    WHERE p.source_consumable_id = p_consumable_id
      AND o.order_date::DATE > v_last_inventory_date
      AND o.order_status != 'Canceled'
      AND COALESCE(o.is_legacy_import, false) = false
      AND o.facility_id = p_facility_id;

    RETURN GREATEST(0, (v_inventory_count + v_purchased_amount - v_usage_amount - v_resold_usage));
END;
$function$;

-- ── 2. Point-in-time COGS: resold product = its consumable's cost at date ─────
CREATE OR REPLACE FUNCTION public.get_product_cogs_on_date(p_product_id text, p_facility_id text, p_order_date date)
  RETURNS numeric
  LANGUAGE plpgsql
AS $function$
DECLARE
    v_recipe_id         text;
    v_weight_lbs        numeric;
    v_source_consumable text;
    v_coffee_cost       numeric := 0;
    v_consumable_cost   numeric := 0;
    v_component_cost    numeric;
    v_rec               record;
    v_has_any_cost      boolean := false;
BEGIN
    SELECT recipe_id, weight_lbs, source_consumable_id
      INTO v_recipe_id, v_weight_lbs, v_source_consumable
      FROM public.products
     WHERE product_id = p_product_id
     LIMIT 1;

    IF v_recipe_id IS NOT NULL AND COALESCE(v_weight_lbs, 0) > 0 THEN
        FOR v_rec IN
            SELECT rc.coffee_item, rc.percentage
              FROM public.recipe_components rc
             WHERE rc.recipe_id   = v_recipe_id
               AND rc.facility_id = p_facility_id
        LOOP
            v_component_cost := COALESCE(
                public.get_origin_roasted_cost_on_date(v_rec.coffee_item, p_facility_id, p_order_date),
                public.get_coffee_cost_on_date(v_rec.coffee_item, p_facility_id, p_order_date)
            );
            IF v_component_cost IS NOT NULL THEN
                v_coffee_cost  := v_coffee_cost + (v_component_cost * COALESCE(v_rec.percentage, 0));
                v_has_any_cost := true;
            END IF;
        END LOOP;
    END IF;

    FOR v_rec IN
        SELECT pc.consumable_id, pc.quantity
          FROM public.product_consumables pc
         WHERE pc.product_id   = p_product_id
           AND pc.facility_id  = p_facility_id
    LOOP
        v_component_cost := public.get_consumable_cost_on_date(
            v_rec.consumable_id, p_facility_id, p_order_date
        );
        IF v_component_cost IS NOT NULL THEN
            v_consumable_cost := v_consumable_cost + (v_component_cost * COALESCE(v_rec.quantity, 1));
            v_has_any_cost    := true;
        END IF;
    END LOOP;

    -- ▼▼ RESOLD: the product IS its source consumable (no recipe, no BOM) — its
    --    per-unit cost is the consumable's cost on that date (quantity 1). ▼▼
    IF v_source_consumable IS NOT NULL THEN
        v_component_cost := public.get_consumable_cost_on_date(v_source_consumable, p_facility_id, p_order_date);
        IF v_component_cost IS NOT NULL THEN
            v_consumable_cost := v_consumable_cost + v_component_cost;
            v_has_any_cost    := true;
        END IF;
    END IF;

    IF NOT v_has_any_cost THEN
        RETURN NULL;
    END IF;

    RETURN (v_coffee_cost * COALESCE(v_weight_lbs, 0)) + v_consumable_cost;
END;
$function$;

-- ── 3. Sync trigger: recompute the SOURCE consumable on a resold sale ─────────
CREATE OR REPLACE FUNCTION public.update_consumable_stock()
  RETURNS trigger
  LANGUAGE plpgsql
AS $function$
DECLARE
    r               RECORD;
    v_product_id    TEXT;
    v_facility_id   TEXT;
    v_current_stock NUMERIC;
    v_par           NUMERIC;
    v_restock_level NUMERIC;
    v_is_legacy     BOOLEAN;
BEGIN
    SELECT COALESCE(is_legacy_import, false) INTO v_is_legacy
    FROM orders WHERE order_id = COALESCE(NEW.order_id, OLD.order_id);
    IF v_is_legacy THEN RETURN NULL; END IF;

    v_product_id  := COALESCE(NEW.product_id, OLD.product_id);
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    -- Recompute every consumable this line affects: BOM ingredients AND (for a
    -- resold product) its own source consumable.
    FOR r IN
        SELECT consumable_id FROM public.product_consumables WHERE product_id = v_product_id
        UNION
        SELECT source_consumable_id FROM public.products
         WHERE product_id = v_product_id AND source_consumable_id IS NOT NULL
    LOOP
        v_current_stock := public.calculate_current_stock_consumables(r.consumable_id, v_facility_id);
        v_par           := public.calculate_consumable_par(r.consumable_id, v_facility_id);
        v_restock_level := public.calculate_consumable_restock_level(r.consumable_id, v_facility_id);

        UPDATE public.consumable_inventory
        SET
            in_stock      = v_current_stock,
            par           = v_par,
            restock_level = v_restock_level,
            to_order      = CASE
                                WHEN v_current_stock <= v_restock_level
                                THEN GREATEST(0, v_par - v_current_stock)
                                ELSE 0
                            END,
            updated_at    = NOW()
        WHERE consumable_inventory_id = r.consumable_id
          AND facility_id = v_facility_id;
    END LOOP;

    RETURN NULL;
END;
$function$;

NOTIFY pgrst, 'reload schema';
