-- Migration 00052: current_shipment_id + drop received boolean
--
-- 1. recent_coffee_order: replace order_date with current_shipment_id (Ref to shipment_received)
--    User explicitly selects which shipment is current — eliminates fragile date-based lookup.
-- 2. shipment_received: drop received boolean, add CHECK constraint (date_received not future)
-- 3. Update 4 functions: replace received = TRUE with date_received IS NOT NULL

-- ═══════════════════════════════════════════════════════════════
-- A. recent_coffee_order: add current_shipment_id, backfill, drop order_date
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE public.recent_coffee_order
  ADD COLUMN current_shipment_id text
  REFERENCES public.shipment_received(shipment_id);

-- Backfill: most recent shipment by order_date DESC for each facility
UPDATE public.recent_coffee_order rco
SET current_shipment_id = (
    SELECT shipment_id FROM public.shipment_received
    WHERE facility_id = rco.facility_id
    ORDER BY order_date DESC NULLS LAST, created_at DESC
    LIMIT 1
);

ALTER TABLE public.recent_coffee_order DROP COLUMN order_date;

-- ═══════════════════════════════════════════════════════════════
-- B. Update recalculate_green_purchasing_metrics()
--    Now reads current_shipment_id from recent_coffee_order instead of
--    doing a dynamic ORDER BY date lookup. No longer sets order_date.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.recalculate_green_purchasing_metrics(p_facility_id text)
RETURNS void AS $$
DECLARE
    v_total_ordered_lbs     NUMERIC;
    v_total_ordered_bags    NUMERIC;
    v_total_to_order_bags   NUMERIC;
    v_current_shipment_id   TEXT;
BEGIN
    -- 1. Get current_shipment_id from recent_coffee_order
    SELECT current_shipment_id INTO v_current_shipment_id
    FROM public.recent_coffee_order
    WHERE facility_id = p_facility_id;

    -- 2. Sum lbs and bags from coffee_inventory_purchased for that shipment
    SELECT
        COALESCE(SUM(amount), 0),
        COALESCE(SUM(bags_ordered), 0)
    INTO v_total_ordered_lbs, v_total_ordered_bags
    FROM public.coffee_inventory_purchased
    WHERE shipment_id = v_current_shipment_id
      AND facility_id = p_facility_id;

    -- 3. Sum to_order_bags from coffee_inventory (recommended_pallets unchanged)
    SELECT COALESCE(SUM(to_order_bags), 0)
    INTO v_total_to_order_bags
    FROM public.coffee_inventory
    WHERE facility_id = p_facility_id;

    -- 4. Update recent_coffee_order
    UPDATE public.recent_coffee_order
    SET
        lbs_ordered         = v_total_ordered_lbs,
        recommended_pallets = CEIL(v_total_to_order_bags / 10.0),
        bags_left           = (COALESCE(total_pallets, 0) * 10) - v_total_ordered_bags
    WHERE facility_id = p_facility_id;
END;
$$ LANGUAGE plpgsql;

-- ═══════════════════════════════════════════════════════════════
-- C. Replace per-column BEFORE trigger on recent_coffee_order
--    Old: trg_bags_left_on_pallets_change (total_pallets only, from migration 00051)
--    New: combined trigger covering total_pallets AND current_shipment_id changes
--         sets both lbs_ordered and bags_left in one pass
-- ═══════════════════════════════════════════════════════════════

DROP TRIGGER IF EXISTS trg_bags_left_on_pallets_change ON public.recent_coffee_order;
DROP FUNCTION IF EXISTS public.compute_bags_left_on_pallets_change();

CREATE OR REPLACE FUNCTION public.compute_recent_coffee_order_calcs()
RETURNS TRIGGER AS $$
DECLARE
    v_total_ordered_lbs  NUMERIC;
    v_total_ordered_bags NUMERIC;
BEGIN
    SELECT
        COALESCE(SUM(amount), 0),
        COALESCE(SUM(bags_ordered), 0)
    INTO v_total_ordered_lbs, v_total_ordered_bags
    FROM public.coffee_inventory_purchased
    WHERE shipment_id = NEW.current_shipment_id
      AND facility_id = NEW.facility_id;

    NEW.lbs_ordered := v_total_ordered_lbs;
    NEW.bags_left   := (COALESCE(NEW.total_pallets, 0) * 10) - v_total_ordered_bags;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_recent_coffee_order_calcs
    BEFORE UPDATE OF total_pallets, current_shipment_id
    ON public.recent_coffee_order
    FOR EACH ROW EXECUTE FUNCTION public.compute_recent_coffee_order_calcs();

-- ═══════════════════════════════════════════════════════════════
-- D. shipment_received: drop received boolean, add CHECK constraint
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE public.shipment_received DROP COLUMN received;

ALTER TABLE public.shipment_received
  ADD CONSTRAINT chk_date_received_not_future
  CHECK (date_received IS NULL OR date_received <= CURRENT_DATE);

-- ═══════════════════════════════════════════════════════════════
-- E. Update 4 functions: received = TRUE → date_received IS NOT NULL
-- ═══════════════════════════════════════════════════════════════

-- E1. calculate_current_stock_lbs() — from migration 00042
CREATE OR REPLACE FUNCTION public.calculate_current_stock_lbs(p_origin_id text, p_facility_id text)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
    v_purchased_lbs      NUMERIC;
    v_starting_lbs       NUMERIC;
    v_bag_size           NUMERIC;
    v_inventory_bags     NUMERIC;
    v_last_inventory_date DATE;
    v_roasted_direct_lbs NUMERIC;
    v_roasted_blend_lbs  NUMERIC;
BEGIN
    -- 1. Bag Size (Facility Specific)
    SELECT value_number INTO v_bag_size
    FROM company_parameters
    WHERE parameter_id = '66526a57'
      AND facility_id = p_facility_id;
    IF v_bag_size IS NULL OR v_bag_size = 0 THEN v_bag_size := 154; END IF;

    -- 2. Baseline (Physical Count for THIS Facility)
    SELECT last_inventory::DATE, COALESCE(inventory_count_bags, 0)
    INTO v_last_inventory_date, v_inventory_bags
    FROM coffee_inventory
    WHERE origin_id = p_origin_id
      AND facility_id = p_facility_id;
    IF v_last_inventory_date IS NULL THEN v_last_inventory_date := '2000-01-01'; END IF;
    v_starting_lbs := v_inventory_bags * v_bag_size;

    -- 3. Inflow: Purchases (RECEIVED shipments only — date_received IS NOT NULL)
    SELECT COALESCE(SUM(p.amount), 0) INTO v_purchased_lbs
    FROM coffee_inventory_purchased p
    JOIN shipment_received s ON p.shipment_id = s.shipment_id
    WHERE p.origin = p_origin_id
      AND s.date_received::DATE > v_last_inventory_date
      AND s.date_received IS NOT NULL
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

-- E2. handle_manual_inventory_update() — from migration 00044
CREATE OR REPLACE FUNCTION public.handle_manual_inventory_update() RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_bag_size            NUMERIC;
    v_purchased_lbs       NUMERIC;
    v_roasted_direct_lbs  NUMERIC;
    v_roasted_blend_lbs   NUMERIC;
    v_last_inventory_date DATE;
BEGIN
    -- 1. Bag Size (Facility Specific)
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

    -- 4. Inflows (RECEIVED shipments only — date_received IS NOT NULL)
    SELECT COALESCE(SUM(p.amount), 0) INTO v_purchased_lbs
    FROM coffee_inventory_purchased p
    JOIN shipment_received s ON p.shipment_id = s.shipment_id
    WHERE p.origin = NEW.origin_id
      AND s.date_received::DATE > v_last_inventory_date
      AND s.date_received IS NOT NULL
      AND p.facility_id = NEW.facility_id;

    -- 5. Outflows

    -- A. Direct Roasts
    SELECT COALESCE(SUM(rl.charge_weight), 0) INTO v_roasted_direct_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    WHERE rl.origin_id = NEW.origin_id
      AND rl.roast_date::DATE > v_last_inventory_date
      AND rl."charged?" = TRUE
      AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend')
      AND rl.facility_id = NEW.facility_id;

    -- B. Blend Roasts
    SELECT COALESCE(SUM(rl.charge_weight * rc.percentage), 0) INTO v_roasted_blend_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
    WHERE rc.coffee_item = NEW.origin_id
      AND rr.roast_type = 'Pre-Blend'
      AND rl.roast_date::DATE > v_last_inventory_date
      AND rl."charged?" = TRUE
      AND rl.facility_id = NEW.facility_id;

    -- 6. In Stock
    NEW.in_stock_lbs := GREATEST(0, (NEW.inventory_lbs + v_purchased_lbs - v_roasted_direct_lbs - v_roasted_blend_lbs));
    NEW.in_stock := NEW.in_stock_lbs / v_bag_size;

    -- 7. To Order
    NEW.to_order_bags := GREATEST(0, COALESCE(NEW.par, 0) - NEW.in_stock);

    RETURN NEW;
END;
$$;

-- E3. calculate_current_stock_consumables() — from migration 00045
CREATE OR REPLACE FUNCTION public.calculate_current_stock_consumables(p_consumable_id text, p_facility_id text)
RETURNS numeric
LANGUAGE plpgsql
AS $$
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

    -- 2. Additions (RECEIVED shipments only — date_received IS NOT NULL)
    SELECT COALESCE(SUM(amount), 0)
    INTO v_purchased_amount
    FROM consumable_inventory_purchased cp
    JOIN shipment_received sr ON cp.shipment_id = sr.shipment_id
    WHERE cp.consumable_inventory_item = p_consumable_id
      AND sr.date_received > v_last_inventory_date
      AND sr.date_received IS NOT NULL
      AND cp.facility_id = p_facility_id;

    -- 3. Subtractions (non-canceled Orders)
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

-- E4. update_consumable_metrics() — from migration 00045
CREATE OR REPLACE FUNCTION public.update_consumable_metrics() RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    target_id             text;
    v_facility_id         text;
    v_last_inventory_date DATE;
    v_purchased_amount    NUMERIC;
    v_usage_amount        NUMERIC;
    v_par                 numeric;
    v_restock_level       numeric;
BEGIN
    target_id     := COALESCE(NEW.consumable_inventory_id, OLD.consumable_inventory_id);
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    -- 1. Baseline
    v_last_inventory_date := COALESCE(NEW.last_inventory_date::DATE, '2000-01-01');

    -- 2. Additions (RECEIVED shipments only — date_received IS NOT NULL)
    SELECT COALESCE(SUM(amount), 0)
    INTO v_purchased_amount
    FROM consumable_inventory_purchased cp
    JOIN shipment_received sr ON cp.shipment_id = sr.shipment_id
    WHERE cp.consumable_inventory_item = target_id
      AND sr.date_received > v_last_inventory_date
      AND sr.date_received IS NOT NULL
      AND cp.facility_id = v_facility_id;

    -- 3. Subtractions (non-canceled Orders)
    SELECT COALESCE(SUM(od.quantity * pc.quantity), 0)
    INTO v_usage_amount
    FROM order_details od
    JOIN orders o ON od.order_id = o.order_id
    JOIN product_consumables pc ON od.product_id = pc.product_id
    WHERE pc.consumable_id = target_id
      AND o.order_date::DATE > v_last_inventory_date
      AND o.order_status != 'Canceled'
      AND o.facility_id = v_facility_id;

    -- 4. Final Stock
    NEW.in_stock := GREATEST(0, (COALESCE(NEW.inventory_count, 0) + v_purchased_amount - v_usage_amount));

    -- 5. To Order
    v_par           := COALESCE(NEW.par, 0);
    v_restock_level := COALESCE(NEW.restock_level, 0);
    IF NEW.in_stock <= v_restock_level THEN
        NEW.to_order := GREATEST(0, v_par - NEW.in_stock);
    ELSE
        NEW.to_order := 0;
    END IF;

    RETURN NEW;
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- F. Recalculate all rows
-- ═══════════════════════════════════════════════════════════════

-- Coffee inventory (guard bypass required — touches last_inventory)
SELECT set_config('app.from_history_trigger', 'true', true);
UPDATE public.coffee_inventory SET last_inventory = last_inventory
WHERE facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de';

-- Consumable inventory
UPDATE public.consumable_inventory SET updated_at = NOW();

-- recent_coffee_order (recalculate from current_shipment_id)
DO $$
DECLARE v_fid TEXT;
BEGIN
    FOR v_fid IN
        SELECT DISTINCT facility_id FROM public.recent_coffee_order WHERE facility_id IS NOT NULL
    LOOP
        PERFORM public.recalculate_green_purchasing_metrics(v_fid);
    END LOOP;
END;
$$;
