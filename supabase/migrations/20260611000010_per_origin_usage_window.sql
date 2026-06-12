-- ============================================================================
-- Par/restock/daily_usage: per-ORIGIN data-span window + consistent tz anchor
-- ============================================================================
-- 20260611000007/0008 introduced a data-span divisor (usage / actual months of
-- history) so newly-migrated facilities aren't under-pared. But v_first_roast
-- was scoped to the FACILITY's first roast, not the ORIGIN's. An origin that
-- started roasting later than the facility (e.g. MCR Mexico's first roast was
-- 5/21, 16 days after the facility's 5/5) got divided by too many months, so
-- its monthly usage — and par/restock/rec-order — came out materially low
-- (Mexico par 23 vs the correct 40; ~12 of 23 MCR origins affected).
--
-- Fix: scope the first-roast (the denominator's start) to the origin's OWN
-- usage — its direct roasts AND the pre-blends it's a component of. Established
-- origins are unchanged (their first roast == the facility's, both cap at 3.0).
--
-- Also align the "today" anchor: calculate_par + trg_recalc_coffee_on_nudge
-- used CURRENT_DATE (server UTC) while calculate_restock_level used the
-- facility-local date — so par and restock could anchor to different calendar
-- days mid-day and wobble. All three now use the facility-tz date.
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
  v_timezone      text;
  v_current_date  date;
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

  -- Months of THIS ORIGIN's roast history present in the 92-day window.
  SELECT MIN(d) INTO v_first_roast FROM (
    SELECT rl.roast_date::date AS d
    FROM roast_log rl LEFT JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    WHERE rl.origin_id = p_origin_id AND rl.facility_id = v_facility_id
      AND rl."charged?" = true AND COALESCE(rl.charge_weight_lbs, 0) > 0
      AND rl.roast_date::date >= (v_current_date - interval '92 days')
      AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend' OR rr.roast_type IS NULL)
    UNION ALL
    SELECT rl.roast_date::date
    FROM roast_log rl JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
      JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
    WHERE rc.coffee_item = p_origin_id AND rr.roast_type = 'Pre-Blend'
      AND rl.facility_id = v_facility_id AND rl."charged?" = true
      AND COALESCE(rl.charge_weight_lbs, 0) > 0
      AND rl.roast_date::date >= (v_current_date - interval '92 days')
  ) s;
  v_data_months := LEAST(3.0, GREATEST(
    (v_current_date - COALESCE(v_first_roast, v_current_date))::numeric / 30.6667, 0.5));
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

  -- Months of THIS ORIGIN's roast history present in the 92-day window.
  SELECT MIN(d) INTO v_first_roast FROM (
    SELECT rl.roast_date::date AS d
    FROM roast_log rl LEFT JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    WHERE rl.origin_id = p_origin_id AND rl.facility_id = v_facility_id
      AND rl."charged?" = true AND COALESCE(rl.charge_weight_lbs, 0) > 0
      AND rl.roast_date::date >= (v_current_date - interval '92 days')
      AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend' OR rr.roast_type IS NULL)
    UNION ALL
    SELECT rl.roast_date::date
    FROM roast_log rl JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
      JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
    WHERE rc.coffee_item = p_origin_id AND rr.roast_type = 'Pre-Blend'
      AND rl.facility_id = v_facility_id AND rl."charged?" = true
      AND COALESCE(rl.charge_weight_lbs, 0) > 0
      AND rl.roast_date::date >= (v_current_date - interval '92 days')
  ) s;
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

CREATE OR REPLACE FUNCTION public.trg_recalc_coffee_on_nudge()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
  v_usage_direct  numeric;
  v_usage_blend   numeric;
  v_total_usage   numeric;
  v_first_roast   date;
  v_days          numeric;
  v_timezone      text;
  v_current_date  date;
BEGIN
  IF pg_trigger_depth() > 1 THEN RETURN NEW; END IF;

  SELECT time_zone INTO v_timezone FROM facilities WHERE facility_id = NEW.facility_id;
  IF v_timezone IS NULL OR v_timezone = '' THEN v_timezone := 'Pacific/Honolulu'; END IF;
  v_current_date := (CURRENT_TIMESTAMP AT TIME ZONE v_timezone)::date;

  SELECT COALESCE(SUM(rl.charge_weight_lbs), 0) INTO v_usage_direct
  FROM roast_log rl
  LEFT JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
  WHERE rl.origin_id = NEW.origin_id
    AND rl.roast_date::date >= (v_current_date - interval '92 days')
    AND rl."charged?" = true
    AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend' OR rr.roast_type IS NULL)
    AND rl.facility_id = NEW.facility_id;

  SELECT COALESCE(SUM(rl.charge_weight_lbs * rc.percentage), 0) INTO v_usage_blend
  FROM roast_log rl
  JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
  JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
  WHERE rc.coffee_item = NEW.origin_id
    AND rr.roast_type = 'Pre-Blend'
    AND rl.roast_date::date >= (v_current_date - interval '92 days')
    AND rl."charged?" = true
    AND rl.facility_id = NEW.facility_id;

  v_total_usage := v_usage_direct + v_usage_blend;

  -- Days of THIS ORIGIN's roast history present in the window (cap 92, floor 14).
  SELECT MIN(d) INTO v_first_roast FROM (
    SELECT rl.roast_date::date AS d
    FROM roast_log rl LEFT JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    WHERE rl.origin_id = NEW.origin_id AND rl.facility_id = NEW.facility_id
      AND rl."charged?" = true AND COALESCE(rl.charge_weight_lbs, 0) > 0
      AND rl.roast_date::date >= (v_current_date - interval '92 days')
      AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend' OR rr.roast_type IS NULL)
    UNION ALL
    SELECT rl.roast_date::date
    FROM roast_log rl JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
      JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
    WHERE rc.coffee_item = NEW.origin_id AND rr.roast_type = 'Pre-Blend'
      AND rl.facility_id = NEW.facility_id AND rl."charged?" = true
      AND COALESCE(rl.charge_weight_lbs, 0) > 0
      AND rl.roast_date::date >= (v_current_date - interval '92 days')
  ) s;
  v_days := LEAST(92, GREATEST((v_current_date - COALESCE(v_first_roast, v_current_date))::numeric, 14));
  NEW.daily_usage_lbs := v_total_usage / v_days;

  NEW.par := calculate_par(NEW.origin_id);
  NEW.restock_level := calculate_restock_level(NEW.origin_id);
  NEW.to_order := GREATEST(0, NEW.par - COALESCE(NEW.in_stock, 0));
  RETURN NEW;
END;
$function$;
