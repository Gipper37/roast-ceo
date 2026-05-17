-- Migration 00057: Round shipping_cost_unit to 3 decimal places
--
-- Two functions both write to shipment_received.shipping_cost_unit with
-- inconsistent precision: calculate_shipment_totals() applies no rounding,
-- calculate_shipping_per_unit() rounds to 4 decimal places. AppSheet treats
-- values with more than 3 decimal places as invalid.
-- Fix: standardize both to ROUND(..., 3) and backfill existing rows.

-- ═══════════════════════════════════════════════════════════════
-- A. calculate_shipment_totals() — add ROUND(..., 3)
--    Fires via: update_shipment_on_coffee, update_shipment_on_consumable
--    (AFTER INSERT OR DELETE OR UPDATE on coffee/consumable_inventory_purchased)
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.calculate_shipment_totals()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_shipment_id TEXT;
    v_facility_id TEXT;
    v_total_weight NUMERIC;
BEGIN
    -- 0. Resolve the correct row reference based on operation type
    --    NEW is NULL on DELETE; OLD is NULL on INSERT.
    IF TG_OP = 'DELETE' THEN
        v_shipment_id := OLD.shipment_id;
        v_facility_id := OLD.facility_id;
    ELSE
        v_shipment_id := NEW.shipment_id;
        v_facility_id := NEW.facility_id;
    END IF;

    -- 1. Calculate Total Weight (Coffee + Consumables)
    v_total_weight := (
        SELECT COALESCE(SUM(amount), 0)
        FROM coffee_inventory_purchased
        WHERE shipment_id = v_shipment_id
          AND facility_id = v_facility_id
    ) + (
        SELECT COALESCE(SUM(amount), 0)
        FROM consumable_inventory_purchased
        WHERE shipment_id = v_shipment_id
          AND facility_id = v_facility_id
    );

    -- 2. Update the Shipment Header
    UPDATE shipment_received
    SET
        shipment_total_weight_units = v_total_weight,
        shipping_cost_unit = CASE
            WHEN v_total_weight > 0 THEN ROUND(shipping_cost / v_total_weight, 3)
            ELSE 0
        END
    WHERE shipment_id = v_shipment_id
      AND facility_id = v_facility_id;

    -- 3. Return appropriate row
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- B. calculate_shipping_per_unit() — change ROUND(..., 4) to ROUND(..., 3)
--    Fires via: trigger_update_shipping_unit_cost
--    (AFTER INSERT OR UPDATE on shipment_received)
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.calculate_shipping_per_unit()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_total_weight NUMERIC;
BEGIN
    -- 1. Anti-Recursion: Stop if we are already inside this trigger
    IF pg_trigger_depth() > 1 THEN RETURN NEW; END IF;

    -- 2. Calculate the TRUE Total Weight (Coffee LBS + Consumable UNITS)
    v_total_weight := (
        SELECT COALESCE(SUM(amount), 0)
        FROM coffee_inventory_purchased
        WHERE shipment_id = NEW.shipment_id
          AND facility_id = NEW.facility_id
    ) + (
        SELECT COALESCE(SUM(amount), 0)
        FROM consumable_inventory_purchased
        WHERE shipment_id = NEW.shipment_id
          AND facility_id = NEW.facility_id
    );

    -- 3. Update BOTH the Total Weight and the Cost Per Unit
    UPDATE shipment_received
    SET shipping_cost_unit = CASE
            WHEN v_total_weight > 0 THEN ROUND(NEW.shipping_cost / v_total_weight, 3)
            ELSE 0
        END,
        shipment_total_weight_units = v_total_weight
    WHERE shipment_id = NEW.shipment_id
      AND facility_id = NEW.facility_id;

    RETURN NEW;
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- C. Backfill existing rows
-- ═══════════════════════════════════════════════════════════════

UPDATE public.shipment_received
SET shipping_cost_unit = ROUND(
    CASE
        WHEN shipment_total_weight_units > 0
            THEN shipping_cost / shipment_total_weight_units
        ELSE 0
    END, 3)
WHERE shipping_cost_unit IS NOT NULL;
