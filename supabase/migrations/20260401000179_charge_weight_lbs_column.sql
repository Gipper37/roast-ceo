-- Migration 00179: Add charge_weight_lbs stored numeric column
-- Fixes performance regression from JOIN pattern in migration 00177.
-- charge_weight stores UUID ref (AppSheet display), charge_weight_lbs stores numeric value.
-- All functions/views use charge_weight_lbs directly — no JOIN needed.
-- Column added and populated via psql (session_replication_role=replica).

-- ── Trigger: maintain charge_weight_lbs on INSERT/UPDATE ─────────────────────
CREATE OR REPLACE FUNCTION public.trg_stamp_roasted_weight()
RETURNS trigger LANGUAGE plpgsql AS $function$
DECLARE
    v_retention     numeric;
    v_tz            text;
BEGIN
    -- Resolve charge_weight UUID → numeric and store in charge_weight_lbs
    SELECT cwo.charge_weight INTO NEW.charge_weight_lbs
    FROM public.charge_weight_options cwo
    WHERE cwo.id = NEW.charge_weight LIMIT 1;

    -- Fallback for any legacy numeric string
    IF NEW.charge_weight_lbs IS NULL AND NEW.charge_weight ~ '^[0-9]+(\.[0-9]+)?$' THEN
        NEW.charge_weight_lbs := NEW.charge_weight::numeric;
    END IF;

    -- 3-tier retention factor
    SELECT value_number INTO v_retention FROM company_parameters
    WHERE parameter_id = '1de271df' AND facility_id = NEW.facility_id LIMIT 1;
    IF v_retention IS NULL OR v_retention = 0 THEN
        SELECT amount INTO v_retention FROM standard_parameters WHERE parameters_id = '1de271df' LIMIT 1;
    END IF;
    IF v_retention IS NULL OR v_retention = 0 THEN v_retention := 0.82; END IF;

    NEW.roasted_weight := ROUND(COALESCE(NEW.charge_weight_lbs, 0) * v_retention, 2);

    -- Populate roast_date_utc from local roast_date
    SELECT COALESCE(time_zone, 'UTC') INTO v_tz
    FROM public.facilities WHERE facility_id = NEW.facility_id;
    IF NEW.roast_date IS NOT NULL THEN
        NEW.roast_date_utc := NEW.roast_date AT TIME ZONE v_tz;
    END IF;

    RETURN NEW;
END;
$function$;

-- ── Functions: use charge_weight_lbs directly ────────────────────────────────

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
    SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
    FROM coffee_inventory WHERE origin_id = p_origin_id AND facility_id = p_facility_id LIMIT 1;

    SELECT last_inventory::DATE, COALESCE(inventory_count_bags, 0)
    INTO v_last_inventory_date, v_inventory_bags
    FROM coffee_inventory WHERE origin_id = p_origin_id AND facility_id = p_facility_id;

    IF v_last_inventory_date IS NULL THEN v_last_inventory_date := '2000-01-01'; END IF;
    v_starting_lbs := v_inventory_bags * v_bag_size;

    SELECT COALESCE(SUM(p.amount), 0) INTO v_purchased_lbs
    FROM coffee_inventory_purchased p
    JOIN shipment_received s ON p.shipment_id = s.shipment_id
    WHERE p.origin = p_origin_id
      AND s.date_received IS NOT NULL
      AND s.date_received::DATE > v_last_inventory_date
      AND COALESCE(s.voided, false) = false
      AND p.facility_id = p_facility_id;

    SELECT COALESCE(SUM(rl.charge_weight_lbs), 0) INTO v_roasted_direct_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    WHERE rl.origin_id = p_origin_id
      AND rl.roast_date::DATE > v_last_inventory_date
      AND rl."charged?" = TRUE
      AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend')
      AND rl.facility_id = p_facility_id;

    SELECT COALESCE(SUM(rl.charge_weight_lbs * rc.percentage), 0) INTO v_roasted_blend_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
    WHERE rc.coffee_item = p_origin_id
      AND rr.roast_type = 'Pre-Blend'
      AND rl.roast_date::DATE > v_last_inventory_date
      AND rl."charged?" = TRUE
      AND rl.facility_id = p_facility_id;

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

    SELECT COALESCE(SUM(rl.charge_weight_lbs), 0) INTO v_usage_direct
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    WHERE rl.origin_id = p_origin_id
      AND rl.roast_date::DATE >= (CURRENT_DATE - INTERVAL '92 days')
      AND rl."charged?" = TRUE
      AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend')
      AND rl.facility_id = v_facility_id;

    SELECT COALESCE(SUM(rl.charge_weight_lbs * rc.percentage), 0) INTO v_usage_blend
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
    WHERE rc.coffee_item = p_origin_id
      AND rr.roast_type = 'Pre-Blend'
      AND rl.roast_date::DATE >= (CURRENT_DATE - INTERVAL '92 days')
      AND rl."charged?" = TRUE
      AND rl.facility_id = v_facility_id;

    v_monthly_usage := (v_usage_direct + v_usage_blend) / 3.0;

    SELECT value_number INTO v_par_multiple FROM company_parameters WHERE parameter_id = '3e6f5909' AND facility_id = v_facility_id;
    SELECT value_number INTO v_buffer FROM company_parameters WHERE parameter_id = '5131610b' AND facility_id = v_facility_id;
    SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size FROM coffee_inventory WHERE origin_id = p_origin_id AND facility_id = v_facility_id LIMIT 1;

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
    SELECT facility_id INTO v_facility_id FROM coffee_inventory WHERE origin_id = p_origin_id LIMIT 1;
    SELECT time_zone INTO v_timezone FROM facilities WHERE facility_id = v_facility_id;
    IF v_timezone IS NULL OR v_timezone = '' THEN v_timezone := 'Pacific/Honolulu'; END IF;
    v_current_date := (CURRENT_TIMESTAMP AT TIME ZONE v_timezone)::DATE;

    SELECT COALESCE(SUM(rl.charge_weight_lbs), 0) INTO v_usage_direct
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    WHERE rl.origin_id = p_origin_id
      AND rl.roast_date::DATE >= (v_current_date - INTERVAL '92 days')
      AND rl."charged?" = TRUE
      AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend')
      AND rl.facility_id = v_facility_id;

    SELECT COALESCE(SUM(rl.charge_weight_lbs * rc.percentage), 0) INTO v_usage_blend
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
    WHERE rc.coffee_item = p_origin_id
      AND rr.roast_type = 'Pre-Blend'
      AND rl.roast_date::DATE >= (v_current_date - INTERVAL '92 days')
      AND rl."charged?" = TRUE
      AND rl.facility_id = v_facility_id;

    v_monthly_usage := (v_usage_direct + v_usage_blend) / 3.0;

    SELECT value_number INTO v_trigger_multiple FROM company_parameters WHERE parameter_id = 'dae6cd4b' AND facility_id = v_facility_id;
    SELECT value_number INTO v_buffer FROM company_parameters WHERE parameter_id = '5131610b' AND facility_id = v_facility_id;
    SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size FROM coffee_inventory WHERE origin_id = p_origin_id AND facility_id = v_facility_id LIMIT 1;

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
    v_bag_size := COALESCE(NEW.bag_size::numeric, 154);
    NEW.par           := public.calculate_par(NEW.origin_id);
    NEW.restock_level := public.calculate_restock_level(NEW.origin_id);
    v_last_inventory_date := COALESCE(NEW.last_inventory::DATE, '2000-01-01');
    NEW.inventory_lbs     := COALESCE(NEW.inventory_count_bags, 0) * v_bag_size;

    SELECT COALESCE(SUM(p.amount), 0) INTO v_purchased_lbs
    FROM coffee_inventory_purchased p
    JOIN shipment_received s ON p.shipment_id = s.shipment_id
    WHERE p.origin = NEW.origin_id
      AND s.date_received IS NOT NULL
      AND s.date_received::DATE > v_last_inventory_date
      AND COALESCE(s.voided, false) = false
      AND p.facility_id = NEW.facility_id;

    SELECT COALESCE(SUM(rl.charge_weight_lbs), 0) INTO v_roasted_direct_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    WHERE rl.origin_id = NEW.origin_id
      AND rl.roast_date::DATE > v_last_inventory_date
      AND rl."charged?" = TRUE
      AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend')
      AND rl.facility_id = NEW.facility_id;

    SELECT COALESCE(SUM(rl.charge_weight_lbs * rc.percentage), 0) INTO v_roasted_blend_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
    WHERE rc.coffee_item = NEW.origin_id
      AND rr.roast_type = 'Pre-Blend'
      AND rl.roast_date::DATE > v_last_inventory_date
      AND rl."charged?" = TRUE
      AND rl.facility_id = NEW.facility_id;

    NEW.in_stock_lbs  := GREATEST(0, (NEW.inventory_lbs + v_purchased_lbs - v_roasted_direct_lbs - v_roasted_blend_lbs));
    NEW.in_stock      := NEW.in_stock_lbs / NULLIF(v_bag_size, 0);
    NEW.to_order_bags := GREATEST(0, COALESCE(NEW.par, 0) - NEW.in_stock);

    RETURN NEW;
END;
$function$;

-- ── Views: use charge_weight_lbs directly ────────────────────────────────────

CREATE OR REPLACE VIEW public.monthly_coffee_usage AS
SELECT
    (rl.facility_id || '_' || (date_trunc('month', rl.roast_date))::date) AS month_usage_id,
    (date_trunc('month', rl.roast_date))::date AS month_start,
    rl.facility_id, rl.company_id,
    round(sum(rl.charge_weight_lbs), 2) AS green_used_lbs,
    round(sum(rl.roasted_weight), 2) AS lbs_roasted,
    count(*)::integer AS batch_count,
    round((sum(rl.roasted_weight) / NULLIF(sum(rl.charge_weight_lbs), 0::numeric)) * 100::numeric, 1) AS retention_pct
FROM roast_log rl
WHERE rl."charged?" = true
GROUP BY date_trunc('month', rl.roast_date), rl.facility_id, rl.company_id;

CREATE OR REPLACE VIEW public.monthly_coffee_usage_by_origin AS
WITH roast_by_origin AS (
    SELECT rl.roast_date, rl.origin_id, rl.charge_weight_lbs AS green_used_lbs,
           rl.roasted_weight AS lbs_roasted, rl.facility_id, rl.company_id
    FROM roast_log rl
    WHERE rl.origin_id IS NOT NULL AND rl."charged?" = true
    UNION ALL
    SELECT rl.roast_date, rc.coffee_item AS origin_id,
           rl.charge_weight_lbs * rc.percentage AS green_used_lbs,
           rl.roasted_weight * rc.percentage AS lbs_roasted, rl.facility_id, rl.company_id
    FROM roast_log rl
    JOIN recipe_components rc ON rc.recipe_id = rl.recipe_id
    WHERE rl.origin_id IS NULL AND rl.recipe_id IS NOT NULL AND rl."charged?" = true
)
SELECT
    ((((r.facility_id || '_') || r.origin_id) || '_') || (date_trunc('month', r.roast_date))::date) AS month_origin_id,
    (date_trunc('month', r.roast_date))::date AS month_start,
    r.origin_id, ci.origin AS origin_name, r.facility_id, r.company_id,
    round(sum(r.green_used_lbs), 2) AS green_used_lbs,
    round(sum(r.lbs_roasted), 2) AS lbs_roasted
FROM roast_by_origin r
LEFT JOIN coffee_inventory ci ON ci.origin_id = r.origin_id AND ci.facility_id = r.facility_id
GROUP BY date_trunc('month', r.roast_date), r.origin_id, ci.origin, r.facility_id, r.company_id;

CREATE OR REPLACE VIEW public.weekly_grand_total AS
WITH facility_config AS (
    SELECT f.facility_id, f.company_id,
        COALESCE(NULLIF(f.time_zone, ''), 'UTC') AS timezone,
        COALESCE((SELECT cp.value_number::integer FROM company_parameters cp WHERE cp.parameter_id = 'RF1iFWjOh7' AND cp.facility_id = f.facility_id LIMIT 1), 1) AS roast_target_day,
        COALESCE((SELECT cp.value_number FROM company_parameters cp WHERE cp.parameter_id = '1de271df' AND cp.facility_id = f.facility_id LIMIT 1), 0.82) AS retention_rate,
        COALESCE((SELECT cp.value_number::integer FROM company_parameters cp WHERE cp.parameter_id = 'orders_reset_day' AND cp.facility_id = f.facility_id LIMIT 1),
                 (SELECT sp.amount::integer FROM standard_parameters sp WHERE sp.parameters_id = 'orders_reset_day' LIMIT 1), 6) AS orders_reset_day
    FROM facilities f
), calc AS (
    SELECT fc.facility_id, fc.company_id, fc.retention_rate,
        (CURRENT_TIMESTAMP AT TIME ZONE fc.timezone)::date - (((EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fc.timezone)::date)::integer - fc.orders_reset_day) + 7) % 7) AS order_week_start,
        (CURRENT_TIMESTAMP AT TIME ZONE fc.timezone)::date - (((EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fc.timezone)::date)::integer - fc.roast_target_day) + 7) % 7) AS roast_week_start
    FROM facility_config fc
)
SELECT
    facility_id AS open_order_total_id, facility_id, company_id,
    COALESCE((SELECT sum(od.roasted_weight) FROM order_details od JOIN orders o ON od.order_id = o.order_id WHERE o.order_date >= c.order_week_start AND o.facility_id = c.facility_id AND o.order_status <> 'Canceled'), 0::double precision) AS total_ordered_roasted,
    COALESCE((SELECT sum(od.roasted_weight) FROM order_details od JOIN orders o ON od.order_id = o.order_id WHERE o.order_date >= c.order_week_start AND o.facility_id = c.facility_id AND o.order_status <> 'Canceled'), 0::double precision) / NULLIF(retention_rate::double precision, 0) AS total_ordered_green,
    COALESCE((SELECT sum(rl.roasted_weight) FROM roast_log rl WHERE rl."charged?" = true AND rl.roast_date >= c.roast_week_start AND rl.facility_id = c.facility_id), 0::numeric) AS total_roasted,
    COALESCE((SELECT sum(rl.charge_weight_lbs) FROM roast_log rl WHERE rl."charged?" = true AND rl.roast_date >= c.roast_week_start AND rl.facility_id = c.facility_id), 0::numeric) AS total_roasted_green
FROM calc c;

DROP VIEW IF EXISTS public.weekly_coffee_stock_by_origin;
CREATE VIEW public.weekly_coffee_stock_by_origin AS
WITH direct_roasts AS (
    SELECT rl.roast_date::date AS roast_date, rl.origin_id, rl.facility_id, rl.charge_weight_lbs AS green_lbs
    FROM roast_log rl JOIN roast_recipes rr ON rr.recipe_id = rl.recipe_id
    WHERE rl.origin_id IS NOT NULL AND rl."charged?" = true AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend')
), blend_roasts AS (
    SELECT rl.roast_date::date AS roast_date, rc.coffee_item AS origin_id, rl.facility_id,
           rl.charge_weight_lbs * rc.percentage AS green_lbs
    FROM roast_log rl JOIN roast_recipes rr ON rr.recipe_id = rl.recipe_id
    JOIN recipe_components rc ON rc.recipe_id = rl.recipe_id
    WHERE rl.origin_id IS NULL AND rr.roast_type = 'Pre-Blend' AND rl."charged?" = true
), all_roasts AS (
    SELECT roast_date, origin_id, facility_id, green_lbs FROM direct_roasts
    UNION ALL SELECT roast_date, origin_id, facility_id, green_lbs FROM blend_roasts
), all_purchases AS (
    SELECT sr.date_received AS received_date, p.origin AS origin_id, p.facility_id, p.amount AS purchased_lbs
    FROM coffee_inventory_purchased p JOIN shipment_received sr ON sr.shipment_id = p.shipment_id
    WHERE sr.date_received IS NOT NULL AND COALESCE(sr.voided, false) = false
), origins AS (
    SELECT DISTINCT ci.origin_id, ci.facility_id, ci.company_id, ci.bag_size, ci.origin AS origin_name
    FROM coffee_inventory ci WHERE ci.origin_id IS NOT NULL
), date_spine AS (
    SELECT o.origin_id, o.facility_id, o.company_id, o.bag_size, o.origin_name, gs.week_start::date AS week_start
    FROM origins o JOIN LATERAL generate_series(date_trunc('week', now() - '1 year'::interval), date_trunc('week', now()), '7 days'::interval) gs(week_start) ON true
)
SELECT ((facility_id || '_') || origin_id || '_' || week_start) AS week_stock_id,
    week_start, origin_id, origin_name, facility_id, company_id,
    GREATEST(0::numeric, (
        COALESCE((SELECT ci.inventory_count_bags * ci.bag_size::numeric FROM coffee_inventory ci WHERE ci.origin_id = ds.origin_id AND ci.facility_id = ds.facility_id LIMIT 1), 0)
        + COALESCE((SELECT sum(p.purchased_lbs) FROM all_purchases p WHERE p.origin_id = ds.origin_id AND p.facility_id = ds.facility_id AND p.received_date > (SELECT COALESCE(ci.last_inventory, '1970-01-01'::date) FROM coffee_inventory ci WHERE ci.origin_id = ds.origin_id AND ci.facility_id = ds.facility_id LIMIT 1) AND p.received_date <= ds.week_start), 0)
        - COALESCE((SELECT sum(r.green_lbs) FROM all_roasts r WHERE r.origin_id = ds.origin_id AND r.facility_id = ds.facility_id AND r.roast_date > (SELECT COALESCE(ci.last_inventory, '1970-01-01'::date) FROM coffee_inventory ci WHERE ci.origin_id = ds.origin_id AND ci.facility_id = ds.facility_id LIMIT 1) AND r.roast_date <= ds.week_start), 0)
    )) AS stock_lbs
FROM date_spine ds;

DROP VIEW IF EXISTS public.roast_detail;
CREATE VIEW public.roast_detail AS
WITH facility_params AS (
    SELECT f.facility_id, f.company_id, COALESCE(NULLIF(f.time_zone, ''), 'Pacific/Honolulu') AS timezone,
        COALESCE((SELECT cp.value_number::integer FROM company_parameters cp WHERE cp.parameter_id = 'RF1iFWjOh7' AND cp.facility_id = f.facility_id LIMIT 1), 4) AS roast_reset_day,
        COALESCE((SELECT cp.value_number FROM company_parameters cp WHERE cp.parameter_id = '761fd894' AND cp.facility_id = f.facility_id LIMIT 1), 25::numeric) AS charge_weight,
        COALESCE((SELECT cp.value_number FROM company_parameters cp WHERE cp.parameter_id = '1de271df' AND cp.facility_id = f.facility_id LIMIT 1), 0.82) AS retention_rate
    FROM facilities f
), calc AS (
    SELECT fp.facility_id, fp.company_id, fp.timezone, fp.charge_weight, fp.retention_rate,
        (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date - (((EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date)::integer - fp.roast_reset_day) + 7) % 7) AS roast_week_start
    FROM facility_params fp
), origin_facility AS (
    SELECT DISTINCT rc.coffee_item AS origin, f.facility_id, f.company_id
    FROM recipe_components rc JOIN roast_recipes rr ON rc.recipe_id = rr.recipe_id
    JOIN facilities f ON f.company_id = rr.company_id AND (rr.facility_id IS NULL OR rr.facility_id = f.facility_id)
), per_origin AS (
    SELECT of2.origin, of2.facility_id, of2.company_id,
        (COALESCE((SELECT sum(rsl.lbs_in_stock) FROM roast_stock_log rsl WHERE rsl.origin_id = of2.origin AND rsl.facility_id = of2.facility_id AND (rsl.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start), 0)
         + COALESCE((SELECT sum(rsl.lbs_in_stock * rc.percentage) FROM roast_stock_log rsl JOIN recipe_components rc ON rsl.blend_id = rc.recipe_id WHERE rc.coffee_item = of2.origin AND rsl.facility_id = of2.facility_id AND (rsl.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start), 0)) AS in_stock_roasted,
        COALESCE((SELECT sum(od.quantity * p.weight_lbs * rc.percentage) FROM order_details od JOIN orders o ON od.order_id = o.order_id JOIN products p ON od.product_id = p.product_id JOIN recipe_components rc ON p.recipe_id = rc.recipe_id WHERE rc.coffee_item = of2.origin AND o.order_status = 'Open' AND o.facility_id = of2.facility_id), 0) AS total_ordered,
        (COALESCE((SELECT sum(rl.roasted_weight) FROM roast_log rl WHERE rl.origin_id = of2.origin AND rl."charged?" = true AND rl.roast_date >= c.roast_week_start AND rl.facility_id = of2.facility_id), 0)
         + COALESCE((SELECT sum(rl.roasted_weight * rc.percentage) FROM roast_log rl JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id WHERE rr.roast_type = 'Pre-Blend' AND rc.coffee_item = of2.origin AND rl."charged?" = true AND rl.roast_date >= c.roast_week_start AND rl.facility_id = of2.facility_id), 0)) AS total_roasted,
        c.retention_rate,
        COALESCE((SELECT avg(rl.charge_weight_lbs) FROM (SELECT charge_weight_lbs FROM roast_log WHERE origin_id = of2.origin AND facility_id = of2.facility_id AND charge_weight_lbs > 0 ORDER BY roast_date DESC LIMIT 5) rl), c.charge_weight, 25::numeric) AS effective_charge_weight
    FROM origin_facility of2 JOIN calc c ON c.facility_id = of2.facility_id
)
SELECT (origin || '-' || facility_id) AS roast_detail_id, origin, facility_id, company_id,
    in_stock_roasted, total_roasted, total_ordered,
    GREATEST(0::numeric, (total_ordered - in_stock_roasted) - total_roasted) AS final_roasted_weight,
    GREATEST(0::numeric, (total_ordered - in_stock_roasted) - total_roasted) / NULLIF(retention_rate, 0) AS green_to_roast,
    (GREATEST(0::numeric, (total_ordered - in_stock_roasted) - total_roasted) / NULLIF(retention_rate, 0)) / NULLIF(effective_charge_weight, 0) AS roasts_remaining
FROM per_origin;

DROP VIEW IF EXISTS public.roast_detail_by_blend;
CREATE VIEW public.roast_detail_by_blend AS
WITH facility_params AS (
    SELECT f.facility_id, f.company_id, COALESCE(NULLIF(f.time_zone, ''), 'Pacific/Honolulu') AS timezone,
        COALESCE((SELECT cp.value_number::integer FROM company_parameters cp WHERE cp.parameter_id = 'RF1iFWjOh7' AND cp.facility_id = f.facility_id LIMIT 1), 4) AS roast_reset_day,
        COALESCE((SELECT cp.value_number FROM company_parameters cp WHERE cp.parameter_id = '761fd894' AND cp.facility_id = f.facility_id LIMIT 1), 25::numeric) AS charge_weight,
        COALESCE((SELECT cp.value_number FROM company_parameters cp WHERE cp.parameter_id = '1de271df' AND cp.facility_id = f.facility_id LIMIT 1), 0.82) AS retention_rate
    FROM facilities f
), calc AS (
    SELECT fp.facility_id, fp.company_id, fp.timezone, fp.charge_weight, fp.retention_rate,
        (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date - (((EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date)::integer - fp.roast_reset_day) + 7) % 7) AS roast_week_start
    FROM facility_params fp
), recipe_facility AS (
    SELECT rr.recipe_id, f.facility_id, f.company_id FROM roast_recipes rr
    JOIN facilities f ON f.company_id = rr.company_id AND (rr.facility_id IS NULL OR rr.facility_id = f.facility_id)
), per_recipe AS (
    SELECT rf.recipe_id, rf.facility_id, rf.company_id,
        COALESCE(stock.in_stock_roasted, 0::numeric) AS in_stock_roasted,
        COALESCE(ordered.total_ordered, 0::double precision) AS total_ordered,
        COALESCE(roasted.total_roasted, 0::numeric) AS total_roasted,
        c.retention_rate,
        COALESCE((SELECT avg(rl.charge_weight_lbs) FROM (SELECT charge_weight_lbs FROM roast_log WHERE recipe_id = rf.recipe_id AND facility_id = rf.facility_id AND charge_weight_lbs > 0 ORDER BY roast_date DESC LIMIT 5) rl), c.charge_weight, 25::numeric) AS effective_charge_weight
    FROM recipe_facility rf JOIN calc c ON c.facility_id = rf.facility_id
    LEFT JOIN LATERAL (SELECT COALESCE(sum(rsl.lbs_in_stock), 0) AS in_stock_roasted FROM roast_stock_log rsl WHERE rsl.blend_id = rf.recipe_id AND rsl.facility_id = rf.facility_id AND (rsl.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start) stock ON true
    LEFT JOIN LATERAL (SELECT sum(od.roasted_weight) AS total_ordered FROM order_details od JOIN orders o ON od.order_id = o.order_id JOIN products p ON od.product_id = p.product_id WHERE p.recipe_id = rf.recipe_id AND o.order_status = 'Open' AND o.facility_id = rf.facility_id) ordered ON true
    LEFT JOIN LATERAL (SELECT sum(rl.roasted_weight) AS total_roasted FROM roast_log rl WHERE rl.recipe_id = rf.recipe_id AND rl."charged?" = true AND rl.roast_date >= c.roast_week_start AND rl.facility_id = rf.facility_id) roasted ON true
)
SELECT (recipe_id || '-' || facility_id) AS roast_blend_id, recipe_id, facility_id, company_id,
    in_stock_roasted, total_ordered, total_roasted,
    GREATEST(0::double precision, (total_ordered - in_stock_roasted::double precision) - total_roasted::double precision) AS roasted_left,
    (GREATEST(0::double precision, (total_ordered - in_stock_roasted::double precision) - total_roasted::double precision) / NULLIF(retention_rate, 0)::double precision) / NULLIF(effective_charge_weight, 0)::double precision AS roasts_remaining
FROM per_recipe;
