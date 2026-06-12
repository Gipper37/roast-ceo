-- ============================================================================
-- daily_usage_lbs: annualize over data actually available (match par fix)
-- ============================================================================
-- trg_recalc_coffee_on_nudge set daily_usage_lbs = 92-day usage / 92.0 — the
-- same flat-window assumption that 20260611000007 fixed for calculate_par /
-- calculate_restock_level. A newly-migrated facility with ~5.5 weeks of roast
-- history had its daily (and therefore the "avg weekly consumption" shown in
-- the inventory table) understated ~2.4x, inconsistent with the now-corrected
-- par. Divide by the days of roast history actually present instead — capped
-- at 92 (established facilities unchanged) and floored at 14.
-- ============================================================================

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
BEGIN
  IF pg_trigger_depth() > 1 THEN RETURN NEW; END IF;

  SELECT COALESCE(SUM(rl.charge_weight_lbs), 0) INTO v_usage_direct
  FROM roast_log rl
  LEFT JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
  WHERE rl.origin_id = NEW.origin_id
    AND rl.roast_date::date >= (CURRENT_DATE - interval '92 days')
    AND rl."charged?" = true
    AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend' OR rr.roast_type IS NULL)
    AND rl.facility_id = NEW.facility_id;

  SELECT COALESCE(SUM(rl.charge_weight_lbs * rc.percentage), 0) INTO v_usage_blend
  FROM roast_log rl
  JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
  JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
  WHERE rc.coffee_item = NEW.origin_id
    AND rr.roast_type = 'Pre-Blend'
    AND rl.roast_date::date >= (CURRENT_DATE - interval '92 days')
    AND rl."charged?" = true
    AND rl.facility_id = NEW.facility_id;

  v_total_usage := v_usage_direct + v_usage_blend;

  -- Days of roast history actually present in the window (cap 92, floor 14).
  SELECT MIN(rl.roast_date::date) INTO v_first_roast
  FROM roast_log rl
  WHERE rl.facility_id = NEW.facility_id
    AND rl."charged?" = true
    AND COALESCE(rl.charge_weight_lbs, 0) > 0
    AND rl.roast_date::date >= (CURRENT_DATE - interval '92 days');
  v_days := LEAST(92, GREATEST((CURRENT_DATE - COALESCE(v_first_roast, CURRENT_DATE))::numeric, 14));
  NEW.daily_usage_lbs := v_total_usage / v_days;

  NEW.par := calculate_par(NEW.origin_id);
  NEW.restock_level := calculate_restock_level(NEW.origin_id);
  NEW.to_order := GREATEST(0, NEW.par - COALESCE(NEW.in_stock, 0));
  RETURN NEW;
END;
$function$;
