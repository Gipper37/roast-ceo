-- Add voided flag to shipment_received
ALTER TABLE public.shipment_received
  ADD COLUMN IF NOT EXISTS voided boolean NOT NULL DEFAULT false;

-- ── 1. calculate_current_stock_lbs ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.calculate_current_stock_lbs(p_origin_id text, p_facility_id text)
RETURNS numeric LANGUAGE plpgsql AS $$
DECLARE
    v_purchased_lbs       NUMERIC;
    v_starting_lbs        NUMERIC;
    v_bag_size            NUMERIC;
    v_inventory_bags      NUMERIC;
    v_last_inventory_date DATE;
    v_roasted_direct_lbs  NUMERIC;
    v_roasted_blend_lbs   NUMERIC;
BEGIN
    -- 1. Bag size (text → numeric)
    SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
    FROM coffee_inventory
    WHERE origin_id = p_origin_id AND facility_id = p_facility_id
    LIMIT 1;

    -- 2. Baseline
    SELECT last_inventory::DATE, COALESCE(inventory_count_bags, 0)
    INTO v_last_inventory_date, v_inventory_bags
    FROM coffee_inventory
    WHERE origin_id = p_origin_id AND facility_id = p_facility_id;

    IF v_last_inventory_date IS NULL THEN
        v_last_inventory_date := '2000-01-01';
    END IF;

    v_starting_lbs := v_inventory_bags * v_bag_size;

    -- 3. Inflow: received, non-voided purchases
    SELECT COALESCE(SUM(p.amount), 0) INTO v_purchased_lbs
    FROM coffee_inventory_purchased p
    JOIN shipment_received s ON p.shipment_id = s.shipment_id
    WHERE p.origin = p_origin_id
      AND s.date_received::DATE > v_last_inventory_date
      AND s.date_received IS NOT NULL
      AND COALESCE(s.voided, false) = false
      AND p.facility_id = p_facility_id;

    -- 4. Outflow A: direct roasts
    SELECT COALESCE(SUM(rl.charge_weight), 0) INTO v_roasted_direct_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    WHERE rl.origin_id = p_origin_id
      AND rl.roast_date::DATE > v_last_inventory_date
      AND rl."charged?" = TRUE
      AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend')
      AND rl.facility_id = p_facility_id;

    -- 5. Outflow B: blend roasts
    SELECT COALESCE(SUM(rl.charge_weight * rc.percentage), 0) INTO v_roasted_blend_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
    WHERE rc.coffee_item = p_origin_id
      AND rr.roast_type = 'Pre-Blend'
      AND rl.roast_date::DATE > v_last_inventory_date
      AND rl."charged?" = TRUE
      AND rl.facility_id = p_facility_id;

    -- 6. Result
    RETURN GREATEST(0, (v_starting_lbs + v_purchased_lbs - v_roasted_direct_lbs - v_roasted_blend_lbs));
END;
$$;

-- ── 2. calculate_current_stock_consumables ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.calculate_current_stock_consumables(p_consumable_id text, p_facility_id text)
RETURNS numeric LANGUAGE plpgsql AS $$
DECLARE
    v_last_inventory_date DATE;
    v_inventory_count     NUMERIC;
    v_purchased_amount    NUMERIC;
    v_usage_amount        NUMERIC;
BEGIN
    -- 1. Baseline
    SELECT last_inventory_date, COALESCE(inventory_count, 0)
    INTO v_last_inventory_date, v_inventory_count
    FROM consumable_inventory
    WHERE consumable_inventory_id = p_consumable_id
      AND facility_id = p_facility_id;
    IF v_last_inventory_date IS NULL THEN v_last_inventory_date := '2000-01-01'; END IF;

    -- 2. Additions (received, non-voided shipments only)
    SELECT COALESCE(SUM(amount), 0)
    INTO v_purchased_amount
    FROM consumable_inventory_purchased cp
    JOIN shipment_received sr ON cp.shipment_id = sr.shipment_id
    WHERE cp.consumable_inventory_item = p_consumable_id
      AND sr.date_received > v_last_inventory_date
      AND sr.date_received IS NOT NULL
      AND COALESCE(sr.voided, false) = false
      AND cp.facility_id = p_facility_id;

    -- 3. Subtractions (non-canceled orders)
    SELECT COALESCE(SUM(od.quantity * pc.quantity), 0)
    INTO v_usage_amount
    FROM order_details od
    JOIN orders o ON od.order_id = o.order_id
    JOIN product_consumables pc ON od.product_id = pc.product_id
    WHERE pc.consumable_id = p_consumable_id
      AND o.order_date::DATE > v_last_inventory_date
      AND o.order_status != 'Canceled'
      AND o.facility_id = p_facility_id;

    RETURN GREATEST(0, (v_inventory_count + v_purchased_amount - v_usage_amount));
END;
$$;

-- ── 3. recalculate_inventory_cost ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.recalculate_inventory_cost(p_origin_id text, p_facility_id text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_retention             numeric;
    v_latest_green_cost     numeric;
    v_latest_shipping_cost  numeric;
    v_final_landed_cost     numeric;
    v_fallback_cost         numeric;
BEGIN
    -- 1. Resolve retention factor (3-tier)
    SELECT value_number
      INTO v_retention
    FROM company_parameters
    WHERE parameter_id = '1de271df'
      AND facility_id = p_facility_id
    LIMIT 1;

    IF v_retention IS NULL OR v_retention = 0 THEN
      SELECT sp.amount
        INTO v_retention
      FROM standard_parameters sp
      WHERE sp.parameters_id = '1de271df'
      LIMIT 1;
    END IF;

    IF v_retention IS NULL OR v_retention = 0 THEN
      v_retention := 0.82;
    END IF;

    -- 2. Weighted average green cost from most recent non-voided shipment
    WITH latest_shipment AS (
        SELECT cp.shipment_id
        FROM coffee_inventory_purchased cp
        LEFT JOIN shipment_received sr ON cp.shipment_id = sr.shipment_id
        WHERE cp.origin        = p_origin_id
          AND cp.cost_lb       > 0
          AND cp.facility_id   = p_facility_id
          AND COALESCE(sr.voided, false) = false
        ORDER BY sr.date_received DESC NULLS LAST, cp.created_at DESC NULLS LAST
        LIMIT 1
    )
    SELECT
        SUM(cp.cost_lb * COALESCE(cp.amount, 0))
        / NULLIF(SUM(COALESCE(cp.amount, 0)), 0)
    INTO v_latest_green_cost
    FROM coffee_inventory_purchased cp
    JOIN latest_shipment ls
      ON (cp.shipment_id = ls.shipment_id)
      OR (cp.shipment_id IS NULL AND ls.shipment_id IS NULL)
    WHERE cp.origin      = p_origin_id
      AND cp.cost_lb     > 0
      AND cp.facility_id = p_facility_id;

    -- 3. Most recent non-voided shipment shipping cost
    SELECT sr.shipping_cost_unit
      INTO v_latest_shipping_cost
    FROM coffee_inventory_purchased cp
    LEFT JOIN shipment_received sr ON cp.shipment_id = sr.shipment_id
    WHERE cp.origin      = p_origin_id
      AND sr.shipping_cost_unit > 0
      AND cp.facility_id = p_facility_id
      AND COALESCE(sr.voided, false) = false
    ORDER BY sr.date_received DESC NULLS LAST, cp.created_at DESC NULLS LAST
    LIMIT 1;

    v_latest_green_cost    := COALESCE(v_latest_green_cost, 0);
    v_latest_shipping_cost := COALESCE(v_latest_shipping_cost, 0);

    -- 4. Fallback cost if no shipment green cost found
    IF v_latest_green_cost = 0 THEN
        SELECT ci.fallback_cost INTO v_fallback_cost
        FROM public.coffee_inventory ci
        WHERE ci.origin_id   = p_origin_id
          AND ci.facility_id = p_facility_id;

        IF COALESCE(v_fallback_cost, 0) > 0 THEN
            UPDATE public.coffee_inventory
               SET last_cost_lb       = NULL,
                   last_shipping_cost = NULL,
                   latest_cost        = v_fallback_cost
             WHERE origin_id   = p_origin_id
               AND facility_id = p_facility_id;
            RETURN;
        END IF;
    END IF;

    -- 5. Normal shipment path
    IF v_retention > 0 THEN
      v_final_landed_cost := (v_latest_green_cost + v_latest_shipping_cost) / v_retention;
    ELSE
      v_final_landed_cost := 0;
    END IF;

    UPDATE public.coffee_inventory
       SET last_cost_lb        = v_latest_green_cost,
           last_shipping_cost  = v_latest_shipping_cost,
           latest_cost         = v_final_landed_cost
     WHERE origin_id   = p_origin_id
       AND facility_id = p_facility_id;
END;
$$;

-- ── 4. get_coffee_cost_on_date ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_coffee_cost_on_date(p_origin_id text, p_facility_id text, p_order_date date)
RETURNS numeric LANGUAGE plpgsql AS $$
DECLARE
    v_retention     numeric;
    v_cost_lb       numeric;
    v_shipping_cost numeric;
BEGIN
    -- Retention factor (3-tier)
    SELECT value_number INTO v_retention
      FROM public.company_parameters
     WHERE parameter_id = '1de271df' AND facility_id = p_facility_id
     LIMIT 1;

    IF v_retention IS NULL OR v_retention = 0 THEN
        SELECT amount INTO v_retention FROM public.standard_parameters
         WHERE parameters_id = '1de271df' LIMIT 1;
    END IF;

    IF v_retention IS NULL OR v_retention = 0 THEN v_retention := 0.82; END IF;

    -- Priority 1: Most recent non-voided received shipment on or before order date
    SELECT cp.cost_lb, COALESCE(sr.shipping_cost_unit, 0)
      INTO v_cost_lb, v_shipping_cost
      FROM public.coffee_inventory_purchased cp
      JOIN public.shipment_received sr ON sr.shipment_id = cp.shipment_id
     WHERE cp.origin        = p_origin_id
       AND cp.facility_id   = p_facility_id
       AND cp.cost_lb        > 0
       AND sr.date_received IS NOT NULL
       AND sr.date_received <= p_order_date
       AND COALESCE(sr.voided, false) = false
     ORDER BY sr.date_received DESC, cp.created_at DESC
     LIMIT 1;

    IF v_cost_lb IS NOT NULL THEN
        RETURN (v_cost_lb + v_shipping_cost) / v_retention;
    END IF;

    -- Priority 2: Earliest non-voided received shipment (forward fallback)
    SELECT cp.cost_lb, COALESCE(sr.shipping_cost_unit, 0)
      INTO v_cost_lb, v_shipping_cost
      FROM public.coffee_inventory_purchased cp
      JOIN public.shipment_received sr ON sr.shipment_id = cp.shipment_id
     WHERE cp.origin        = p_origin_id
       AND cp.facility_id   = p_facility_id
       AND cp.cost_lb        > 0
       AND sr.date_received IS NOT NULL
       AND COALESCE(sr.voided, false) = false
     ORDER BY sr.date_received ASC, cp.created_at ASC
     LIMIT 1;

    IF v_cost_lb IS NOT NULL THEN
        RETURN (v_cost_lb + v_shipping_cost) / v_retention;
    END IF;

    -- Priority 3: User-entered fallback cost
    RETURN (
        SELECT fallback_cost FROM public.coffee_inventory
         WHERE origin_id = p_origin_id AND facility_id = p_facility_id
         LIMIT 1
    );
END;
$$;

-- ── 5. get_consumable_cost_on_date ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_consumable_cost_on_date(p_consumable_id text, p_facility_id text, p_order_date date)
RETURNS numeric LANGUAGE plpgsql AS $$
DECLARE
    v_cost numeric;
BEGIN
    -- Priority 1: Most recent non-voided received shipment on or before order date
    SELECT cp.cost_unit INTO v_cost
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
    SELECT cp.cost_unit INTO v_cost
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

-- ── 6. update_last_consumable_cost ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.update_last_consumable_cost()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_item_id       TEXT;
    v_facility_id   TEXT;
    v_latest_cost   NUMERIC;
    v_fallback_cost NUMERIC;
BEGIN
    v_item_id     := COALESCE(NEW.consumable_inventory_item, OLD.consumable_inventory_item);
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    -- Most recent valid cost from non-voided shipment
    SELECT cp.cost_unit::numeric
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

-- ── 7. propagate_coffee_purchase_to_orders ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.propagate_coffee_purchase_to_orders()
RETURNS trigger LANGUAGE plpgsql AS $$
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

    -- Get date_received — skip if shipment is voided
    SELECT sr.date_received INTO v_this_date
      FROM public.shipment_received sr
     WHERE sr.shipment_id = NEW.shipment_id
       AND COALESCE(sr.voided, false) = false
     LIMIT 1;

    IF v_this_date IS NULL THEN RETURN NULL; END IF;

    -- Find the NEXT non-voided received shipment for this origin + facility
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
         WHERE o.order_status    != 'Canceled'
           AND od.order_date     >= v_this_date
           AND (v_next_date IS NULL OR od.order_date < v_next_date)
           AND rc.coffee_item     = NEW.origin
           AND COALESCE(od.quantity, 0) > 0
    LOOP
        v_new_cost := public.get_product_cogs_on_date(
            v_rec.product_id, v_rec.facility_id, v_rec.order_date
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

-- ── 8. propagate_consumable_purchase_to_orders ───────────────────────────────
CREATE OR REPLACE FUNCTION public.propagate_consumable_purchase_to_orders()
RETURNS trigger LANGUAGE plpgsql AS $$
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

    -- Get date_received — skip if shipment is voided
    SELECT sr.date_received INTO v_this_date
      FROM public.shipment_received sr
     WHERE sr.shipment_id = NEW.shipment_id
       AND COALESCE(sr.voided, false) = false
     LIMIT 1;

    IF v_this_date IS NULL THEN RETURN NULL; END IF;

    -- Find the NEXT non-voided received shipment for this consumable + facility
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
         WHERE o.order_status    != 'Canceled'
           AND od.order_date     >= v_this_date
           AND (v_next_date IS NULL OR od.order_date < v_next_date)
           AND pc.consumable_id   = NEW.consumable_inventory_item
           AND COALESCE(od.quantity, 0) > 0
    LOOP
        v_new_cost := public.get_product_cogs_on_date(
            v_rec.product_id, v_rec.facility_id, v_rec.order_date
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

-- ── 9. Cascade trigger: recalculate stock + COGS when voided changes ─────────
CREATE OR REPLACE FUNCTION public.void_shipment_cascade()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    r              RECORD;
    v_bag_size     NUMERIC;
    v_current_lbs  NUMERIC;
    v_current_bags NUMERIC;
    v_par          NUMERIC;
    v_stock        NUMERIC;
BEGIN
    -- Recalculate coffee stock + COGS for all origins in this shipment
    FOR r IN
        SELECT DISTINCT origin AS origin_id, facility_id
        FROM public.coffee_inventory_purchased
        WHERE shipment_id = NEW.shipment_id
    LOOP
        SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
        FROM public.coffee_inventory
        WHERE origin_id = r.origin_id AND facility_id = r.facility_id LIMIT 1;

        v_current_lbs  := public.calculate_current_stock_lbs(r.origin_id, r.facility_id);
        v_current_bags := v_current_lbs / NULLIF(v_bag_size, 0);
        v_par          := public.calculate_par(r.origin_id);

        UPDATE public.coffee_inventory SET
            in_stock_lbs  = v_current_lbs,
            in_stock      = v_current_bags,
            par           = v_par,
            to_order_bags = GREATEST(0, COALESCE(v_par, 0) - v_current_bags),
            restock_level = public.calculate_restock_level(r.origin_id),
            updated_at    = NOW()
        WHERE origin_id = r.origin_id AND facility_id = r.facility_id;

        PERFORM public.recalculate_inventory_cost(r.origin_id, r.facility_id);
    END LOOP;

    -- Recalculate consumable stock for all items in this shipment
    FOR r IN
        SELECT DISTINCT consumable_inventory_item AS consumable_id, facility_id
        FROM public.consumable_inventory_purchased
        WHERE shipment_id = NEW.shipment_id
    LOOP
        v_stock := public.calculate_current_stock_consumables(r.consumable_id, r.facility_id);

        UPDATE public.consumable_inventory SET
            in_stock   = v_stock,
            updated_at = NOW()
        WHERE consumable_inventory_id = r.consumable_id
          AND facility_id = r.facility_id;
    END LOOP;

    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_void_shipment_cascade
AFTER UPDATE OF voided ON public.shipment_received
FOR EACH ROW
WHEN (OLD.voided IS DISTINCT FROM NEW.voided)
EXECUTE FUNCTION public.void_shipment_cascade();
