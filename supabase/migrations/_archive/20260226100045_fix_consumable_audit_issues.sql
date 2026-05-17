-- Migration 00045: Fix consumable inventory audit issues
--
-- 1. Fix spelling: 'Cancelled' → 'Canceled' in calculate_current_stock_consumables()
--    (migration 00042 accidentally reverted the standard set in migration 00000)
-- 2. Fix update_consumable_metrics(): add sr.received = TRUE filter on purchase query
--    (was counting undelivered/future shipments in consumable stock)
-- 3. Add trigger on orders.order_status to recalculate consumable stock when an
--    order is canceled or un-canceled

-- ═══════════════════════════════════════════════════════════════
-- A. Fix calculate_current_stock_consumables() — spelling fix
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.calculate_current_stock_consumables(p_consumable_id text, p_facility_id text) RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
    v_last_inventory_date DATE;
    v_inventory_count NUMERIC;
    v_purchased_amount NUMERIC;
    v_usage_amount NUMERIC;
BEGIN
    -- 1. Get Baseline for THIS facility only
    SELECT last_inventory_date, COALESCE(inventory_count, 0)
    INTO v_last_inventory_date, v_inventory_count
    FROM consumable_inventory
    WHERE consumable_inventory_id = p_consumable_id
      AND facility_id = p_facility_id;

    IF v_last_inventory_date IS NULL THEN
        v_last_inventory_date := '2000-01-01';
    END IF;

    -- 2. Sum Additions (RECEIVED shipments only)
    SELECT COALESCE(SUM(amount), 0)
    INTO v_purchased_amount
    FROM consumable_inventory_purchased cp
    JOIN shipment_received sr ON cp.shipment_id = sr.shipment_id
    WHERE cp.consumable_inventory_item = p_consumable_id
      AND sr.date_received > v_last_inventory_date
      AND sr.received = TRUE
      AND cp.facility_id = p_facility_id;

    -- 3. Sum Subtractions (Usage from non-canceled Orders at THIS facility)
    SELECT COALESCE(SUM(od.quantity * pc.quantity), 0)
    INTO v_usage_amount
    FROM order_details od
    JOIN orders o ON od.order_id = o.order_id
    JOIN product_consumables pc ON od.product_id = pc.product_id
    WHERE pc.consumable_id = p_consumable_id
      AND o.order_date::DATE > v_last_inventory_date
      AND o.order_status != 'Canceled'
      AND o.facility_id = p_facility_id;

    -- 4. Final Calculation
    RETURN GREATEST(0, (v_inventory_count + v_purchased_amount - v_usage_amount));
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- B. Fix update_consumable_metrics() — add received filter
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.update_consumable_metrics() RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    target_id text;
    v_facility_id text;
    v_last_inventory_date DATE;
    v_purchased_amount NUMERIC;
    v_usage_amount NUMERIC;
    v_par numeric;
    v_restock_level numeric;
BEGIN
    target_id := COALESCE(NEW.consumable_inventory_id, OLD.consumable_inventory_id);
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    -- 1. Setup Baseline
    v_last_inventory_date := COALESCE(NEW.last_inventory_date::DATE, '2000-01-01');

    -- 2. Sum Additions (RECEIVED shipments only)
    SELECT COALESCE(SUM(amount), 0)
    INTO v_purchased_amount
    FROM consumable_inventory_purchased cp
    JOIN shipment_received sr ON cp.shipment_id = sr.shipment_id
    WHERE cp.consumable_inventory_item = target_id
      AND sr.date_received > v_last_inventory_date
      AND sr.received = TRUE
      AND cp.facility_id = v_facility_id;

    -- 3. Sum Subtractions (Usage from non-canceled Orders at THIS facility)
    SELECT COALESCE(SUM(od.quantity * pc.quantity), 0)
    INTO v_usage_amount
    FROM order_details od
    JOIN orders o ON od.order_id = o.order_id
    JOIN product_consumables pc ON od.product_id = pc.product_id
    WHERE pc.consumable_id = target_id
      AND o.order_date::DATE > v_last_inventory_date
      AND o.order_status != 'Canceled'
      AND o.facility_id = v_facility_id;

    -- 4. Calculate Final Stock
    NEW.in_stock := GREATEST(0, (COALESCE(NEW.inventory_count, 0) + v_purchased_amount - v_usage_amount));

    -- 5. Calculate "To Order"
    v_par := COALESCE(NEW.par, 0);
    v_restock_level := COALESCE(NEW.restock_level, 0);

    IF NEW.in_stock <= v_restock_level THEN
        NEW.to_order := GREATEST(0, v_par - NEW.in_stock);
    ELSE
        NEW.to_order := 0;
    END IF;

    RETURN NEW;
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- C. Order status change → recalculate consumable stock
-- ═══════════════════════════════════════════════════════════════
-- When an order is canceled or un-canceled, the usage subtraction
-- changes, so consumable stock must be recalculated.

CREATE OR REPLACE FUNCTION public.recalculate_consumables_on_order_status() RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    r RECORD;
    v_facility_id TEXT;
BEGIN
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    -- Only recalculate when cancellation status actually changes
    IF (OLD.order_status = 'Canceled' AND NEW.order_status != 'Canceled')
       OR (OLD.order_status != 'Canceled' AND NEW.order_status = 'Canceled') THEN

        -- Find all consumables affected by products in this order
        FOR r IN
            SELECT DISTINCT pc.consumable_id
            FROM order_details od
            JOIN product_consumables pc ON od.product_id = pc.product_id
            WHERE od.order_id = NEW.order_id
        LOOP
            -- Touch the row to fire trg_update_consumable_ordering
            -- which recalculates in_stock and to_order from scratch
            UPDATE consumable_inventory
            SET updated_at = NOW()
            WHERE consumable_inventory_id = r.consumable_id
              AND facility_id = v_facility_id;
        END LOOP;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_order_status_consumable_sync
    AFTER UPDATE OF order_status ON public.orders
    FOR EACH ROW
    EXECUTE FUNCTION public.recalculate_consumables_on_order_status();

-- ═══════════════════════════════════════════════════════════════
-- D. Recalculate all consumable inventory rows
-- ═══════════════════════════════════════════════════════════════
-- Touches every row so update_consumable_metrics() recalculates
-- with the corrected received filter and spelling.

UPDATE public.consumable_inventory
SET updated_at = NOW();
