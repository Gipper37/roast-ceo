-- Migration: Fix calculate_shipment_totals() to handle DELETE operations
--
-- Issue 5: The function fires on INSERT OR DELETE OR UPDATE but uses NEW.shipment_id
-- and NEW.facility_id throughout. On DELETE, NEW is NULL — causing the WHERE clauses
-- to silently match nothing and shipment totals to never recalculate after a line
-- item is removed.
--
-- Fix: Detect TG_OP and use OLD values on DELETE, NEW values otherwise.

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
            WHEN v_total_weight > 0 THEN shipping_cost / v_total_weight
            ELSE 0
        END
    WHERE shipment_id = v_shipment_id
      AND facility_id = v_facility_id;

    -- 3. Return appropriate row (AFTER triggers ignore return value,
    --    but returning OLD/NEW correctly is best practice)
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$;
