-- Migration 00044: Fix to_order_bags in handle_manual_inventory_update + guard baseline columns
--
-- Bug: handle_manual_inventory_update() computes par and in_stock but never
-- derives to_order_bags. Result: to_order_bags stays at 0 after recalculation.
--
-- Also adds guard triggers to prevent direct edits to baseline columns on
-- coffee_inventory and consumable_inventory. All baseline changes must go
-- through the history tables.

-- ═══════════════════════════════════════════════════════════════
-- A. Fix handle_manual_inventory_update() — add to_order_bags
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

    -- 7. Update To Order (FIX: was missing in migration 00042)
    NEW.to_order_bags := GREATEST(0, COALESCE(NEW.par, 0) - NEW.in_stock);

    RETURN NEW;
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- B. Guard triggers — prevent direct edits to baseline columns
-- ═══════════════════════════════════════════════════════════════

-- B1. Coffee inventory guard
CREATE OR REPLACE FUNCTION public.guard_coffee_inventory_baseline() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    -- Allow writes from the history-to-parent trigger function
    IF current_setting('app.from_history_trigger', true) = 'true' THEN
        RETURN NEW;
    END IF;

    IF OLD.last_inventory IS DISTINCT FROM NEW.last_inventory
       OR OLD.inventory_count_bags IS DISTINCT FROM NEW.inventory_count_bags THEN
        RAISE EXCEPTION 'Direct edits to last_inventory / inventory_count_bags are not allowed. Insert into coffee_inventory_history instead.';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_guard_coffee_baseline
    BEFORE UPDATE OF last_inventory, inventory_count_bags ON public.coffee_inventory
    FOR EACH ROW
    EXECUTE FUNCTION public.guard_coffee_inventory_baseline();

-- B2. Consumable inventory guard
CREATE OR REPLACE FUNCTION public.guard_consumable_inventory_baseline() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF current_setting('app.from_history_trigger', true) = 'true' THEN
        RETURN NEW;
    END IF;

    IF OLD.last_inventory_date IS DISTINCT FROM NEW.last_inventory_date
       OR OLD.inventory_count IS DISTINCT FROM NEW.inventory_count THEN
        RAISE EXCEPTION 'Direct edits to last_inventory_date / inventory_count are not allowed. Insert into consumable_inventory_history instead.';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_guard_consumable_baseline
    BEFORE UPDATE OF last_inventory_date, inventory_count ON public.consumable_inventory
    FOR EACH ROW
    EXECUTE FUNCTION public.guard_consumable_inventory_baseline();

-- ═══════════════════════════════════════════════════════════════
-- C. Update push functions — set session flag to bypass guard
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.push_coffee_history_to_parent() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    -- Set flag so the guard trigger allows this write
    PERFORM set_config('app.from_history_trigger', 'true', true);

    UPDATE coffee_inventory
    SET
        last_inventory = NEW.inventory_date,
        inventory_count_bags = NEW.bag_count,
        updated_at = NOW()
    WHERE origin_id = NEW.origin_id
      AND facility_id = NEW.facility_id;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.push_consumable_history_to_parent() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM set_config('app.from_history_trigger', 'true', true);

    UPDATE consumable_inventory
    SET
        last_inventory_date = NEW.inventory_date,
        inventory_count = NEW.inventory_count,
        updated_at = NOW()
    WHERE consumable_inventory_id = NEW.consumable_id
      AND facility_id = NEW.facility_id;

    RETURN NEW;
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- D. Recalculate all coffee_inventory rows
-- ═══════════════════════════════════════════════════════════════
-- Must bypass guard since we're touching last_inventory

SELECT set_config('app.from_history_trigger', 'true', true);

UPDATE public.coffee_inventory
SET last_inventory = last_inventory;
