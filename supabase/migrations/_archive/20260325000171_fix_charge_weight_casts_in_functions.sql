-- Add ::numeric casts to charge_weight in all functions that aggregate it

CREATE OR REPLACE FUNCTION public.calculate_current_stock_lbs(p_origin_id text, p_facility_id text)
RETURNS numeric LANGUAGE plpgsql AS $function$
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
    SELECT COALESCE(SUM(rl.charge_weight::numeric), 0) INTO v_roasted_direct_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    WHERE rl.origin_id = p_origin_id
      AND rl.roast_date::DATE > v_last_inventory_date
      AND rl."charged?" = TRUE
      AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend')
      AND rl.facility_id = p_facility_id;

    -- 5. Outflow B: blend roasts
    SELECT COALESCE(SUM(rl.charge_weight::numeric * rc.percentage), 0) INTO v_roasted_blend_lbs
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
$function$;


CREATE OR REPLACE FUNCTION public.calculate_par(p_origin_id text)
RETURNS numeric LANGUAGE plpgsql AS $function$
DECLARE
    v_facility_id   TEXT;
    v_usage_direct  NUMERIC;
    v_usage_blend   NUMERIC;
    v_monthly_usage NUMERIC;
    v_par_multiple  NUMERIC;
    v_buffer        NUMERIC;
    v_bag_size      NUMERIC;
BEGIN
    SELECT facility_id INTO v_facility_id
    FROM coffee_inventory WHERE origin_id = p_origin_id LIMIT 1;

    SELECT COALESCE(SUM(rl.charge_weight::numeric), 0) INTO v_usage_direct
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    WHERE rl.origin_id = p_origin_id
      AND rl.roast_date::DATE >= (CURRENT_DATE - INTERVAL '92 days')
      AND rl."charged?" = TRUE
      AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend')
      AND rl.facility_id = v_facility_id;

    SELECT COALESCE(SUM(rl.charge_weight::numeric * rc.percentage), 0) INTO v_usage_blend
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
    WHERE rc.coffee_item = p_origin_id
      AND rr.roast_type = 'Pre-Blend'
      AND rl.roast_date::DATE >= (CURRENT_DATE - INTERVAL '92 days')
      AND rl."charged?" = TRUE
      AND rl.facility_id = v_facility_id;

    v_monthly_usage := (v_usage_direct + v_usage_blend) / 3.0;

    SELECT value_number INTO v_par_multiple
    FROM company_parameters WHERE parameter_id = '3e6f5909' AND facility_id = v_facility_id;

    SELECT value_number INTO v_buffer
    FROM company_parameters WHERE parameter_id = '5131610b' AND facility_id = v_facility_id;

    -- Bag size (text → numeric)
    SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
    FROM coffee_inventory WHERE origin_id = p_origin_id AND facility_id = v_facility_id LIMIT 1;

    IF v_par_multiple IS NULL THEN v_par_multiple := 3;   END IF;
    IF v_buffer       IS NULL THEN v_buffer       := 1.3; END IF;

    RETURN FLOOR((v_monthly_usage * v_par_multiple * v_buffer) / NULLIF(v_bag_size, 0));
END;
$function$;


CREATE OR REPLACE FUNCTION public.calculate_restock_level(p_origin_id text)
RETURNS numeric LANGUAGE plpgsql AS $function$
DECLARE
    v_facility_id      TEXT;
    v_usage_direct     NUMERIC;
    v_usage_blend      NUMERIC;
    v_monthly_usage    NUMERIC;
    v_trigger_multiple NUMERIC;
    v_buffer           NUMERIC;
    v_bag_size         NUMERIC;
    v_current_date     DATE;
    v_timezone         TEXT;
BEGIN
    SELECT facility_id INTO v_facility_id
    FROM coffee_inventory WHERE origin_id = p_origin_id LIMIT 1;

    SELECT time_zone INTO v_timezone
    FROM facilities WHERE facility_id = v_facility_id;

    IF v_timezone IS NULL OR v_timezone = '' THEN
        v_timezone := 'Pacific/Honolulu';
    END IF;

    v_current_date := (CURRENT_TIMESTAMP AT TIME ZONE v_timezone)::DATE;

    SELECT COALESCE(SUM(rl.charge_weight::numeric), 0) INTO v_usage_direct
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    WHERE rl.origin_id = p_origin_id
      AND rl.roast_date::DATE >= (v_current_date - INTERVAL '92 days')
      AND rl."charged?" = TRUE
      AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend')
      AND rl.facility_id = v_facility_id;

    SELECT COALESCE(SUM(rl.charge_weight::numeric * rc.percentage), 0) INTO v_usage_blend
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
    WHERE rc.coffee_item = p_origin_id
      AND rr.roast_type = 'Pre-Blend'
      AND rl.roast_date::DATE >= (v_current_date - INTERVAL '92 days')
      AND rl."charged?" = TRUE
      AND rl.facility_id = v_facility_id;

    v_monthly_usage := (v_usage_direct + v_usage_blend) / 3.0;

    SELECT value_number INTO v_trigger_multiple
    FROM company_parameters WHERE parameter_id = 'dae6cd4b' AND facility_id = v_facility_id;

    SELECT value_number INTO v_buffer
    FROM company_parameters WHERE parameter_id = '5131610b' AND facility_id = v_facility_id;

    -- Bag size (text → numeric)
    SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
    FROM coffee_inventory WHERE origin_id = p_origin_id AND facility_id = v_facility_id LIMIT 1;

    v_trigger_multiple := COALESCE(v_trigger_multiple, 1.5);
    v_buffer           := COALESCE(v_buffer, 1.3);

    RETURN CEILING((v_monthly_usage * v_trigger_multiple * v_buffer) / NULLIF(v_bag_size, 0));
END;
$function$;


CREATE OR REPLACE FUNCTION public.handle_manual_inventory_update()
RETURNS trigger LANGUAGE plpgsql AS $function$
DECLARE
    v_bag_size            NUMERIC;
    v_purchased_lbs       NUMERIC;
    v_roasted_direct_lbs  NUMERIC;
    v_roasted_blend_lbs   NUMERIC;
    v_last_inventory_date DATE;
BEGIN
    -- 1. Bag size (text → numeric)
    v_bag_size := COALESCE(NEW.bag_size::numeric, 154);

    -- 2. Rolling metrics
    NEW.par           := public.calculate_par(NEW.origin_id);
    NEW.restock_level := public.calculate_restock_level(NEW.origin_id);

    -- 3. Baseline
    v_last_inventory_date := COALESCE(NEW.last_inventory::DATE, '2000-01-01');
    NEW.inventory_lbs     := COALESCE(NEW.inventory_count_bags, 0) * v_bag_size;

    -- 4. Inflows
    SELECT COALESCE(SUM(p.amount), 0) INTO v_purchased_lbs
    FROM coffee_inventory_purchased p
    JOIN shipment_received s ON p.shipment_id = s.shipment_id
    WHERE p.origin = NEW.origin_id
      AND s.date_received::DATE > v_last_inventory_date
      AND s.date_received IS NOT NULL
      AND p.facility_id = NEW.facility_id;

    -- 5a. Direct roasts
    SELECT COALESCE(SUM(rl.charge_weight::numeric), 0) INTO v_roasted_direct_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    WHERE rl.origin_id = NEW.origin_id
      AND rl.roast_date::DATE > v_last_inventory_date
      AND rl."charged?" = TRUE
      AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend')
      AND rl.facility_id = NEW.facility_id;

    -- 5b. Blend roasts
    SELECT COALESCE(SUM(rl.charge_weight::numeric * rc.percentage), 0) INTO v_roasted_blend_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
    WHERE rc.coffee_item = NEW.origin_id
      AND rr.roast_type = 'Pre-Blend'
      AND rl.roast_date::DATE > v_last_inventory_date
      AND rl."charged?" = TRUE
      AND rl.facility_id = NEW.facility_id;

    -- 6. In stock
    NEW.in_stock_lbs := GREATEST(0, (NEW.inventory_lbs + v_purchased_lbs - v_roasted_direct_lbs - v_roasted_blend_lbs));
    NEW.in_stock     := NEW.in_stock_lbs / NULLIF(v_bag_size, 0);

    -- 7. To order
    NEW.to_order_bags := GREATEST(0, COALESCE(NEW.par, 0) - NEW.in_stock);

    RETURN NEW;
END;
$function$;
