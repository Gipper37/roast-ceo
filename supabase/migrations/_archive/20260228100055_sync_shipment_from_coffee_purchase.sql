-- Migration 00055: Move current_shipment_id auto-sync to coffee_inventory_purchased
--
-- Problem with migration 00053 (trigger on shipment_received INSERT):
--   1. Fires for ANY shipment — consumables-only shipments incorrectly hijack
--      current_shipment_id, showing 0 lbs in the Shipment Order Guide.
--   2. At INSERT time, no coffee lines exist yet — can't confirm it's a coffee shipment.
--
-- Fix: Move the trigger to coffee_inventory_purchased AFTER INSERT.
--   - Only fires when a coffee line is actually added (definitively a coffee shipment)
--   - Compares order_date (falling back to created_at) to avoid switching backwards
--     when a user edits an older shipment
--   - Handles the case where a new shipment is created before the previous one arrives:
--     order_date comparison ensures the most recently *ordered* shipment always wins
--
-- Trigger firing order on coffee_inventory_purchased INSERT (alphabetical):
--   1. trg_sync_current_shipment_from_coffee_purchase  ← sets current_shipment_id
--   2. trg_update_green_metrics_from_purchased          ← recalcs metrics using updated id

-- ═══════════════════════════════════════════════════════════════
-- A. Drop old trigger and function (shipment_received INSERT)
-- ═══════════════════════════════════════════════════════════════

DROP TRIGGER IF EXISTS trg_sync_current_shipment ON public.shipment_received;
DROP FUNCTION IF EXISTS public.sync_current_shipment_on_new_order();

-- ═══════════════════════════════════════════════════════════════
-- B. New function: fires on coffee_inventory_purchased INSERT
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.sync_current_shipment_from_coffee_purchase()
RETURNS TRIGGER AS $$
DECLARE
    v_current_shipment_id  TEXT;
    v_new_order_date       DATE;
    v_new_created_at       TIMESTAMPTZ;
    v_cur_order_date       DATE;
    v_cur_created_at       TIMESTAMPTZ;
BEGIN
    -- Get this facility's current shipment reference
    SELECT current_shipment_id
    INTO v_current_shipment_id
    FROM public.recent_coffee_order
    WHERE facility_id = NEW.facility_id;

    -- Same shipment: adding more lines to the current one — no switch needed,
    -- trg_update_green_metrics_from_purchased handles the recalc
    IF v_current_shipment_id IS NOT DISTINCT FROM NEW.shipment_id THEN
        RETURN NEW;
    END IF;

    -- Look up new shipment's date info
    SELECT order_date, created_at
    INTO v_new_order_date, v_new_created_at
    FROM public.shipment_received
    WHERE shipment_id = NEW.shipment_id;

    -- Look up current shipment's date info (skip if no current shipment yet)
    IF v_current_shipment_id IS NOT NULL THEN
        SELECT order_date, created_at
        INTO v_cur_order_date, v_cur_created_at
        FROM public.shipment_received
        WHERE shipment_id = v_current_shipment_id;
    END IF;

    -- Switch only if new shipment is >= current (or there is no current shipment).
    -- Falls back to created_at::date when order_date is NULL.
    IF v_current_shipment_id IS NULL
       OR COALESCE(v_new_order_date, v_new_created_at::date)
          >= COALESCE(v_cur_order_date, v_cur_created_at::date)
    THEN
        UPDATE public.recent_coffee_order
        SET current_shipment_id = NEW.shipment_id
        WHERE facility_id = NEW.facility_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ═══════════════════════════════════════════════════════════════
-- C. Attach trigger to coffee_inventory_purchased
-- ═══════════════════════════════════════════════════════════════

CREATE TRIGGER trg_sync_current_shipment_from_coffee_purchase
    AFTER INSERT ON public.coffee_inventory_purchased
    FOR EACH ROW EXECUTE FUNCTION public.sync_current_shipment_from_coffee_purchase();
