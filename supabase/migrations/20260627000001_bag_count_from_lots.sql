-- Derive the group bag COUNT from the lots/sources instead of a single group
-- bag_size. The group's coffee_inventory.bag_size (e.g. 132) often disagrees with
-- its lots' real bag size (e.g. 152), so the cached in_stock bag count (lbs /
-- group_bag_size) over/under-counted vs the per-source view (Σ lbs / lot bag_size).
-- e.g. MCR Fruit showed 19.6 vs the lot's 17; Chocolate 42.8 vs 37.2.
--
-- Approach (keeps the column, stops USING it for counts):
--   • get_effective_bag_size(origin,facility) — one scalar size for usage→bags
--     conversions (par/restock): active source -> newest in-stock lot -> most
--     common lot size -> 152.
--   • current_stock_bags_exact(origin,facility) — true bag count = Σ over in-stock
--     lots of remaining_lbs / that lot's own bag_size (per-lot fallback to the
--     effective size when a lot has no bag_size). Mirrors calculate_current_stock_lbs's
--     lot selection (received-non-voided + baseline shipment_id NULL).
--   • A single BEFORE trigger on coffee_inventory sets in_stock + to_order_bags
--     from the lots on every write, so all stock writers (lot change, roast, void,
--     manual) land the correct count without rewriting each. Named to run last.
--   • par/restock now divide usage by get_effective_bag_size (was group bag_size),
--     so the displayed par/restock bags match the corrected count.
-- The reorder SIGNAL is bag_size-independent (lbs vs lbs), so this corrects the
-- displayed bag numbers without changing who needs reordering.

-- ── 1. effective scalar bag size (for usage→bags) ──────────────────────────────
CREATE OR REPLACE FUNCTION public.get_effective_bag_size(p_origin_id text, p_facility_id text)
RETURNS numeric LANGUAGE plpgsql AS $function$
DECLARE v numeric;
BEGIN
  -- a) active (loaded) source's bag size
  SELECT NULLIF(cs.bag_size,'')::numeric INTO v
    FROM public.coffee_inventory ci
    JOIN public.coffee_source cs ON cs.coffee_source_id = ci.active_coffee_source_id
   WHERE ci.origin_id = p_origin_id AND ci.facility_id = p_facility_id LIMIT 1;
  IF v IS NOT NULL AND v > 0 THEN RETURN v; END IF;
  -- b) newest in-stock lot's bag size
  SELECT NULLIF(cip.bag_size,'')::numeric INTO v
    FROM public.coffee_inventory_purchased cip
    LEFT JOIN public.shipment_received sr ON sr.shipment_id = cip.shipment_id
   WHERE cip.origin = p_origin_id AND cip.facility_id = p_facility_id
     AND COALESCE(cip.remaining_lbs,0) > 0 AND NULLIF(cip.bag_size,'') IS NOT NULL
   ORDER BY COALESCE(sr.date_received, cip.created_at::date) DESC NULLS LAST, cip.created_at DESC
   LIMIT 1;
  IF v IS NOT NULL AND v > 0 THEN RETURN v; END IF;
  -- c) most common lot bag size for the group (any lot)
  SELECT NULLIF(cip.bag_size,'')::numeric INTO v
    FROM public.coffee_inventory_purchased cip
   WHERE cip.origin = p_origin_id AND cip.facility_id = p_facility_id
     AND NULLIF(cip.bag_size,'') IS NOT NULL
   GROUP BY cip.bag_size ORDER BY count(*) DESC LIMIT 1;
  IF v IS NOT NULL AND v > 0 THEN RETURN v; END IF;
  -- d) default
  RETURN 152;
END; $function$;

-- ── 2. true bag count = Σ per-lot (remaining_lbs / lot bag_size) ───────────────
CREATE OR REPLACE FUNCTION public.current_stock_bags_exact(p_origin_id text, p_facility_id text)
RETURNS numeric LANGUAGE plpgsql AS $function$
DECLARE v_eff numeric; v_total numeric;
BEGIN
  IF p_origin_id IS NULL OR p_facility_id IS NULL THEN RETURN 0; END IF;
  v_eff := public.get_effective_bag_size(p_origin_id, p_facility_id);
  -- received, non-voided lots
  SELECT COALESCE(SUM(GREATEST(cip.remaining_lbs,0)
            / NULLIF(COALESCE(NULLIF(cip.bag_size,'')::numeric, v_eff), 0)), 0)
    INTO v_total
    FROM public.coffee_inventory_purchased cip
    JOIN public.shipment_received sr ON sr.shipment_id = cip.shipment_id
   WHERE cip.origin = p_origin_id AND cip.facility_id = p_facility_id
     AND COALESCE(sr.voided,false) = false AND cip.remaining_lbs IS NOT NULL;
  -- baseline (shipment-less) lots
  SELECT v_total + COALESCE(SUM(GREATEST(cip.remaining_lbs,0)
            / NULLIF(COALESCE(NULLIF(cip.bag_size,'')::numeric, v_eff), 0)), 0)
    INTO v_total
    FROM public.coffee_inventory_purchased cip
   WHERE cip.origin = p_origin_id AND cip.facility_id = p_facility_id
     AND cip.shipment_id IS NULL AND cip.remaining_lbs IS NOT NULL;
  RETURN COALESCE(v_total, 0);
END; $function$;

-- ── 3. single trigger: in_stock + to_order_bags always from the lots ───────────
CREATE OR REPLACE FUNCTION public.sync_in_stock_bags() RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
  IF NEW.origin_id IS NOT NULL AND NEW.facility_id IS NOT NULL THEN
    NEW.in_stock := public.current_stock_bags_exact(NEW.origin_id, NEW.facility_id);
    NEW.to_order_bags := GREATEST(0, COALESCE(NEW.par,0) - NEW.in_stock);
  END IF;
  RETURN NEW;
END; $function$;
-- 'zzz_' so it runs LAST among BEFORE triggers (final say on in_stock).
DROP TRIGGER IF EXISTS trg_zzz_sync_in_stock_bags ON public.coffee_inventory;
CREATE TRIGGER trg_zzz_sync_in_stock_bags
  BEFORE INSERT OR UPDATE ON public.coffee_inventory
  FOR EACH ROW EXECUTE FUNCTION public.sync_in_stock_bags();

-- ── 4. par / restock divide by the EFFECTIVE bag size (was group bag_size) ─────
CREATE OR REPLACE FUNCTION public.calculate_par(p_origin_id text)
 RETURNS numeric LANGUAGE plpgsql AS $function$
DECLARE
  v_facility_id   text; v_usage numeric; v_usage_blend numeric; v_monthly_usage numeric;
  v_target_months numeric; v_buffer numeric; v_bag_size numeric;
  v_first_roast date; v_data_months numeric; v_timezone text; v_current_date date;
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

  SELECT COALESCE(rc.target_months, 3) INTO v_target_months
  FROM coffee_inventory ci LEFT JOIN restock_category rc ON rc.restock_category_id = ci.restock_category_id
  WHERE ci.origin_id = p_origin_id LIMIT 1;
  IF v_target_months IS NULL THEN v_target_months := 3; END IF;

  SELECT COALESCE((SELECT cp.value_number FROM company_parameters cp
     WHERE cp.parameter_id = '5131610b' AND cp.facility_id = v_facility_id LIMIT 1), 1.3) INTO v_buffer;

  v_bag_size := public.get_effective_bag_size(p_origin_id, v_facility_id);

  RETURN ROUND((v_monthly_usage * v_target_months * v_buffer) / NULLIF(v_bag_size, 0));
END; $function$;

CREATE OR REPLACE FUNCTION public.calculate_restock_level(p_origin_id text)
 RETURNS numeric LANGUAGE plpgsql AS $function$
DECLARE
  v_facility_id text; v_usage numeric; v_usage_blend numeric; v_monthly_usage numeric;
  v_reorder_months numeric; v_buffer numeric; v_bag_size numeric; v_current_date date;
  v_timezone text; v_par numeric; v_result numeric; v_first_roast date; v_data_months numeric;
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

  v_bag_size := public.get_effective_bag_size(p_origin_id, v_facility_id);

  v_result := CEILING((v_monthly_usage * v_reorder_months * v_buffer) / NULLIF(v_bag_size, 0));

  v_par := calculate_par(p_origin_id);
  IF v_par <= 0 THEN RETURN 0; END IF;

  RETURN LEAST(v_result, v_par);
END; $function$;

-- ── 5. backfill ───────────────────────────────────────────────────────────────
-- (No lot bag_size backfill: current_stock_bags_exact already falls back to the
--  effective size for null-bag lots, and coffee_inventory_purchased.bag_size is
--  FK-constrained to bag_sizes so we can't write an arbitrary literal. Going
--  forward, bag_size becomes required at source-add.)
-- Recompute par/restock for every group; the BEFORE trigger then lands the
-- correct in_stock + to_order_bags from the lots.
UPDATE public.coffee_inventory ci
   SET par = public.calculate_par(ci.origin_id),
       restock_level = public.calculate_restock_level(ci.origin_id)
 WHERE ci.origin_id IS NOT NULL AND ci.facility_id IS NOT NULL;
