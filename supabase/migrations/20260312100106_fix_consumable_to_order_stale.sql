-- Migration 00106: Fix stale to_order on consumable_inventory
--
-- Root cause: update_consumable_stock_purchased() and update_consumable_stock()
-- only SET in_stock and updated_at when stock changes. The to_order recalc
-- lives in trg_update_consumable_ordering, which fires on UPDATE OF
-- {consumable_inventory_id, facility_id, last_inventory_date, inventory_count,
-- par, restock_level} — in_stock is NOT in that list, so to_order is never
-- recalculated when a purchase or order changes stock.
--
-- Fix: mirror the coffee pattern — compute to_order inline in both functions.
-- Also removes the misleading comment claiming the trigger would fire.

-- ─── 1. update_consumable_stock_purchased() ───────────────────────────────
-- Fired by: AFTER INSERT OR UPDATE OR DELETE on consumable_inventory_purchased

CREATE OR REPLACE FUNCTION public.update_consumable_stock_purchased()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_stock NUMERIC;
    v_target_id     TEXT;
    v_facility_id   TEXT;
BEGIN
    v_target_id   := COALESCE(NEW.consumable_inventory_item, OLD.consumable_inventory_item);
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    v_current_stock := public.calculate_current_stock_consumables(v_target_id, v_facility_id);

    UPDATE public.consumable_inventory
    SET
        in_stock   = v_current_stock,
        to_order   = CASE
                         WHEN v_current_stock <= COALESCE(restock_level, 0)
                         THEN GREATEST(0, COALESCE(par, 0) - v_current_stock)
                         ELSE 0
                     END,
        updated_at = NOW()
    WHERE consumable_inventory_id = v_target_id
      AND facility_id = v_facility_id;

    RETURN NULL;
END;
$$;


-- ─── 2. update_consumable_stock() ─────────────────────────────────────────
-- Fired by: AFTER INSERT OR UPDATE OR DELETE on order_details (consumable usage)

CREATE OR REPLACE FUNCTION public.update_consumable_stock()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    r               RECORD;
    v_product_id    TEXT;
    v_facility_id   TEXT;
    v_current_stock NUMERIC;
BEGIN
    v_product_id  := COALESCE(NEW.product_id, OLD.product_id);
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    FOR r IN
        SELECT consumable_id
        FROM public.product_consumables
        WHERE product_id = v_product_id
    LOOP
        v_current_stock := public.calculate_current_stock_consumables(r.consumable_id, v_facility_id);

        UPDATE public.consumable_inventory
        SET
            in_stock   = v_current_stock,
            to_order   = CASE
                             WHEN v_current_stock <= COALESCE(restock_level, 0)
                             THEN GREATEST(0, COALESCE(par, 0) - v_current_stock)
                             ELSE 0
                         END,
            updated_at = NOW()
        WHERE consumable_inventory_id = r.consumable_id
          AND facility_id = v_facility_id;
    END LOOP;

    RETURN NULL;
END;
$$;


-- ─── 3. Backfill all existing stale to_order values ───────────────────────

UPDATE public.consumable_inventory
SET to_order = CASE
    WHEN in_stock <= COALESCE(restock_level, 0)
    THEN GREATEST(0, COALESCE(par, 0) - in_stock)
    ELSE 0
END;
