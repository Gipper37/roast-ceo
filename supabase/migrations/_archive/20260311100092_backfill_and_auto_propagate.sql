-- Migration 00092: Order COGS backfill function + auto-propagation triggers
--
-- Part A: backfill_order_unit_costs() — on-demand function
--   Recalculates unit_cost_at_sale for all (or a filtered range of) orders
--   using point-in-time cost data from the shipment history. Call this once
--   after deploying 00090-00092 to fix the 5-year backlog of zero-cost orders.
--
-- Part B: propagate_coffee_purchase_to_orders() + trigger
--   AFTER UPDATE OF cost_lb on coffee_inventory_purchased.
--   When an old shipment's green cost is corrected, automatically finds all
--   orders in the effective date range and recalculates their unit_cost_at_sale.
--   Date range: [this shipment's date_received, next received shipment's date_received)
--
-- Part C: propagate_consumable_purchase_to_orders() + trigger
--   Same pattern for consumable_inventory_purchased.cost_unit changes.
--
-- IMPORTANT: These triggers fire on UPDATE only (editing an existing purchase row).
--   If you INSERT a brand-new historical purchase record, run
--   backfill_order_unit_costs() manually to sweep the affected date range.
--
-- All updates skip Canceled orders and only update when recalculated cost > 0.
-- Partial costs (e.g. coffee cost known but label cost unknown) are still
-- written — a partial cost is better than leaving the order at 0.


-- ===========================================================================
-- PART A: backfill_order_unit_costs
-- ===========================================================================

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
               od.order_date
          FROM public.order_details od
          JOIN public.orders o ON o.order_id = od.order_id
         WHERE o.order_status != 'Canceled'
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
               SET unit_cost_at_sale = v_new_cost,
                   updated_at        = now()
             WHERE order_detail_id = v_rec.order_detail_id;
            v_count := v_count + 1;
        END IF;
    END LOOP;

    RETURN v_count;
END;
$$;

COMMENT ON FUNCTION public.backfill_order_unit_costs(date, date, text) IS
    'Recalculates unit_cost_at_sale for orders using point-in-time shipment costs.
     Call with no arguments to sweep all orders: SELECT backfill_order_unit_costs();
     Returns count of rows updated. Skips Canceled orders and zero-result rows.';


-- ===========================================================================
-- PART B: Coffee purchase cost → order history auto-propagation
-- ===========================================================================

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
    -- Skip if cost_lb didn't actually change
    IF OLD.cost_lb IS NOT DISTINCT FROM NEW.cost_lb THEN
        RETURN NULL;
    END IF;

    -- Get the date_received for THIS specific shipment
    SELECT sr.date_received
      INTO v_this_date
      FROM public.shipment_received sr
     WHERE sr.shipment_id = NEW.shipment_id
     LIMIT 1;

    -- If shipment hasn't been received yet (date_received IS NULL), skip
    -- Costs for in-transit shipments shouldn't backfill historical orders
    IF v_this_date IS NULL THEN
        RETURN NULL;
    END IF;

    -- Find the NEXT received shipment for this origin + facility
    -- This defines the upper bound of the date range we need to sweep
    SELECT sr.date_received
      INTO v_next_date
      FROM public.coffee_inventory_purchased cp
      JOIN public.shipment_received sr ON sr.shipment_id = cp.shipment_id
     WHERE cp.origin        = NEW.origin
       AND cp.facility_id   = NEW.facility_id
       AND sr.date_received  IS NOT NULL
       AND sr.date_received   > v_this_date
     ORDER BY sr.date_received ASC
     LIMIT 1;

    -- Sweep order_details in [v_this_date, v_next_date)
    -- v_next_date IS NULL means this is the most recent shipment → sweep to present
    FOR v_rec IN
        SELECT DISTINCT od.order_detail_id,
                        od.product_id,
                        od.facility_id,
                        od.order_date
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
    LOOP
        v_new_cost := public.get_product_cogs_on_date(
            v_rec.product_id,
            v_rec.facility_id,
            v_rec.order_date
        );

        IF v_new_cost IS NOT NULL AND v_new_cost > 0 THEN
            UPDATE public.order_details
               SET unit_cost_at_sale = v_new_cost,
                   updated_at        = now()
             WHERE order_detail_id = v_rec.order_detail_id;
        END IF;
    END LOOP;

    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_propagate_coffee_purchase_cost_to_orders
    AFTER UPDATE OF cost_lb ON public.coffee_inventory_purchased
    FOR EACH ROW EXECUTE FUNCTION public.propagate_coffee_purchase_to_orders();


-- ===========================================================================
-- PART C: Consumable purchase cost → order history auto-propagation
-- ===========================================================================

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
    -- Skip if cost_unit didn't actually change
    IF OLD.cost_unit IS NOT DISTINCT FROM NEW.cost_unit THEN
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
     ORDER BY sr.date_received ASC
     LIMIT 1;

    -- Sweep order_details in [v_this_date, v_next_date)
    FOR v_rec IN
        SELECT DISTINCT od.order_detail_id,
                        od.product_id,
                        od.facility_id,
                        od.order_date
          FROM public.order_details od
          JOIN public.orders o           ON o.order_id   = od.order_id
          JOIN public.product_consumables pc
               ON pc.product_id  = od.product_id
              AND pc.facility_id = od.facility_id
         WHERE o.order_status    != 'Canceled'
           AND od.order_date     >= v_this_date
           AND (v_next_date IS NULL OR od.order_date < v_next_date)
           AND pc.consumable_id   = NEW.consumable_inventory_item
    LOOP
        v_new_cost := public.get_product_cogs_on_date(
            v_rec.product_id,
            v_rec.facility_id,
            v_rec.order_date
        );

        IF v_new_cost IS NOT NULL AND v_new_cost > 0 THEN
            UPDATE public.order_details
               SET unit_cost_at_sale = v_new_cost,
                   updated_at        = now()
             WHERE order_detail_id = v_rec.order_detail_id;
        END IF;
    END LOOP;

    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_propagate_consumable_purchase_cost_to_orders
    AFTER UPDATE OF cost_unit ON public.consumable_inventory_purchased
    FOR EACH ROW EXECUTE FUNCTION public.propagate_consumable_purchase_to_orders();
