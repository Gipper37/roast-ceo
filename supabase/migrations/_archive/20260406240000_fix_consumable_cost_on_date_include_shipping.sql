-- Fix get_consumable_cost_on_date to include shipping_cost_unit from shipment_received.
-- Previously only used cp.cost_unit, ignoring per-unit shipping — same bug as
-- update_last_consumable_cost (fixed in 20260406230000).

CREATE OR REPLACE FUNCTION get_consumable_cost_on_date(
    p_consumable_id TEXT,
    p_facility_id   TEXT,
    p_order_date    DATE
)
RETURNS NUMERIC
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_cost numeric;
BEGIN
    -- Priority 1: Most recent non-voided received shipment on or before order date
    SELECT cp.cost_unit + COALESCE(sr.shipping_cost_unit, 0)
      INTO v_cost
      FROM public.consumable_inventory_purchased cp
      JOIN public.shipment_received sr ON sr.shipment_id = cp.shipment_id
     WHERE cp.consumable_inventory_item = p_consumable_id
       AND cp.facility_id               = p_facility_id
       AND cp.cost_unit                  > 0
       AND sr.date_received IS NOT NULL
       AND sr.date_received             <= p_order_date
       AND COALESCE(sr.voided, false) = false
     ORDER BY sr.date_received DESC, cp.created_at DESC
     LIMIT 1;

    IF v_cost IS NOT NULL THEN RETURN v_cost; END IF;

    -- Priority 2: Earliest non-voided received shipment (forward fallback)
    SELECT cp.cost_unit + COALESCE(sr.shipping_cost_unit, 0)
      INTO v_cost
      FROM public.consumable_inventory_purchased cp
      JOIN public.shipment_received sr ON sr.shipment_id = cp.shipment_id
     WHERE cp.consumable_inventory_item = p_consumable_id
       AND cp.facility_id               = p_facility_id
       AND cp.cost_unit                  > 0
       AND sr.date_received IS NOT NULL
       AND COALESCE(sr.voided, false) = false
     ORDER BY sr.date_received ASC, cp.created_at ASC
     LIMIT 1;

    IF v_cost IS NOT NULL THEN RETURN v_cost; END IF;

    -- Priority 3: User-entered fallback cost
    RETURN (
        SELECT fallback_unit_cost FROM public.consumable_inventory
         WHERE consumable_inventory_id = p_consumable_id LIMIT 1
    );
END;
$$;

-- Backfill: recompute unit_cost_at_sale for all non-canceled order_details
-- now that get_consumable_cost_on_date (called inside get_product_cogs_on_date)
-- correctly includes shipping. Uses session_replication_role = replica to
-- suppress audit triggers and avoid bumping updated_at on unrelated columns.
DO $$
DECLARE
    v_rec      RECORD;
    v_new_cost NUMERIC;
BEGIN
    SET session_replication_role = replica;

    FOR v_rec IN
        SELECT od.order_detail_id, od.product_id, od.facility_id,
               od.order_date, od.quantity
          FROM public.order_details od
          JOIN public.orders o ON o.order_id = od.order_id
         WHERE o.order_status != 'Canceled'
           AND COALESCE(od.quantity, 0) > 0
    LOOP
        v_new_cost := public.get_product_cogs_on_date(
            v_rec.product_id, v_rec.facility_id, v_rec.order_date
        );

        IF v_new_cost IS NOT NULL AND v_new_cost > 0 THEN
            UPDATE public.order_details
               SET unit_cost_at_sale = v_new_cost * v_rec.quantity
             WHERE order_detail_id = v_rec.order_detail_id;
        END IF;
    END LOOP;

    SET session_replication_role = DEFAULT;
END;
$$;
