-- Inventory becomes LOT-DRIVEN (single-planning-home model). Read-side only.
--
--  A. On-hand(group) = SUM of its lots' remaining_lbs. calculate_current_stock_lbs
--     (which feeds in_stock_lbs / in_stock / to_order_bags) now returns the lot
--     ledger sum instead of the count + purchases - roasts formula. Same
--     two-branch logic as recalculate_origin_total_stock (received-shipment lots,
--     voided excluded; + quick-add no-shipment lots).
--
--  B. Reorder(group) = trailing PHYSICAL depletion of its lots, taken from the
--     consumption ledger (roast_log_lot_consumption) keyed by each consumed lot's
--     HOME (coffee_inventory_purchased.origin) — NOT by recipe attribution. So a
--     borrowed lot's usage lands on its home group's reorder, automatically.
--
-- No trigger or column changes; columns refresh via the existing triggers (lot
-- change, manual count, hourly nudge). Borrow recording (write-side) is a
-- separate migration. See memory/project_lot_home_inventory.md.

-- ── A ────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.calculate_current_stock_lbs(p_origin_id text, p_facility_id text)
RETURNS numeric LANGUAGE plpgsql AS $function$
DECLARE v_total numeric;
BEGIN
  SELECT COALESCE(SUM(GREATEST(cip.remaining_lbs, 0)), 0) INTO v_total
    FROM public.coffee_inventory_purchased cip
    JOIN public.shipment_received sr ON sr.shipment_id = cip.shipment_id
   WHERE cip.origin = p_origin_id
     AND cip.facility_id = p_facility_id
     AND COALESCE(sr.voided, false) = false
     AND cip.remaining_lbs IS NOT NULL;

  SELECT v_total + COALESCE(SUM(GREATEST(cip.remaining_lbs, 0)), 0) INTO v_total
    FROM public.coffee_inventory_purchased cip
   WHERE cip.origin = p_origin_id
     AND cip.facility_id = p_facility_id
     AND cip.shipment_id IS NULL
     AND cip.remaining_lbs IS NOT NULL;

  RETURN v_total;
END;
$function$;

-- ── B: calculate_par ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.calculate_par(p_origin_id text)
RETURNS numeric LANGUAGE plpgsql AS $function$
DECLARE
  v_facility_id   text;
  v_usage         numeric;
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

  -- Physical depletion of THIS group's lots over the trailing window (by lot home).
  SELECT COALESCE(SUM(rlc.lbs_consumed), 0) INTO v_usage
  FROM roast_log_lot_consumption rlc
  JOIN coffee_inventory_purchased cip ON cip.origin_purchase_id = rlc.origin_purchase_id
  JOIN roast_log rl ON rl.roast_log_id = rlc.roast_log_id
  WHERE cip.origin = p_origin_id
    AND cip.facility_id = v_facility_id
    AND rl.roast_date::date >= (v_current_date - interval '92 days')
    AND rl."charged?" = true;

  SELECT MIN(rl.roast_date::date) INTO v_first_roast
  FROM roast_log_lot_consumption rlc
  JOIN coffee_inventory_purchased cip ON cip.origin_purchase_id = rlc.origin_purchase_id
  JOIN roast_log rl ON rl.roast_log_id = rlc.roast_log_id
  WHERE cip.origin = p_origin_id
    AND cip.facility_id = v_facility_id
    AND rl.roast_date::date >= (v_current_date - interval '92 days')
    AND rl."charged?" = true
    AND COALESCE(rlc.lbs_consumed, 0) > 0;

  v_data_months := LEAST(3.0, GREATEST(
    (v_current_date - COALESCE(v_first_roast, v_current_date))::numeric / 30.6667, 0.5));
  v_monthly_usage := v_usage / v_data_months;

  SELECT COALESCE(rc.target_months, 3) INTO v_target_months
  FROM coffee_inventory ci
  LEFT JOIN restock_category rc ON rc.restock_category_id = ci.restock_category_id
  WHERE ci.origin_id = p_origin_id LIMIT 1;
  IF v_target_months IS NULL THEN v_target_months := 3; END IF;

  SELECT COALESCE(
    (SELECT cp.value_number FROM company_parameters cp
     WHERE cp.parameter_id = '5131610b' AND cp.facility_id = v_facility_id LIMIT 1), 1.3
  ) INTO v_buffer;

  SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
  FROM coffee_inventory WHERE origin_id = p_origin_id AND facility_id = v_facility_id LIMIT 1;

  RETURN ROUND((v_monthly_usage * v_target_months * v_buffer) / NULLIF(v_bag_size, 0));
END;
$function$;

-- ── B: calculate_restock_level ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.calculate_restock_level(p_origin_id text)
RETURNS numeric LANGUAGE plpgsql AS $function$
DECLARE
  v_facility_id    text;
  v_usage          numeric;
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
  SELECT facility_id INTO v_facility_id
  FROM coffee_inventory WHERE origin_id = p_origin_id LIMIT 1;

  SELECT time_zone INTO v_timezone FROM facilities WHERE facility_id = v_facility_id;
  IF v_timezone IS NULL OR v_timezone = '' THEN v_timezone := 'Pacific/Honolulu'; END IF;
  v_current_date := (CURRENT_TIMESTAMP AT TIME ZONE v_timezone)::date;

  SELECT COALESCE(SUM(rlc.lbs_consumed), 0) INTO v_usage
  FROM roast_log_lot_consumption rlc
  JOIN coffee_inventory_purchased cip ON cip.origin_purchase_id = rlc.origin_purchase_id
  JOIN roast_log rl ON rl.roast_log_id = rlc.roast_log_id
  WHERE cip.origin = p_origin_id
    AND cip.facility_id = v_facility_id
    AND rl.roast_date::date >= (v_current_date - interval '92 days')
    AND rl."charged?" = true;

  SELECT MIN(rl.roast_date::date) INTO v_first_roast
  FROM roast_log_lot_consumption rlc
  JOIN coffee_inventory_purchased cip ON cip.origin_purchase_id = rlc.origin_purchase_id
  JOIN roast_log rl ON rl.roast_log_id = rlc.roast_log_id
  WHERE cip.origin = p_origin_id
    AND cip.facility_id = v_facility_id
    AND rl.roast_date::date >= (v_current_date - interval '92 days')
    AND rl."charged?" = true
    AND COALESCE(rlc.lbs_consumed, 0) > 0;

  v_data_months := LEAST(3.0, GREATEST(
    (v_current_date - COALESCE(v_first_roast, v_current_date))::numeric / 30.6667, 0.5));
  v_monthly_usage := v_usage / v_data_months;

  IF v_monthly_usage <= 0 THEN RETURN 0; END IF;

  SELECT COALESCE(rc.reorder_months, 1.5) INTO v_reorder_months
  FROM coffee_inventory ci
  LEFT JOIN restock_category rc ON rc.restock_category_id = ci.restock_category_id
  WHERE ci.origin_id = p_origin_id LIMIT 1;
  IF v_reorder_months IS NULL THEN v_reorder_months := 1.5; END IF;

  SELECT COALESCE(
    (SELECT cp.value_number FROM company_parameters cp
     WHERE cp.parameter_id = '5131610b' AND cp.facility_id = v_facility_id LIMIT 1), 1.3
  ) INTO v_buffer;

  SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
  FROM coffee_inventory WHERE origin_id = p_origin_id AND facility_id = v_facility_id LIMIT 1;

  v_result := CEILING((v_monthly_usage * v_reorder_months * v_buffer) / NULLIF(v_bag_size, 0));

  v_par := calculate_par(p_origin_id);
  IF v_par <= 0 THEN RETURN 0; END IF;

  RETURN LEAST(v_result, v_par);
END;
$function$;
