-- Fix update_last_consumable_cost to include shipping_cost_unit from shipment_received
-- Previously only used cost_unit, ignoring per-unit shipping cost on the shipment.
-- Landed cost = cost_unit + shipping_cost_unit

CREATE OR REPLACE FUNCTION update_last_consumable_cost()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_item_id       TEXT;
    v_facility_id   TEXT;
    v_latest_cost   NUMERIC;
    v_fallback_cost NUMERIC;
BEGIN
    v_item_id     := COALESCE(NEW.consumable_inventory_item, OLD.consumable_inventory_item);
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    -- Most recent landed cost (unit price + per-unit shipping) from non-voided shipment
    SELECT cp.cost_unit::numeric + COALESCE(sr.shipping_cost_unit, 0)
    INTO   v_latest_cost
    FROM   consumable_inventory_purchased cp
    LEFT JOIN shipment_received sr ON cp.shipment_id = sr.shipment_id
    WHERE  cp.consumable_inventory_item = v_item_id
      AND  cp.facility_id = v_facility_id
      AND  cp.cost_unit IS NOT NULL
      AND  cp.cost_unit::text <> ''
      AND  cp.cost_unit::numeric > 0
      AND  COALESCE(sr.voided, false) = false
    ORDER BY sr.date_received DESC NULLS LAST, cp.created_at DESC
    LIMIT 1;

    IF v_latest_cost IS NOT NULL THEN
        UPDATE consumable_inventory
        SET    last_cost_unit = v_latest_cost, updated_at = NOW()
        WHERE  consumable_inventory_id = v_item_id AND facility_id = v_facility_id;
    ELSE
        SELECT fallback_unit_cost INTO v_fallback_cost
        FROM   consumable_inventory
        WHERE  consumable_inventory_id = v_item_id AND facility_id = v_facility_id;

        IF COALESCE(v_fallback_cost, 0) > 0 THEN
            UPDATE consumable_inventory
            SET    last_cost_unit = v_fallback_cost, updated_at = NOW()
            WHERE  consumable_inventory_id = v_item_id AND facility_id = v_facility_id;
        END IF;
    END IF;

    RETURN NULL;
END;
$$;

-- Backfill: recompute last_cost_unit for all consumable inventory items
-- using the corrected landed cost (unit + shipping).
-- Updating last_cost_unit fires trg_propagate_consumable_cost which cascades
-- through to product COGS automatically.
DO $$
DECLARE
    r             RECORD;
    v_latest_cost NUMERIC;
BEGIN
    FOR r IN
        SELECT DISTINCT consumable_inventory_item, facility_id
        FROM consumable_inventory_purchased
        WHERE consumable_inventory_item IS NOT NULL
    LOOP
        SELECT cp.cost_unit::numeric + COALESCE(sr.shipping_cost_unit, 0)
        INTO   v_latest_cost
        FROM   consumable_inventory_purchased cp
        LEFT JOIN shipment_received sr ON cp.shipment_id = sr.shipment_id
        WHERE  cp.consumable_inventory_item = r.consumable_inventory_item
          AND  cp.facility_id = r.facility_id
          AND  cp.cost_unit IS NOT NULL
          AND  cp.cost_unit::text <> ''
          AND  cp.cost_unit::numeric > 0
          AND  COALESCE(sr.voided, false) = false
        ORDER BY sr.date_received DESC NULLS LAST, cp.created_at DESC
        LIMIT 1;

        IF v_latest_cost IS NOT NULL THEN
            UPDATE consumable_inventory
            SET    last_cost_unit = v_latest_cost, updated_at = NOW()
            WHERE  consumable_inventory_id = r.consumable_inventory_item
              AND  facility_id = r.facility_id;
        END IF;
    END LOOP;
END;
$$;
