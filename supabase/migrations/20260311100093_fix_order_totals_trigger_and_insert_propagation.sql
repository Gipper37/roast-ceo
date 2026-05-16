-- Migration 00093: Fix order-totals cascade + extend propagation to INSERT
--
-- Fix 1: trg_update_order_totals WHEN clause
--   The existing trigger fires AFTER INSERT OR DELETE OR UPDATE on order_details
--   for ANY change. This causes an unnecessary cascade: when backfill_order_unit_costs()
--   updates unit_cost_at_sale, the trigger fires → update_order_aggregates() runs →
--   touches orders.order_total (unchanged) → fires update_customer_metrics_on_order()
--   → tries to UPDATE customers → hits FK violation on bad state data.
--
--   Fix: add a WHEN clause so the UPDATE path only fires when total_price or
--   roasted_weight actually changes. INSERT and DELETE still always fire.
--   (On INSERT, OLD.total_price IS NULL → DISTINCT from NEW.total_price → fires.)
--   (On DELETE, NEW.total_price IS NULL → DISTINCT from OLD.total_price → fires.)
--   (On UPDATE changing only unit_cost_at_sale → same total_price → does NOT fire.)
--
-- Fix 2: Extend auto-propagation triggers to INSERT
--   The triggers added in migration 00092 only fire on UPDATE of purchase cost
--   columns. If a user adds a BRAND NEW historical purchase record (INSERT) for
--   a date that already has orders, those orders won't be swept automatically.
--
--   Fix: change both triggers to fire on INSERT OR UPDATE. The functions now
--   check TG_OP and skip the "did cost change?" guard on INSERT (all inserts
--   with a cost and a received shipment should trigger a sweep).


-- ===========================================================================
-- FIX 1: Add WHEN clause to trg_update_order_totals
--
-- PostgreSQL requires separate triggers for INSERT/DELETE vs UPDATE when
-- using a WHEN clause that references OLD (OLD doesn't exist on INSERT).
--
-- Split into two triggers:
--   trg_update_order_totals_ins_del — INSERT OR DELETE, always fires
--   trg_update_order_totals_upd     — UPDATE only, fires when total_price
--                                     or roasted_weight actually changes
-- ===========================================================================

DROP TRIGGER IF EXISTS trg_update_order_totals ON public.order_details;

-- INSERT and DELETE always need to recalculate order totals
CREATE TRIGGER trg_update_order_totals_ins_del
    AFTER INSERT OR DELETE ON public.order_details
    FOR EACH ROW
    EXECUTE FUNCTION public.update_order_aggregates();

-- UPDATE only fires when the aggregated columns actually changed
-- (not when only unit_cost_at_sale or other non-aggregate columns change)
CREATE TRIGGER trg_update_order_totals_upd
    AFTER UPDATE ON public.order_details
    FOR EACH ROW
    WHEN (
        OLD.total_price      IS DISTINCT FROM NEW.total_price
        OR OLD.roasted_weight IS DISTINCT FROM NEW.roasted_weight
    )
    EXECUTE FUNCTION public.update_order_aggregates();


-- ===========================================================================
-- FIX 2: Update coffee propagation to handle INSERT
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

-- Drop old trigger and recreate for INSERT OR UPDATE
DROP TRIGGER IF EXISTS trg_propagate_coffee_purchase_cost_to_orders ON public.coffee_inventory_purchased;

CREATE TRIGGER trg_propagate_coffee_purchase_cost_to_orders
    AFTER INSERT OR UPDATE OF cost_lb ON public.coffee_inventory_purchased
    FOR EACH ROW EXECUTE FUNCTION public.propagate_coffee_purchase_to_orders();


-- ===========================================================================
-- FIX 2b: Update consumable propagation to handle INSERT
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

-- Drop old trigger and recreate for INSERT OR UPDATE
DROP TRIGGER IF EXISTS trg_propagate_consumable_purchase_cost_to_orders ON public.consumable_inventory_purchased;

CREATE TRIGGER trg_propagate_consumable_purchase_cost_to_orders
    AFTER INSERT OR UPDATE OF cost_unit ON public.consumable_inventory_purchased
    FOR EACH ROW EXECUTE FUNCTION public.propagate_consumable_purchase_to_orders();
