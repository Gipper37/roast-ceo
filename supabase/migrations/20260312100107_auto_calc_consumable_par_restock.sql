-- Migration 00107: Auto-calculate consumable par and restock_level
--
-- Problem: consumable_inventory.par and restock_level were fully manual.
-- Coffee inventory has calculate_par() and calculate_restock_level() based on
-- 92-day rolling roast usage. Consumables had no equivalent, leading to
-- inconsistent manually-entered values (e.g. Kea Lani restock_level = 65
-- with par = 389, vs. Vida restock_level = 135 with par = 384 — no logic).
--
-- Fix: mirror coffee pattern using order_details × product_consumables as the
-- usage source instead of roast_log. Reuses same company_parameters:
--   par_multiple   (3e6f5909) default 3
--   trigger_multiple (dae6cd4b) default 1.5
--   buffer           (5131610b) default 1.3
-- No bag_size division — consumables are in units, not bags.
-- Zero-usage items get par = 0, restock_level = 0 (prevents false signals
-- for discontinued or never-sold items).


-- ─── 1. calculate_consumable_par(consumable_id, facility_id) ──────────────

CREATE OR REPLACE FUNCTION public.calculate_consumable_par(
    p_consumable_id text,
    p_facility_id   text
) RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
    v_92day_usage    NUMERIC;
    v_monthly_usage  NUMERIC;
    v_par_multiple   NUMERIC;
    v_buffer         NUMERIC;
BEGIN
    -- 1. Sum usage over last 92 days from order history
    SELECT COALESCE(SUM(od.quantity * pc.quantity), 0)
    INTO v_92day_usage
    FROM public.order_details od
    JOIN public.orders o ON od.order_id = o.order_id
    JOIN public.product_consumables pc ON od.product_id = pc.product_id
    WHERE pc.consumable_id = p_consumable_id
      AND o.order_date >= CURRENT_DATE - INTERVAL '92 days'
      AND o.order_status != 'Canceled'
      AND o.facility_id = p_facility_id;

    -- Return 0 for items with no recent sales history
    IF v_92day_usage = 0 THEN RETURN 0; END IF;

    v_monthly_usage := v_92day_usage / 3.0;

    -- 2. Parameters (same IDs used by coffee calculate_par)
    SELECT value_number INTO v_par_multiple
    FROM public.company_parameters
    WHERE parameter_id = '3e6f5909' AND facility_id = p_facility_id;

    SELECT value_number INTO v_buffer
    FROM public.company_parameters
    WHERE parameter_id = '5131610b' AND facility_id = p_facility_id;

    v_par_multiple := COALESCE(v_par_multiple, 3);
    v_buffer       := COALESCE(v_buffer, 1.3);

    -- 3. Par = monthly usage × par_multiple × buffer (ceiling, in units)
    RETURN CEIL(v_monthly_usage * v_par_multiple * v_buffer);
END;
$$;


-- ─── 2. calculate_consumable_restock_level(consumable_id, facility_id) ────

CREATE OR REPLACE FUNCTION public.calculate_consumable_restock_level(
    p_consumable_id text,
    p_facility_id   text
) RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
    v_92day_usage       NUMERIC;
    v_monthly_usage     NUMERIC;
    v_trigger_multiple  NUMERIC;
    v_buffer            NUMERIC;
BEGIN
    -- 1. Sum usage over last 92 days from order history
    SELECT COALESCE(SUM(od.quantity * pc.quantity), 0)
    INTO v_92day_usage
    FROM public.order_details od
    JOIN public.orders o ON od.order_id = o.order_id
    JOIN public.product_consumables pc ON od.product_id = pc.product_id
    WHERE pc.consumable_id = p_consumable_id
      AND o.order_date >= CURRENT_DATE - INTERVAL '92 days'
      AND o.order_status != 'Canceled'
      AND o.facility_id = p_facility_id;

    -- Return 0 for items with no recent sales history
    IF v_92day_usage = 0 THEN RETURN 0; END IF;

    v_monthly_usage := v_92day_usage / 3.0;

    -- 2. Parameters (same IDs used by coffee calculate_restock_level)
    SELECT value_number INTO v_trigger_multiple
    FROM public.company_parameters
    WHERE parameter_id = 'dae6cd4b' AND facility_id = p_facility_id;

    SELECT value_number INTO v_buffer
    FROM public.company_parameters
    WHERE parameter_id = '5131610b' AND facility_id = p_facility_id;

    v_trigger_multiple := COALESCE(v_trigger_multiple, 1.5);
    v_buffer           := COALESCE(v_buffer, 1.3);

    -- 3. Restock level = monthly usage × trigger_multiple × buffer (ceiling)
    RETURN CEIL(v_monthly_usage * v_trigger_multiple * v_buffer);
END;
$$;


-- ─── 3. update_consumable_metrics() — add auto-calc before to_order ───────
-- Fires on: BEFORE INSERT OR UPDATE OF consumable_inventory_id, facility_id,
--           last_inventory_date, inventory_count, par, restock_level

CREATE OR REPLACE FUNCTION public.update_consumable_metrics()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    target_id             text;
    v_facility_id         text;
    v_last_inventory_date DATE;
    v_purchased_amount    NUMERIC;
    v_usage_amount        NUMERIC;
    v_par                 numeric;
    v_restock_level       numeric;
BEGIN
    target_id     := COALESCE(NEW.consumable_inventory_id, OLD.consumable_inventory_id);
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    -- 1. Baseline
    v_last_inventory_date := COALESCE(NEW.last_inventory_date::DATE, '2000-01-01');

    -- 2. Additions (RECEIVED shipments only — date_received IS NOT NULL)
    SELECT COALESCE(SUM(amount), 0)
    INTO v_purchased_amount
    FROM public.consumable_inventory_purchased cp
    JOIN public.shipment_received sr ON cp.shipment_id = sr.shipment_id
    WHERE cp.consumable_inventory_item = target_id
      AND sr.date_received > v_last_inventory_date
      AND sr.date_received IS NOT NULL
      AND cp.facility_id = v_facility_id;

    -- 3. Subtractions (non-canceled orders)
    SELECT COALESCE(SUM(od.quantity * pc.quantity), 0)
    INTO v_usage_amount
    FROM public.order_details od
    JOIN public.orders o ON od.order_id = o.order_id
    JOIN public.product_consumables pc ON od.product_id = pc.product_id
    WHERE pc.consumable_id = target_id
      AND o.order_date::DATE > v_last_inventory_date
      AND o.order_status != 'Canceled'
      AND o.facility_id = v_facility_id;

    -- 4. Current stock
    NEW.in_stock := GREATEST(0, (COALESCE(NEW.inventory_count, 0) + v_purchased_amount - v_usage_amount));

    -- 5. Auto-calculate par and restock_level from 92-day order history
    NEW.par           := public.calculate_consumable_par(target_id, v_facility_id);
    NEW.restock_level := public.calculate_consumable_restock_level(target_id, v_facility_id);

    v_par           := NEW.par;
    v_restock_level := NEW.restock_level;

    -- 6. To order
    IF NEW.in_stock <= v_restock_level THEN
        NEW.to_order := GREATEST(0, v_par - NEW.in_stock);
    ELSE
        NEW.to_order := 0;
    END IF;

    RETURN NEW;
END;
$$;


-- ─── 4. update_consumable_stock_purchased() — add par/restock to UPDATE ───
-- Fires on: AFTER INSERT OR UPDATE OR DELETE on consumable_inventory_purchased

CREATE OR REPLACE FUNCTION public.update_consumable_stock_purchased()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_stock  NUMERIC;
    v_par            NUMERIC;
    v_restock_level  NUMERIC;
    v_target_id      TEXT;
    v_facility_id    TEXT;
BEGIN
    v_target_id   := COALESCE(NEW.consumable_inventory_item, OLD.consumable_inventory_item);
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    v_current_stock := public.calculate_current_stock_consumables(v_target_id, v_facility_id);
    v_par           := public.calculate_consumable_par(v_target_id, v_facility_id);
    v_restock_level := public.calculate_consumable_restock_level(v_target_id, v_facility_id);

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
    WHERE consumable_inventory_id = v_target_id
      AND facility_id = v_facility_id;

    RETURN NULL;
END;
$$;


-- ─── 5. update_consumable_stock() — add par/restock to UPDATE ─────────────
-- Fires on: AFTER INSERT OR UPDATE OR DELETE on order_details

CREATE OR REPLACE FUNCTION public.update_consumable_stock()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    r               RECORD;
    v_product_id    TEXT;
    v_facility_id   TEXT;
    v_current_stock NUMERIC;
    v_par           NUMERIC;
    v_restock_level NUMERIC;
BEGIN
    v_product_id  := COALESCE(NEW.product_id, OLD.product_id);
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    FOR r IN
        SELECT consumable_id
        FROM public.product_consumables
        WHERE product_id = v_product_id
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
$$;


-- ─── 6. Backfill all consumable_inventory rows ────────────────────────────

DO $$
DECLARE
    r               RECORD;
    v_par           NUMERIC;
    v_restock_level NUMERIC;
BEGIN
    FOR r IN
        SELECT consumable_inventory_id, facility_id, in_stock
        FROM public.consumable_inventory
    LOOP
        v_par           := public.calculate_consumable_par(r.consumable_inventory_id, r.facility_id);
        v_restock_level := public.calculate_consumable_restock_level(r.consumable_inventory_id, r.facility_id);

        UPDATE public.consumable_inventory
        SET
            par           = v_par,
            restock_level = v_restock_level,
            to_order      = CASE
                                WHEN r.in_stock <= v_restock_level
                                THEN GREATEST(0, v_par - r.in_stock)
                                ELSE 0
                            END
        WHERE consumable_inventory_id = r.consumable_inventory_id
          AND facility_id = r.facility_id;
    END LOOP;
END;
$$;
