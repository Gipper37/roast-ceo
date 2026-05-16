-- Migration 00125: Fix unit_cost_at_sale missing quantity multiplication in propagation functions
--
-- Bug: propagate_coffee_purchase_to_orders, propagate_consumable_purchase_to_orders,
-- and backfill_order_unit_costs all called get_product_cogs_on_date() which returns
-- PER-UNIT COGS, then wrote that directly to unit_cost_at_sale without multiplying by
-- quantity. handle_order_detail_logic correctly does quantity × cogs, so orders placed
-- while costs were live were fine — but any order retroactively filled by these functions
-- got only the per-unit cost, tanking COGS% for high-quantity rows to near zero.
--
-- Fix: include quantity in the loop SELECT and multiply before writing unit_cost_at_sale.
-- Then run a full backfill to correct all historical rows immediately.

-- ── 1. propagate_coffee_purchase_to_orders ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.propagate_coffee_purchase_to_orders()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_this_date  date;
    v_next_date  date;
    v_new_cost   numeric;
    v_rec        record;
BEGIN
    -- On UPDATE: skip if cost_lb didn't actually change
    IF TG_OP = 'UPDATE' AND OLD.cost_lb IS NOT DISTINCT FROM NEW.cost_lb THEN
        RETURN NULL;
    END IF;

    -- Skip rows with no cost (INSERT with cost_lb = 0 or NULL)
    IF COALESCE(NEW.cost_lb, 0) = 0 THEN
        RETURN NULL;
    END IF;

    -- Get the date_received for THIS specific shipment
    SELECT sr.date_received
      INTO v_this_date
      FROM public.shipment_received sr
     WHERE sr.shipment_id = NEW.shipment_id
     LIMIT 1;

    -- If shipment hasn't been received yet (date_received IS NULL), skip
    IF v_this_date IS NULL THEN
        RETURN NULL;
    END IF;

    -- Find the NEXT received shipment for this origin + facility
    SELECT sr.date_received
      INTO v_next_date
      FROM public.coffee_inventory_purchased cp
      JOIN public.shipment_received sr ON sr.shipment_id = cp.shipment_id
     WHERE cp.origin        = NEW.origin
       AND cp.facility_id   = NEW.facility_id
       AND sr.date_received  IS NOT NULL
       AND sr.date_received   > v_this_date
       AND cp.origin_purchase_id != NEW.origin_purchase_id  -- exclude self
     ORDER BY sr.date_received ASC
     LIMIT 1;

    -- Sweep order_details in [v_this_date, v_next_date)
    FOR v_rec IN
        SELECT DISTINCT od.order_detail_id,
                        od.product_id,
                        od.facility_id,
                        od.order_date,
                        od.quantity
          FROM public.order_details od
          JOIN public.orders o          ON o.order_id   = od.order_id
          JOIN public.products p        ON p.product_id = od.product_id
          JOIN public.recipe_components rc
               ON rc.recipe_id   = p.recipe_id
              AND rc.facility_id = od.facility_id
         WHERE o.order_status    != 'Canceled'
           AND od.order_date     >= v_this_date
           AND (v_next_date IS NULL OR od.order_date < v_next_date)
           AND rc.coffee_item     = NEW.origin
           AND COALESCE(od.quantity, 0) > 0
    LOOP
        v_new_cost := public.get_product_cogs_on_date(
            v_rec.product_id,
            v_rec.facility_id,
            v_rec.order_date
        );

        IF v_new_cost IS NOT NULL AND v_new_cost > 0 THEN
            UPDATE public.order_details
               SET unit_cost_at_sale = v_new_cost * v_rec.quantity,
                   updated_at        = now()
             WHERE order_detail_id = v_rec.order_detail_id;
        END IF;
    END LOOP;

    RETURN NULL;
END;
$$;

-- ── 2. propagate_consumable_purchase_to_orders ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public.propagate_consumable_purchase_to_orders()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_this_date  date;
    v_next_date  date;
    v_new_cost   numeric;
    v_rec        record;
BEGIN
    -- On UPDATE: skip if cost_unit didn't actually change
    IF TG_OP = 'UPDATE' AND OLD.cost_unit IS NOT DISTINCT FROM NEW.cost_unit THEN
        RETURN NULL;
    END IF;

    -- Skip rows with no cost
    IF COALESCE(NEW.cost_unit, 0) = 0 THEN
        RETURN NULL;
    END IF;

    -- Get the date_received for THIS specific shipment
    SELECT sr.date_received
      INTO v_this_date
      FROM public.shipment_received sr
     WHERE sr.shipment_id = NEW.shipment_id
     LIMIT 1;

    -- If shipment hasn't been received yet, skip
    IF v_this_date IS NULL THEN
        RETURN NULL;
    END IF;

    -- Find the NEXT received shipment for this consumable + facility
    SELECT sr.date_received
      INTO v_next_date
      FROM public.consumable_inventory_purchased cp
      JOIN public.shipment_received sr ON sr.shipment_id = cp.shipment_id
     WHERE cp.consumable_inventory_item = NEW.consumable_inventory_item
       AND cp.facility_id               = NEW.facility_id
       AND sr.date_received              IS NOT NULL
       AND sr.date_received               > v_this_date
       AND cp.consumable_purchase_id    != NEW.consumable_purchase_id  -- exclude self
     ORDER BY sr.date_received ASC
     LIMIT 1;

    -- Sweep order_details in [v_this_date, v_next_date)
    FOR v_rec IN
        SELECT DISTINCT od.order_detail_id,
                        od.product_id,
                        od.facility_id,
                        od.order_date,
                        od.quantity
          FROM public.order_details od
          JOIN public.orders o           ON o.order_id   = od.order_id
          JOIN public.product_consumables pc
               ON pc.product_id  = od.product_id
              AND pc.facility_id = od.facility_id
         WHERE o.order_status    != 'Canceled'
           AND od.order_date     >= v_this_date
           AND (v_next_date IS NULL OR od.order_date < v_next_date)
           AND pc.consumable_id   = NEW.consumable_inventory_item
           AND COALESCE(od.quantity, 0) > 0
    LOOP
        v_new_cost := public.get_product_cogs_on_date(
            v_rec.product_id,
            v_rec.facility_id,
            v_rec.order_date
        );

        IF v_new_cost IS NOT NULL AND v_new_cost > 0 THEN
            UPDATE public.order_details
               SET unit_cost_at_sale = v_new_cost * v_rec.quantity,
                   updated_at        = now()
             WHERE order_detail_id = v_rec.order_detail_id;
        END IF;
    END LOOP;

    RETURN NULL;
END;
$$;

-- ── 3. backfill_order_unit_costs ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.backfill_order_unit_costs(
    p_from_date   date DEFAULT NULL,
    p_to_date     date DEFAULT NULL,
    p_facility_id text DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    v_count    integer := 0;
    v_new_cost numeric;
    v_rec      record;
BEGIN
    FOR v_rec IN
        SELECT od.order_detail_id,
               od.product_id,
               od.facility_id,
               od.order_date,
               od.quantity
          FROM public.order_details od
          JOIN public.orders o ON o.order_id = od.order_id
         WHERE o.order_status    != 'Canceled'
           AND COALESCE(od.quantity, 0) > 0
           AND (p_from_date   IS NULL OR od.order_date >= p_from_date)
           AND (p_to_date     IS NULL OR od.order_date <= p_to_date)
           AND (p_facility_id IS NULL OR od.facility_id = p_facility_id)
    LOOP
        v_new_cost := public.get_product_cogs_on_date(
            v_rec.product_id,
            v_rec.facility_id,
            v_rec.order_date
        );

        IF v_new_cost IS NOT NULL AND v_new_cost > 0 THEN
            UPDATE public.order_details
               SET unit_cost_at_sale = v_new_cost * v_rec.quantity,
                   updated_at        = now()
             WHERE order_detail_id = v_rec.order_detail_id;
            v_count := v_count + 1;
        END IF;
    END LOOP;

    RETURN v_count;
END;
$$;

-- ── 4. Run full backfill to correct all historical rows immediately ───────────────────
DO $$
DECLARE
    v_updated integer;
BEGIN
    SELECT public.backfill_order_unit_costs(NULL, NULL, NULL) INTO v_updated;
    RAISE NOTICE 'backfill_order_unit_costs updated % rows', v_updated;
END;
$$;
