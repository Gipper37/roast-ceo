-- ============================================================================
-- Par / restock: annualize usage over the data ACTUALLY available
-- ============================================================================
-- calculate_par and calculate_restock_level summed roast usage over the last
-- 92 days and divided by a fixed 3.0 to get "monthly usage." That assumes a
-- full 3 months of roast history. A newly-migrated facility with, say, ~5.5
-- weeks of imported roasts has its monthly usage understated ~2.5x — so par
-- and restock come out far too low for what's actually being consumed.
-- (Real MCR case: Colombia ran ~1,836 lbs in May, but par's monthly estimate
-- was only 848 lbs → par 25 bags instead of ~60.)
--
-- Fix: divide by the months of roast history actually present in the window,
-- not a fixed 3. Capped at 3.0 (so a facility with ≥3 months of history is
-- byte-for-byte unchanged) and floored at 0.5 month (so a facility with only
-- a handful of days doesn't get a wildly inflated par).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.calculate_par(p_origin_id text)
RETURNS numeric
LANGUAGE plpgsql
AS $function$
DECLARE
  v_facility_id   text;
  v_usage_direct  numeric;
  v_usage_blend   numeric;
  v_monthly_usage numeric;
  v_target_months numeric;
  v_buffer        numeric;
  v_bag_size      numeric;
  v_first_roast   date;
  v_data_months   numeric;
BEGIN
  SELECT facility_id INTO v_facility_id
  FROM coffee_inventory WHERE origin_id = p_origin_id LIMIT 1;

  SELECT COALESCE(SUM(rl.charge_weight_lbs), 0) INTO v_usage_direct
  FROM roast_log rl
  LEFT JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
  WHERE rl.origin_id = p_origin_id
    AND rl.roast_date::date >= (CURRENT_DATE - interval '92 days')
    AND rl."charged?" = true
    AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend' OR rr.roast_type IS NULL)
    AND rl.facility_id = v_facility_id;

  SELECT COALESCE(SUM(rl.charge_weight_lbs * rc.percentage), 0) INTO v_usage_blend
  FROM roast_log rl
  JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
  JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
  WHERE rc.coffee_item = p_origin_id
    AND rr.roast_type = 'Pre-Blend'
    AND rl.roast_date::date >= (CURRENT_DATE - interval '92 days')
    AND rl."charged?" = true
    AND rl.facility_id = v_facility_id;

  -- Months of roast history actually present in the 92-day window.
  SELECT MIN(rl.roast_date::date) INTO v_first_roast
  FROM roast_log rl
  WHERE rl.facility_id = v_facility_id
    AND rl."charged?" = true
    AND COALESCE(rl.charge_weight_lbs, 0) > 0
    AND rl.roast_date::date >= (CURRENT_DATE - interval '92 days');
  v_data_months := LEAST(3.0, GREATEST(
    (CURRENT_DATE - COALESCE(v_first_roast, CURRENT_DATE))::numeric / 30.6667, 0.5));
  v_monthly_usage := (v_usage_direct + v_usage_blend) / v_data_months;

  SELECT COALESCE(rc.target_months, 3)
  INTO v_target_months
  FROM coffee_inventory ci
  LEFT JOIN restock_category rc ON rc.restock_category_id = ci.restock_category_id
  WHERE ci.origin_id = p_origin_id
  LIMIT 1;
  IF v_target_months IS NULL THEN v_target_months := 3; END IF;

  SELECT COALESCE(
    (SELECT cp.value_number FROM company_parameters cp
     WHERE cp.parameter_id = '5131610b' AND cp.facility_id = v_facility_id LIMIT 1),
    1.3
  ) INTO v_buffer;

  SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
  FROM coffee_inventory WHERE origin_id = p_origin_id AND facility_id = v_facility_id LIMIT 1;

  RETURN ROUND((v_monthly_usage * v_target_months * v_buffer) / NULLIF(v_bag_size, 0));
END;
$function$;

CREATE OR REPLACE FUNCTION public.calculate_restock_level(p_origin_id text)
RETURNS numeric
LANGUAGE plpgsql
AS $function$
DECLARE
  v_facility_id      text;
  v_usage_direct     numeric;
  v_usage_blend      numeric;
  v_monthly_usage    numeric;
  v_reorder_months   numeric;
  v_buffer           numeric;
  v_bag_size         numeric;
  v_current_date     date;
  v_timezone         text;
  v_par              numeric;
  v_result           numeric;
  v_first_roast      date;
  v_data_months      numeric;
BEGIN
  SELECT facility_id INTO v_facility_id
  FROM coffee_inventory WHERE origin_id = p_origin_id LIMIT 1;

  SELECT time_zone INTO v_timezone FROM facilities WHERE facility_id = v_facility_id;
  IF v_timezone IS NULL OR v_timezone = '' THEN v_timezone := 'Pacific/Honolulu'; END IF;
  v_current_date := (CURRENT_TIMESTAMP AT TIME ZONE v_timezone)::date;

  SELECT COALESCE(SUM(rl.charge_weight_lbs), 0) INTO v_usage_direct
  FROM roast_log rl
  LEFT JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
  WHERE rl.origin_id = p_origin_id
    AND rl.roast_date::date >= (v_current_date - interval '92 days')
    AND rl."charged?" = true
    AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend' OR rr.roast_type IS NULL)
    AND rl.facility_id = v_facility_id;

  SELECT COALESCE(SUM(rl.charge_weight_lbs * rc.percentage), 0) INTO v_usage_blend
  FROM roast_log rl
  JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
  JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
  WHERE rc.coffee_item = p_origin_id
    AND rr.roast_type = 'Pre-Blend'
    AND rl.roast_date::date >= (v_current_date - interval '92 days')
    AND rl."charged?" = true
    AND rl.facility_id = v_facility_id;

  -- Months of roast history actually present in the 92-day window.
  SELECT MIN(rl.roast_date::date) INTO v_first_roast
  FROM roast_log rl
  WHERE rl.facility_id = v_facility_id
    AND rl."charged?" = true
    AND COALESCE(rl.charge_weight_lbs, 0) > 0
    AND rl.roast_date::date >= (v_current_date - interval '92 days');
  v_data_months := LEAST(3.0, GREATEST(
    (v_current_date - COALESCE(v_first_roast, v_current_date))::numeric / 30.6667, 0.5));
  v_monthly_usage := (v_usage_direct + v_usage_blend) / v_data_months;

  IF v_monthly_usage <= 0 THEN RETURN 0; END IF;

  SELECT COALESCE(rc.reorder_months, 1.5)
  INTO v_reorder_months
  FROM coffee_inventory ci
  LEFT JOIN restock_category rc ON rc.restock_category_id = ci.restock_category_id
  WHERE ci.origin_id = p_origin_id
  LIMIT 1;
  IF v_reorder_months IS NULL THEN v_reorder_months := 1.5; END IF;

  SELECT COALESCE(
    (SELECT cp.value_number FROM company_parameters cp
     WHERE cp.parameter_id = '5131610b' AND cp.facility_id = v_facility_id LIMIT 1),
    1.3
  ) INTO v_buffer;

  SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
  FROM coffee_inventory WHERE origin_id = p_origin_id AND facility_id = v_facility_id LIMIT 1;

  v_result := CEILING((v_monthly_usage * v_reorder_months * v_buffer) / NULLIF(v_bag_size, 0));

  v_par := calculate_par(p_origin_id);
  IF v_par <= 0 THEN RETURN 0; END IF;

  RETURN LEAST(v_result, v_par);
END;
$function$;
