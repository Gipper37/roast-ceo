-- FIX: par/restock returned 0 for everything because Migration 1
-- (20260623000003) sourced their usage from roast_log_lot_consumption (the
-- per-lot deduct ledger), which is EMPTY for imported roasts (they skip the
-- deduct). Meanwhile daily_usage_lbs / AVG-MO is computed from the actual roast
-- record and works. So par showed 0 while AVG-MO showed real usage.
--
-- This re-sources calculate_par + calculate_restock_level from the SAME
-- roast-based usage as daily_usage_lbs (trg_recalc_coffee_on_nudge): single-origin
-- charge_weight to the group + each pre-blend's percentage share where the group
-- is a component, over a trailing 92-day window. Keeps the on-hand change from
-- Migration 1 (calculate_current_stock_lbs = lot sum) intact.
--
-- (True per-lot depletion par — borrow-aware — is revisitable once native
-- lot-tracked roasting populates the ledger; until then roast usage is complete
-- and consistent with what the operator sees in AVG-MO.)

CREATE OR REPLACE FUNCTION public.calculate_par(p_origin_id text)
RETURNS numeric LANGUAGE plpgsql AS $function$
DECLARE
  v_facility_id   text;
  v_usage         numeric;
  v_usage_blend   numeric;
  v_monthly_usage numeric;
  v_target_months numeric;
  v_buffer        numeric;
  v_bag_size      numeric;
  v_first_roast   date;
  v_data_months   numeric;
  v_timezone      text;
  v_current_date  date;
BEGIN
  SELECT facility_id INTO v_facility_id FROM coffee_inventory WHERE origin_id = p_origin_id LIMIT 1;
  SELECT time_zone INTO v_timezone FROM facilities WHERE facility_id = v_facility_id;
  IF v_timezone IS NULL OR v_timezone = '' THEN v_timezone := 'Pacific/Honolulu'; END IF;
  v_current_date := (CURRENT_TIMESTAMP AT TIME ZONE v_timezone)::date;

  -- roast-based usage (matches daily_usage_lbs): single-origin + pre-blend share
  SELECT COALESCE(SUM(rl.charge_weight_lbs), 0) INTO v_usage
  FROM roast_log rl LEFT JOIN roast_recipes rr ON rr.recipe_id = rl.recipe_id
  WHERE rl.origin_id = p_origin_id AND rl.facility_id = v_facility_id
    AND rl.roast_date::date >= (v_current_date - interval '92 days') AND rl."charged?" = true
    AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend' OR rr.roast_type IS NULL);

  SELECT COALESCE(SUM(rl.charge_weight_lbs * rc.percentage), 0) INTO v_usage_blend
  FROM roast_log rl JOIN roast_recipes rr ON rr.recipe_id = rl.recipe_id
    JOIN recipe_components rc ON rc.recipe_id = rl.recipe_id
  WHERE rc.coffee_item = p_origin_id AND rr.roast_type = 'Pre-Blend' AND rl.facility_id = v_facility_id
    AND rl.roast_date::date >= (v_current_date - interval '92 days') AND rl."charged?" = true;

  v_usage := v_usage + v_usage_blend;

  SELECT MIN(d) INTO v_first_roast FROM (
    SELECT rl.roast_date::date AS d FROM roast_log rl LEFT JOIN roast_recipes rr ON rr.recipe_id = rl.recipe_id
     WHERE rl.origin_id = p_origin_id AND rl.facility_id = v_facility_id AND rl."charged?" = true
       AND COALESCE(rl.charge_weight_lbs,0) > 0 AND rl.roast_date::date >= (v_current_date - interval '92 days')
       AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend' OR rr.roast_type IS NULL)
    UNION ALL
    SELECT rl.roast_date::date FROM roast_log rl JOIN roast_recipes rr ON rr.recipe_id = rl.recipe_id
      JOIN recipe_components rc ON rc.recipe_id = rl.recipe_id
     WHERE rc.coffee_item = p_origin_id AND rr.roast_type = 'Pre-Blend' AND rl.facility_id = v_facility_id
       AND rl."charged?" = true AND rl.roast_date::date >= (v_current_date - interval '92 days')
  ) sub;

  v_data_months := LEAST(3.0, GREATEST((v_current_date - COALESCE(v_first_roast, v_current_date))::numeric / 30.6667, 0.5));
  v_monthly_usage := v_usage / v_data_months;

  SELECT COALESCE(rc.target_months, 3) INTO v_target_months
  FROM coffee_inventory ci LEFT JOIN restock_category rc ON rc.restock_category_id = ci.restock_category_id
  WHERE ci.origin_id = p_origin_id LIMIT 1;
  IF v_target_months IS NULL THEN v_target_months := 3; END IF;

  SELECT COALESCE((SELECT cp.value_number FROM company_parameters cp
     WHERE cp.parameter_id = '5131610b' AND cp.facility_id = v_facility_id LIMIT 1), 1.3) INTO v_buffer;

  SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
  FROM coffee_inventory WHERE origin_id = p_origin_id AND facility_id = v_facility_id LIMIT 1;

  RETURN ROUND((v_monthly_usage * v_target_months * v_buffer) / NULLIF(v_bag_size, 0));
END;
$function$;

CREATE OR REPLACE FUNCTION public.calculate_restock_level(p_origin_id text)
RETURNS numeric LANGUAGE plpgsql AS $function$
DECLARE
  v_facility_id    text;
  v_usage          numeric;
  v_usage_blend    numeric;
  v_monthly_usage  numeric;
  v_reorder_months numeric;
  v_buffer         numeric;
  v_bag_size       numeric;
  v_current_date   date;
  v_timezone       text;
  v_par            numeric;
  v_result         numeric;
  v_first_roast    date;
  v_data_months    numeric;
BEGIN
  SELECT facility_id INTO v_facility_id FROM coffee_inventory WHERE origin_id = p_origin_id LIMIT 1;
  SELECT time_zone INTO v_timezone FROM facilities WHERE facility_id = v_facility_id;
  IF v_timezone IS NULL OR v_timezone = '' THEN v_timezone := 'Pacific/Honolulu'; END IF;
  v_current_date := (CURRENT_TIMESTAMP AT TIME ZONE v_timezone)::date;

  SELECT COALESCE(SUM(rl.charge_weight_lbs), 0) INTO v_usage
  FROM roast_log rl LEFT JOIN roast_recipes rr ON rr.recipe_id = rl.recipe_id
  WHERE rl.origin_id = p_origin_id AND rl.facility_id = v_facility_id
    AND rl.roast_date::date >= (v_current_date - interval '92 days') AND rl."charged?" = true
    AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend' OR rr.roast_type IS NULL);

  SELECT COALESCE(SUM(rl.charge_weight_lbs * rc.percentage), 0) INTO v_usage_blend
  FROM roast_log rl JOIN roast_recipes rr ON rr.recipe_id = rl.recipe_id
    JOIN recipe_components rc ON rc.recipe_id = rl.recipe_id
  WHERE rc.coffee_item = p_origin_id AND rr.roast_type = 'Pre-Blend' AND rl.facility_id = v_facility_id
    AND rl.roast_date::date >= (v_current_date - interval '92 days') AND rl."charged?" = true;

  v_usage := v_usage + v_usage_blend;

  SELECT MIN(d) INTO v_first_roast FROM (
    SELECT rl.roast_date::date AS d FROM roast_log rl LEFT JOIN roast_recipes rr ON rr.recipe_id = rl.recipe_id
     WHERE rl.origin_id = p_origin_id AND rl.facility_id = v_facility_id AND rl."charged?" = true
       AND COALESCE(rl.charge_weight_lbs,0) > 0 AND rl.roast_date::date >= (v_current_date - interval '92 days')
       AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend' OR rr.roast_type IS NULL)
    UNION ALL
    SELECT rl.roast_date::date FROM roast_log rl JOIN roast_recipes rr ON rr.recipe_id = rl.recipe_id
      JOIN recipe_components rc ON rc.recipe_id = rl.recipe_id
     WHERE rc.coffee_item = p_origin_id AND rr.roast_type = 'Pre-Blend' AND rl.facility_id = v_facility_id
       AND rl."charged?" = true AND rl.roast_date::date >= (v_current_date - interval '92 days')
  ) sub;

  v_data_months := LEAST(3.0, GREATEST((v_current_date - COALESCE(v_first_roast, v_current_date))::numeric / 30.6667, 0.5));
  v_monthly_usage := v_usage / v_data_months;

  IF v_monthly_usage <= 0 THEN RETURN 0; END IF;

  SELECT COALESCE(rc.reorder_months, 1.5) INTO v_reorder_months
  FROM coffee_inventory ci LEFT JOIN restock_category rc ON rc.restock_category_id = ci.restock_category_id
  WHERE ci.origin_id = p_origin_id LIMIT 1;
  IF v_reorder_months IS NULL THEN v_reorder_months := 1.5; END IF;

  SELECT COALESCE((SELECT cp.value_number FROM company_parameters cp
     WHERE cp.parameter_id = '5131610b' AND cp.facility_id = v_facility_id LIMIT 1), 1.3) INTO v_buffer;

  SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
  FROM coffee_inventory WHERE origin_id = p_origin_id AND facility_id = v_facility_id LIMIT 1;

  v_result := CEILING((v_monthly_usage * v_reorder_months * v_buffer) / NULLIF(v_bag_size, 0));

  v_par := calculate_par(p_origin_id);
  IF v_par <= 0 THEN RETURN 0; END IF;

  RETURN LEAST(v_result, v_par);
END;
$function$;
