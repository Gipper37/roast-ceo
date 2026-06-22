-- ============================================================================
-- Books-closed guard — protect booked/closed-period COGS from retroactive edits
-- ----------------------------------------------------------------------------
-- Today, editing an old purchase cost_lb/cost_unit silently rewrites
-- order_details.unit_cost_at_sale for ALL non-canceled past orders in the
-- shipment's date window (incl. Delivered), and re-values roast cost snapshots
-- — with no period-close protection. That's the standard ERP footgun (a typo
-- fix changes last quarter's margins). Industry + GAAP: booked COGS is
-- point-in-time immutable; corrections allowed only until the books close.
--
-- This adds ONE control: companies.books_closed_through (date, nullable).
-- NULL = nothing closed (current behavior). When set, the retroactive paths
-- SKIP anything dated on/before it:
--   • propagate_coffee_purchase_to_orders   — skip orders order_date <= close
--   • propagate_consumable_purchase_to_orders— skip orders order_date <= close
--   • backfill_order_unit_costs             — skip orders order_date <= close
--   • value_roast_lot_consumption           — freeze roasts roast_date <= close
-- Original point-in-time stamping at booking (handle_order_detail_logic) and
-- valuation of new roasts are unaffected (they're current-dated, > close).
-- ============================================================================

BEGIN;

-- 1. The control --------------------------------------------------------------
ALTER TABLE public.companies
    ADD COLUMN IF NOT EXISTS books_closed_through date;

COMMENT ON COLUMN public.companies.books_closed_through IS
  'Accounting close date. Retroactive COGS recalcs skip orders/roasts dated on/before this. NULL = nothing closed.';

-- 2. Coffee purchase-cost edit -> re-stamp past orders (now close-gated) ------
CREATE OR REPLACE FUNCTION public.propagate_coffee_purchase_to_orders()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_this_date  date;
    v_next_date  date;
    v_new_cost   numeric;
    v_rec        record;
BEGIN
    IF TG_OP = 'UPDATE' AND OLD.cost_lb IS NOT DISTINCT FROM NEW.cost_lb THEN
        RETURN NULL;
    END IF;
    IF COALESCE(NEW.cost_lb, 0) = 0 THEN RETURN NULL; END IF;

    SELECT sr.date_received INTO v_this_date
      FROM public.shipment_received sr
     WHERE sr.shipment_id = NEW.shipment_id
       AND COALESCE(sr.voided, false) = false
     LIMIT 1;
    IF v_this_date IS NULL THEN RETURN NULL; END IF;

    SELECT sr.date_received INTO v_next_date
      FROM public.coffee_inventory_purchased cp
      JOIN public.shipment_received sr ON sr.shipment_id = cp.shipment_id
     WHERE cp.origin        = NEW.origin
       AND cp.facility_id   = NEW.facility_id
       AND sr.date_received  IS NOT NULL
       AND sr.date_received   > v_this_date
       AND cp.origin_purchase_id != NEW.origin_purchase_id
       AND COALESCE(sr.voided, false) = false
     ORDER BY sr.date_received ASC
     LIMIT 1;

    FOR v_rec IN
        SELECT DISTINCT od.order_detail_id, od.product_id, od.facility_id,
                        od.order_date, od.quantity
          FROM public.order_details od
          JOIN public.orders o          ON o.order_id   = od.order_id
          JOIN public.products p        ON p.product_id = od.product_id
          JOIN public.recipe_components rc
               ON rc.recipe_id   = p.recipe_id AND rc.facility_id = od.facility_id
          JOIN public.companies cmp     ON cmp.company_id = od.company_id
         WHERE o.order_status    != 'Canceled'
           AND od.order_date     >= v_this_date
           AND (v_next_date IS NULL OR od.order_date < v_next_date)
           AND od.order_date      > COALESCE(cmp.books_closed_through, '-infinity'::date)  -- books-closed guard
           AND rc.coffee_item     = NEW.origin
           AND COALESCE(od.quantity, 0) > 0
    LOOP
        v_new_cost := public.get_product_cogs_on_date(v_rec.product_id, v_rec.facility_id, v_rec.order_date);
        IF v_new_cost IS NOT NULL AND v_new_cost > 0 THEN
            UPDATE public.order_details
               SET unit_cost_at_sale = v_new_cost * v_rec.quantity, updated_at = now()
             WHERE order_detail_id = v_rec.order_detail_id;
        END IF;
    END LOOP;
    RETURN NULL;
END;
$function$;

-- 3. Consumable purchase-cost edit -> re-stamp past orders (now close-gated) --
CREATE OR REPLACE FUNCTION public.propagate_consumable_purchase_to_orders()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_this_date  date;
    v_next_date  date;
    v_new_cost   numeric;
    v_rec        record;
BEGIN
    IF TG_OP = 'UPDATE' AND OLD.cost_unit IS NOT DISTINCT FROM NEW.cost_unit THEN
        RETURN NULL;
    END IF;
    IF COALESCE(NEW.cost_unit, 0) = 0 THEN RETURN NULL; END IF;

    SELECT sr.date_received INTO v_this_date
      FROM public.shipment_received sr
     WHERE sr.shipment_id = NEW.shipment_id
       AND COALESCE(sr.voided, false) = false
     LIMIT 1;
    IF v_this_date IS NULL THEN RETURN NULL; END IF;

    SELECT sr.date_received INTO v_next_date
      FROM public.consumable_inventory_purchased cp
      JOIN public.shipment_received sr ON sr.shipment_id = cp.shipment_id
     WHERE cp.consumable_inventory_item = NEW.consumable_inventory_item
       AND cp.facility_id               = NEW.facility_id
       AND sr.date_received              IS NOT NULL
       AND sr.date_received               > v_this_date
       AND cp.consumable_purchase_id    != NEW.consumable_purchase_id
       AND COALESCE(sr.voided, false) = false
     ORDER BY sr.date_received ASC
     LIMIT 1;

    FOR v_rec IN
        SELECT DISTINCT od.order_detail_id, od.product_id, od.facility_id,
                        od.order_date, od.quantity
          FROM public.order_details od
          JOIN public.orders o           ON o.order_id   = od.order_id
          JOIN public.product_consumables pc
               ON pc.product_id  = od.product_id AND pc.facility_id = od.facility_id
          JOIN public.companies cmp      ON cmp.company_id = od.company_id
         WHERE o.order_status    != 'Canceled'
           AND od.order_date     >= v_this_date
           AND (v_next_date IS NULL OR od.order_date < v_next_date)
           AND od.order_date      > COALESCE(cmp.books_closed_through, '-infinity'::date)  -- books-closed guard
           AND pc.consumable_id   = NEW.consumable_inventory_item
           AND COALESCE(od.quantity, 0) > 0
    LOOP
        v_new_cost := public.get_product_cogs_on_date(v_rec.product_id, v_rec.facility_id, v_rec.order_date);
        IF v_new_cost IS NOT NULL AND v_new_cost > 0 THEN
            UPDATE public.order_details
               SET unit_cost_at_sale = v_new_cost * v_rec.quantity, updated_at = now()
             WHERE order_detail_id = v_rec.order_detail_id;
        END IF;
    END LOOP;
    RETURN NULL;
END;
$function$;

-- 4. Bulk re-stamp helper (now close-gated) ----------------------------------
CREATE OR REPLACE FUNCTION public.backfill_order_unit_costs(p_from_date date DEFAULT NULL::date, p_to_date date DEFAULT NULL::date, p_facility_id text DEFAULT NULL::text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_count    integer := 0;
    v_new_cost numeric;
    v_rec      record;
BEGIN
    FOR v_rec IN
        SELECT od.order_detail_id, od.product_id, od.facility_id, od.order_date, od.quantity
          FROM public.order_details od
          JOIN public.orders o      ON o.order_id    = od.order_id
          JOIN public.companies cmp ON cmp.company_id = od.company_id
         WHERE o.order_status    != 'Canceled'
           AND COALESCE(od.quantity, 0) > 0
           AND od.order_date      > COALESCE(cmp.books_closed_through, '-infinity'::date)  -- books-closed guard
           AND (p_from_date   IS NULL OR od.order_date >= p_from_date)
           AND (p_to_date     IS NULL OR od.order_date <= p_to_date)
           AND (p_facility_id IS NULL OR od.facility_id = p_facility_id)
    LOOP
        v_new_cost := public.get_product_cogs_on_date(v_rec.product_id, v_rec.facility_id, v_rec.order_date);
        IF v_new_cost IS NOT NULL AND v_new_cost > 0 THEN
            UPDATE public.order_details
               SET unit_cost_at_sale = v_new_cost * v_rec.quantity, updated_at = now()
             WHERE order_detail_id = v_rec.order_detail_id;
            v_count := v_count + 1;
        END IF;
    END LOOP;
    RETURN v_count;
END;
$function$;

-- 5. Roast valuation: freeze closed-period roasts ----------------------------
-- (Re-paste of the Step-2 version + a books-closed short-circuit at the top.)
CREATE OR REPLACE FUNCTION public.value_roast_lot_consumption(p_roast_log_id text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_total_green numeric;
    v_roasted_lbs numeric;
    v_facility    text;
    v_origin      text;
    v_new_cost    numeric;
    v_roast_date  date;
    v_closed      date;
BEGIN
    -- Books-closed guard: freeze a roast's cost once its period is closed.
    SELECT rl.roast_date, c.books_closed_through
      INTO v_roast_date, v_closed
      FROM public.roast_log rl
      LEFT JOIN public.companies c ON c.company_id = rl.company_id
     WHERE rl.roast_log_id = p_roast_log_id;
    IF v_closed IS NOT NULL AND v_roast_date IS NOT NULL AND v_roast_date <= v_closed THEN
        RETURN;
    END IF;

    -- a. snapshot each ledger row's green + shipping cost from its lot
    UPDATE public.roast_log_lot_consumption rlc
    SET green_cost_lb    = cip.cost_lb,
        shipping_cost_lb = COALESCE(sr.shipping_cost_unit, 0)
    FROM public.coffee_inventory_purchased cip
    LEFT JOIN public.shipment_received sr ON sr.shipment_id = cip.shipment_id
    WHERE rlc.roast_log_id = p_roast_log_id
      AND cip.origin_purchase_id = rlc.origin_purchase_id;

    -- b. roll up to roast_log (NULL when no ledger rows)
    SELECT SUM(lot_cost)
      INTO v_total_green
      FROM public.roast_log_lot_consumption
     WHERE roast_log_id = p_roast_log_id;

    SELECT COALESCE(rl.measured_roasted_weight,
                    rl.roasted_weight,
                    rl.charge_weight_lbs * COALESCE(public.get_retention_factor(rl.facility_id, rl.recipe_id), 0.82)),
           rl.facility_id
      INTO v_roasted_lbs, v_facility
      FROM public.roast_log rl
     WHERE rl.roast_log_id = p_roast_log_id;

    UPDATE public.roast_log rl
    SET green_cost      = v_total_green,
        roasted_cost_lb = CASE WHEN v_total_green IS NOT NULL AND COALESCE(v_roasted_lbs,0) > 0
                               THEN v_total_green / v_roasted_lbs
                               ELSE NULL END
    WHERE rl.roast_log_id = p_roast_log_id;

    -- c. refresh cached per-origin roasted cost (once per origin)
    FOR v_origin IN
        SELECT DISTINCT cip.origin
          FROM public.roast_log_lot_consumption rlc
          JOIN public.coffee_inventory_purchased cip ON cip.origin_purchase_id = rlc.origin_purchase_id
         WHERE rlc.roast_log_id = p_roast_log_id
    LOOP
        v_new_cost := public.get_origin_roasted_cost_on_date(v_origin, v_facility, CURRENT_DATE);
        UPDATE public.coffee_inventory ci
        SET latest_roasted_cost = v_new_cost
        WHERE ci.origin_id   = v_origin
          AND ci.facility_id = v_facility
          AND ci.latest_roasted_cost IS DISTINCT FROM v_new_cost;
    END LOOP;
END;
$$;

COMMIT;
