-- Migration 00042: Fix inventory calculations
--
-- Three root causes of incorrect coffee_inventory numbers:
--
-- 1. No "received" flag on shipment_received — future/undelivered shipments
--    are counted as received inventory, inflating in_stock.
--
-- 2. par never recalculated by event-driven triggers — only fires on manual
--    inventory count (migration 00012 made the trigger column-specific).
--    The roast_log trigger recalculates restock_level but not par.
--    The purchase trigger recalculates neither par nor restock_level.
--
-- 3. handle_manual_inventory_update() still uses >= for roast date boundary
--    (migration 00009 fixed calculate_current_stock_lbs but not this function).
--
-- Also fixes: calculate_current_stock_consumables() same received filter.

-- ═══════════════════════════════════════════════════════════════
-- A. Add received boolean to shipment_received
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE public.shipment_received
    ADD COLUMN IF NOT EXISTS received BOOLEAN NOT NULL DEFAULT FALSE;

-- Backfill: past/today shipments are received; future ones are not
UPDATE public.shipment_received
SET received = TRUE
WHERE date_received IS NOT NULL
  AND date_received <= CURRENT_DATE;

-- ═══════════════════════════════════════════════════════════════
-- B. calculate_current_stock_lbs() — add received filter
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.calculate_current_stock_lbs(p_origin_id text, p_facility_id text)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
    v_purchased_lbs NUMERIC;
    v_starting_lbs NUMERIC;
    v_bag_size NUMERIC;
    v_inventory_bags NUMERIC;
    v_last_inventory_date DATE;
    v_roasted_direct_lbs NUMERIC;
    v_roasted_blend_lbs NUMERIC;
BEGIN
    -- 1. Get Bag Size (Facility Specific)
    SELECT value_number INTO v_bag_size
    FROM company_parameters
    WHERE parameter_id = '66526a57'
      AND facility_id = p_facility_id;

    IF v_bag_size IS NULL OR v_bag_size = 0 THEN v_bag_size := 154; END IF;

    -- 2. Get Baseline (Physical Count for THIS Facility)
    SELECT last_inventory::DATE, COALESCE(inventory_count_bags, 0)
    INTO v_last_inventory_date, v_inventory_bags
    FROM coffee_inventory
    WHERE origin_id = p_origin_id
      AND facility_id = p_facility_id;

    IF v_last_inventory_date IS NULL THEN v_last_inventory_date := '2000-01-01'; END IF;

    v_starting_lbs := v_inventory_bags * v_bag_size;

    -- 3. Inflow: Purchases (Facility Specific, RECEIVED shipments only)
    SELECT COALESCE(SUM(p.amount), 0) INTO v_purchased_lbs
    FROM coffee_inventory_purchased p
    JOIN shipment_received s ON p.shipment_id = s.shipment_id
    WHERE p.origin = p_origin_id
      AND s.date_received::DATE > v_last_inventory_date
      AND s.received = TRUE
      AND p.facility_id = p_facility_id;

    -- 4. Outflow A: Direct Roasts (Facility Specific)
    SELECT COALESCE(SUM(rl.charge_weight), 0) INTO v_roasted_direct_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    WHERE rl.origin_id = p_origin_id
      AND rl.roast_date::DATE > v_last_inventory_date
      AND rl."charged?" = TRUE
      AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend')
      AND rl.facility_id = p_facility_id;

    -- 5. Outflow B: Blend Roasts (Facility Specific)
    SELECT COALESCE(SUM(rl.charge_weight * rc.percentage), 0) INTO v_roasted_blend_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
    WHERE rc.coffee_item = p_origin_id
      AND rr.roast_type = 'Pre-Blend'
      AND rl.roast_date::DATE > v_last_inventory_date
      AND rl."charged?" = TRUE
      AND rl.facility_id = p_facility_id;

    -- 6. Final Result
    RETURN GREATEST(0, (v_starting_lbs + v_purchased_lbs - v_roasted_direct_lbs - v_roasted_blend_lbs));
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- C. handle_manual_inventory_update() — add received filter + fix >= boundary
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.handle_manual_inventory_update() RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_bag_size NUMERIC;
    v_purchased_lbs NUMERIC;
    v_roasted_direct_lbs NUMERIC;
    v_roasted_blend_lbs NUMERIC;
    v_last_inventory_date DATE;
BEGIN
    -- 1. Get Bag Size (Facility Specific)
    SELECT value_number INTO v_bag_size
    FROM company_parameters
    WHERE parameter_id = '66526a57'
      AND facility_id = NEW.facility_id;

    IF v_bag_size IS NULL OR v_bag_size = 0 THEN v_bag_size := 154; END IF;

    -- 2. Recalculate Rolling Metrics
    NEW.par := public.calculate_par(NEW.origin_id);
    NEW.restock_level := public.calculate_restock_level(NEW.origin_id);

    -- 3. Establish the Baseline
    v_last_inventory_date := COALESCE(NEW.last_inventory::DATE, '2000-01-01');
    NEW.inventory_lbs := COALESCE(NEW.inventory_count_bags, 0) * v_bag_size;

    -- 4. Calculate Inflows (RECEIVED shipments only)
    SELECT COALESCE(SUM(p.amount), 0) INTO v_purchased_lbs
    FROM coffee_inventory_purchased p
    JOIN shipment_received s ON p.shipment_id = s.shipment_id
    WHERE p.origin = NEW.origin_id
      AND s.date_received::DATE > v_last_inventory_date
      AND s.received = TRUE
      AND p.facility_id = NEW.facility_id;

    -- 5. Calculate Outflows (Roasts after this count)
    -- [FIX] Changed >= to > for consistency with calculate_current_stock_lbs

    -- A. Direct Roasts (Single Origin / Post-Blend)
    SELECT COALESCE(SUM(rl.charge_weight), 0) INTO v_roasted_direct_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    WHERE rl.origin_id = NEW.origin_id
      AND rl.roast_date::DATE > v_last_inventory_date
      AND rl."charged?" = TRUE
      AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend')
      AND rl.facility_id = NEW.facility_id;

    -- B. Blend Roasts (Pre-Blend)
    SELECT COALESCE(SUM(rl.charge_weight * rc.percentage), 0) INTO v_roasted_blend_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
    WHERE rc.coffee_item = NEW.origin_id
      AND rr.roast_type = 'Pre-Blend'
      AND rl.roast_date::DATE > v_last_inventory_date
      AND rl."charged?" = TRUE
      AND rl.facility_id = NEW.facility_id;

    -- 6. Update In Stock (LBS & BAGS)
    NEW.in_stock_lbs := GREATEST(0, (NEW.inventory_lbs + v_purchased_lbs - v_roasted_direct_lbs - v_roasted_blend_lbs));
    NEW.in_stock := NEW.in_stock_lbs / v_bag_size;

    RETURN NEW;
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- D. calculate_current_stock_consumables() — add received filter
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.calculate_current_stock_consumables(p_consumable_id text, p_facility_id text)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
    v_last_inventory_date DATE;
    v_inventory_count NUMERIC;
    v_purchased_amount NUMERIC;
    v_usage_amount NUMERIC;
BEGIN
    -- 1. Get Baseline for THIS facility only
    SELECT last_inventory_date, COALESCE(inventory_count, 0)
    INTO v_last_inventory_date, v_inventory_count
    FROM consumable_inventory
    WHERE consumable_inventory_id = p_consumable_id
      AND facility_id = p_facility_id;

    IF v_last_inventory_date IS NULL THEN
        v_last_inventory_date := '2000-01-01';
    END IF;

    -- 2. Sum Additions (RECEIVED shipments only)
    SELECT COALESCE(SUM(amount), 0)
    INTO v_purchased_amount
    FROM consumable_inventory_purchased cp
    JOIN shipment_received sr ON cp.shipment_id = sr.shipment_id
    WHERE cp.consumable_inventory_item = p_consumable_id
      AND sr.date_received > v_last_inventory_date
      AND sr.received = TRUE
      AND cp.facility_id = p_facility_id;

    -- 3. Sum Subtractions (Usage from Orders at THIS facility)
    SELECT COALESCE(SUM(od.quantity * pc.quantity), 0)
    INTO v_usage_amount
    FROM order_details od
    JOIN orders o ON od.order_id = o.order_id
    JOIN product_consumables pc ON od.product_id = pc.product_id
    WHERE pc.consumable_id = p_consumable_id
      AND o.order_date::DATE > v_last_inventory_date
      AND o.order_status != 'Cancelled'
      AND o.facility_id = p_facility_id;

    -- 4. Final Calculation
    RETURN GREATEST(0, (v_inventory_count + v_purchased_amount - v_usage_amount));
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- E. trg_roast_log_inventory_update() — add par recalculation
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.trg_roast_log_inventory_update() RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    r RECORD;
    v_bag_size NUMERIC;
    v_facility_id TEXT;
    v_current_lbs NUMERIC;
    v_current_bags NUMERIC;
    v_roast_type TEXT;
    v_par NUMERIC;
BEGIN
    -- 0. Setup: Identify Facility
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    -- 1. Get Bag Size (Facility Specific)
    SELECT value_number INTO v_bag_size
    FROM company_parameters
    WHERE parameter_id = '66526a57'
      AND facility_id = v_facility_id;

    IF v_bag_size IS NULL OR v_bag_size = 0 THEN v_bag_size := 154; END IF;

    -- -----------------------------------------------------------
    -- HANDLE DELETES or UPDATES (Revert/Fix OLD values)
    -- -----------------------------------------------------------
    IF TG_OP = 'DELETE' OR TG_OP = 'UPDATE' THEN

        v_roast_type := NULL;
        IF OLD.recipe_id IS NOT NULL THEN
            SELECT roast_type INTO v_roast_type FROM roast_recipes WHERE recipe_id = OLD.recipe_id;
        END IF;

        -- Case A: Pre-Blend
        IF v_roast_type = 'Pre-Blend' THEN
            FOR r IN SELECT coffee_item FROM recipe_components WHERE recipe_id = OLD.recipe_id LOOP
                v_current_lbs := public.calculate_current_stock_lbs(r.coffee_item, OLD.facility_id);
                v_current_bags := v_current_lbs / v_bag_size;
                v_par := public.calculate_par(r.coffee_item);

                UPDATE coffee_inventory
                SET
                    in_stock_lbs = v_current_lbs,
                    in_stock = v_current_bags,
                    par = v_par,
                    to_order_bags = GREATEST(0, COALESCE(v_par, 0) - v_current_bags),
                    restock_level = public.calculate_restock_level(r.coffee_item)
                WHERE origin_id = r.coffee_item
                  AND facility_id = OLD.facility_id;
            END LOOP;

        -- Case B: Single Origin / Post-Blend
        ELSIF OLD.origin_id IS NOT NULL THEN
            v_current_lbs := public.calculate_current_stock_lbs(OLD.origin_id, OLD.facility_id);
            v_current_bags := v_current_lbs / v_bag_size;
            v_par := public.calculate_par(OLD.origin_id);

            UPDATE coffee_inventory
            SET
                in_stock_lbs = v_current_lbs,
                in_stock = v_current_bags,
                par = v_par,
                to_order_bags = GREATEST(0, COALESCE(v_par, 0) - v_current_bags),
                restock_level = public.calculate_restock_level(OLD.origin_id)
            WHERE origin_id = OLD.origin_id
              AND facility_id = OLD.facility_id;
        END IF;
    END IF;

    -- -----------------------------------------------------------
    -- HANDLE INSERTS or UPDATES (Apply NEW values)
    -- -----------------------------------------------------------
    IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN

        v_roast_type := NULL;
        IF NEW.recipe_id IS NOT NULL THEN
            SELECT roast_type INTO v_roast_type FROM roast_recipes WHERE recipe_id = NEW.recipe_id;
        END IF;

        -- Case A: Pre-Blend
        IF v_roast_type = 'Pre-Blend' THEN
            FOR r IN SELECT coffee_item FROM recipe_components WHERE recipe_id = NEW.recipe_id LOOP
                v_current_lbs := public.calculate_current_stock_lbs(r.coffee_item, NEW.facility_id);
                v_current_bags := v_current_lbs / v_bag_size;
                v_par := public.calculate_par(r.coffee_item);

                UPDATE coffee_inventory
                SET
                    in_stock_lbs = v_current_lbs,
                    in_stock = v_current_bags,
                    par = v_par,
                    to_order_bags = GREATEST(0, COALESCE(v_par, 0) - v_current_bags),
                    restock_level = public.calculate_restock_level(r.coffee_item)
                WHERE origin_id = r.coffee_item
                  AND facility_id = NEW.facility_id;
            END LOOP;

        -- Case B: Single Origin / Post-Blend
        ELSIF NEW.origin_id IS NOT NULL THEN
            v_current_lbs := public.calculate_current_stock_lbs(NEW.origin_id, NEW.facility_id);
            v_current_bags := v_current_lbs / v_bag_size;
            v_par := public.calculate_par(NEW.origin_id);

            UPDATE coffee_inventory
            SET
                in_stock_lbs = v_current_lbs,
                in_stock = v_current_bags,
                par = v_par,
                to_order_bags = GREATEST(0, COALESCE(v_par, 0) - v_current_bags),
                restock_level = public.calculate_restock_level(NEW.origin_id)
            WHERE origin_id = NEW.origin_id
              AND facility_id = NEW.facility_id;
        END IF;
    END IF;

    RETURN NULL;
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- F. update_coffee_stock_purchased() — add par + restock_level
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.update_coffee_stock_purchased() RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_bag_size NUMERIC;
    v_current_lbs NUMERIC;
    v_par NUMERIC;
BEGIN
    -- -----------------------------------------------------------
    -- HANDLE DELETES
    -- -----------------------------------------------------------
    IF TG_OP = 'DELETE' THEN
        SELECT value_number INTO v_bag_size
        FROM company_parameters
        WHERE parameter_id = '66526a57' AND facility_id = OLD.facility_id;
        IF v_bag_size IS NULL OR v_bag_size = 0 THEN v_bag_size := 154; END IF;

        v_current_lbs := public.calculate_current_stock_lbs(OLD.origin, OLD.facility_id);
        v_par := public.calculate_par(OLD.origin);

        UPDATE coffee_inventory
        SET
            in_stock_lbs = v_current_lbs,
            in_stock = v_current_lbs / v_bag_size,
            par = v_par,
            to_order_bags = GREATEST(0, COALESCE(v_par, 0) - (v_current_lbs / v_bag_size)),
            restock_level = public.calculate_restock_level(OLD.origin)
        WHERE origin_id = OLD.origin
          AND facility_id = OLD.facility_id;
    END IF;

    -- -----------------------------------------------------------
    -- HANDLE INSERTS
    -- -----------------------------------------------------------
    IF TG_OP = 'INSERT' THEN
        SELECT value_number INTO v_bag_size
        FROM company_parameters
        WHERE parameter_id = '66526a57' AND facility_id = NEW.facility_id;
        IF v_bag_size IS NULL OR v_bag_size = 0 THEN v_bag_size := 154; END IF;

        v_current_lbs := public.calculate_current_stock_lbs(NEW.origin, NEW.facility_id);
        v_par := public.calculate_par(NEW.origin);

        UPDATE coffee_inventory
        SET
            in_stock_lbs = v_current_lbs,
            in_stock = v_current_lbs / v_bag_size,
            par = v_par,
            to_order_bags = GREATEST(0, COALESCE(v_par, 0) - (v_current_lbs / v_bag_size)),
            restock_level = public.calculate_restock_level(NEW.origin)
        WHERE origin_id = NEW.origin
          AND facility_id = NEW.facility_id;
    END IF;

    -- -----------------------------------------------------------
    -- HANDLE UPDATES
    -- -----------------------------------------------------------
    IF TG_OP = 'UPDATE' THEN

        -- Scenario 1: Origin or Facility Changed
        IF OLD.origin IS DISTINCT FROM NEW.origin OR OLD.facility_id IS DISTINCT FROM NEW.facility_id THEN

            -- A. Fix OLD
            SELECT value_number INTO v_bag_size
            FROM company_parameters
            WHERE parameter_id = '66526a57' AND facility_id = OLD.facility_id;
            IF v_bag_size IS NULL OR v_bag_size = 0 THEN v_bag_size := 154; END IF;

            v_current_lbs := public.calculate_current_stock_lbs(OLD.origin, OLD.facility_id);
            v_par := public.calculate_par(OLD.origin);

            UPDATE coffee_inventory
            SET
                in_stock_lbs = v_current_lbs,
                in_stock = v_current_lbs / v_bag_size,
                par = v_par,
                to_order_bags = GREATEST(0, COALESCE(v_par, 0) - (v_current_lbs / v_bag_size)),
                restock_level = public.calculate_restock_level(OLD.origin)
            WHERE origin_id = OLD.origin
              AND facility_id = OLD.facility_id;

            -- B. Fix NEW
            SELECT value_number INTO v_bag_size
            FROM company_parameters
            WHERE parameter_id = '66526a57' AND facility_id = NEW.facility_id;
            IF v_bag_size IS NULL OR v_bag_size = 0 THEN v_bag_size := 154; END IF;

            v_current_lbs := public.calculate_current_stock_lbs(NEW.origin, NEW.facility_id);
            v_par := public.calculate_par(NEW.origin);

            UPDATE coffee_inventory
            SET
                in_stock_lbs = v_current_lbs,
                in_stock = v_current_lbs / v_bag_size,
                par = v_par,
                to_order_bags = GREATEST(0, COALESCE(v_par, 0) - (v_current_lbs / v_bag_size)),
                restock_level = public.calculate_restock_level(NEW.origin)
            WHERE origin_id = NEW.origin
              AND facility_id = NEW.facility_id;

        -- Scenario 2: Simple Update (Same Origin/Facility)
        ELSE
            SELECT value_number INTO v_bag_size
            FROM company_parameters
            WHERE parameter_id = '66526a57' AND facility_id = NEW.facility_id;
            IF v_bag_size IS NULL OR v_bag_size = 0 THEN v_bag_size := 154; END IF;

            v_current_lbs := public.calculate_current_stock_lbs(NEW.origin, NEW.facility_id);
            v_par := public.calculate_par(NEW.origin);

            UPDATE coffee_inventory
            SET
                in_stock_lbs = v_current_lbs,
                in_stock = v_current_lbs / v_bag_size,
                par = v_par,
                to_order_bags = GREATEST(0, COALESCE(v_par, 0) - (v_current_lbs / v_bag_size)),
                restock_level = public.calculate_restock_level(NEW.origin)
            WHERE origin_id = NEW.origin
              AND facility_id = NEW.facility_id;
        END IF;
    END IF;

    RETURN NULL;
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- G. One-time recalculation of all coffee_inventory rows
-- Touching last_inventory fires trg_manual_inventory_update which
-- recalculates par, restock_level, in_stock_lbs, in_stock.
-- ═══════════════════════════════════════════════════════════════

UPDATE public.coffee_inventory
SET last_inventory = last_inventory;
