-- calculate_par used FLOOR which rounds 0.9 bags → 0.
-- Switch to ROUND so 0.5+ rounds up to 1 bag.
-- calculate_restock_level caps itself at par, so this fixes restock too.

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
BEGIN
  SELECT facility_id INTO v_facility_id
  FROM coffee_inventory WHERE origin_id = p_origin_id LIMIT 1;

  -- Direct roast usage (last 92 days)
  SELECT COALESCE(SUM(rl.charge_weight_lbs), 0) INTO v_usage_direct
  FROM roast_log rl
  JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
  WHERE rl.origin_id = p_origin_id
    AND rl.roast_date::date >= (CURRENT_DATE - interval '92 days')
    AND rl."charged?" = true
    AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend')
    AND rl.facility_id = v_facility_id;

  -- Blend usage (last 92 days)
  SELECT COALESCE(SUM(rl.charge_weight_lbs * rc.percentage), 0) INTO v_usage_blend
  FROM roast_log rl
  JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
  JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
  WHERE rc.coffee_item = p_origin_id
    AND rr.roast_type = 'Pre-Blend'
    AND rl.roast_date::date >= (CURRENT_DATE - interval '92 days')
    AND rl."charged?" = true
    AND rl.facility_id = v_facility_id;

  v_monthly_usage := (v_usage_direct + v_usage_blend) / 3.0;

  -- Per-category target months (fallback to 3)
  SELECT COALESCE(rc.target_months, 3)
  INTO v_target_months
  FROM coffee_inventory ci
  LEFT JOIN restock_category rc ON rc.restock_category_id = ci.restock_category_id
  WHERE ci.origin_id = p_origin_id
  LIMIT 1;

  IF v_target_months IS NULL THEN v_target_months := 3; END IF;

  -- Global buffer
  SELECT COALESCE(
    (SELECT cp.value_number FROM company_parameters cp
     WHERE cp.parameter_id = '5131610b' AND cp.facility_id = v_facility_id LIMIT 1),
    1.3
  ) INTO v_buffer;

  SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
  FROM coffee_inventory WHERE origin_id = p_origin_id AND facility_id = v_facility_id LIMIT 1;

  -- ROUND (not FLOOR) so 0.5+ bags rounds up to 1 instead of dropping to 0
  RETURN ROUND((v_monthly_usage * v_target_months * v_buffer) / NULLIF(v_bag_size, 0));
END;
$function$;
