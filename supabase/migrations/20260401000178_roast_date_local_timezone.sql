-- Migration 00178: roast_date now stores local facility time (timestamp without time zone)
-- roast_date_utc stores the true UTC value (timestamptz)
--
-- Data migration and column type change were run directly via psql:
--   1. ALTER TABLE roast_log ADD COLUMN roast_date_utc timestamptz (populated from roast_date)
--   2. UPDATE: converted roast_date to local time per facility timezone (session_replication_role=replica)
--   3. Dropped 6 dependent views
--   4. ALTER COLUMN roast_date TYPE timestamp WITHOUT TIME ZONE USING roast_date AT TIME ZONE 'UTC'
--
-- This migration: recreate views + update trigger to populate roast_date_utc on new rows

-- ── Recreate views ───────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW public.monthly_coffee_usage AS
SELECT
    (rl.facility_id || '_' || (date_trunc('month', rl.roast_date))::date) AS month_usage_id,
    (date_trunc('month', rl.roast_date))::date AS month_start,
    rl.facility_id,
    rl.company_id,
    round(sum(cwo.charge_weight), 2) AS green_used_lbs,
    round(sum(rl.roasted_weight), 2) AS lbs_roasted,
    count(*)::integer AS batch_count,
    round((sum(rl.roasted_weight) / NULLIF(sum(cwo.charge_weight), 0::numeric)) * 100::numeric, 1) AS retention_pct
FROM roast_log rl
JOIN charge_weight_options cwo ON cwo.id = rl.charge_weight
WHERE rl."charged?" = true
GROUP BY date_trunc('month', rl.roast_date), rl.facility_id, rl.company_id;

CREATE OR REPLACE VIEW public.monthly_coffee_usage_by_origin AS
WITH roast_by_origin AS (
    SELECT rl.roast_date, rl.origin_id, cwo.charge_weight AS green_used_lbs,
           rl.roasted_weight AS lbs_roasted, rl.facility_id, rl.company_id
    FROM roast_log rl
    JOIN charge_weight_options cwo ON cwo.id = rl.charge_weight
    WHERE rl.origin_id IS NOT NULL AND rl."charged?" = true
    UNION ALL
    SELECT rl.roast_date, rc.coffee_item AS origin_id,
           cwo.charge_weight * rc.percentage AS green_used_lbs,
           rl.roasted_weight * rc.percentage AS lbs_roasted, rl.facility_id, rl.company_id
    FROM roast_log rl
    JOIN recipe_components rc ON rc.recipe_id = rl.recipe_id
    JOIN charge_weight_options cwo ON cwo.id = rl.charge_weight
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
        COALESCE((SELECT cp.value_number::integer FROM company_parameters cp
                  WHERE cp.parameter_id = 'RF1iFWjOh7' AND cp.facility_id = f.facility_id LIMIT 1), 1) AS roast_target_day,
        COALESCE((SELECT cp.value_number FROM company_parameters cp
                  WHERE cp.parameter_id = '1de271df' AND cp.facility_id = f.facility_id LIMIT 1), 0.82) AS retention_rate,
        COALESCE((SELECT cp.value_number::integer FROM company_parameters cp
                  WHERE cp.parameter_id = 'orders_reset_day' AND cp.facility_id = f.facility_id LIMIT 1),
                 (SELECT sp.amount::integer FROM standard_parameters sp
                  WHERE sp.parameters_id = 'orders_reset_day' LIMIT 1), 6) AS orders_reset_day
    FROM facilities f
), calc AS (
    SELECT fc.facility_id, fc.company_id, fc.retention_rate,
        (CURRENT_TIMESTAMP AT TIME ZONE fc.timezone)::date
            - (((EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fc.timezone)::date)::integer - fc.orders_reset_day) + 7) % 7) AS order_week_start,
        (CURRENT_TIMESTAMP AT TIME ZONE fc.timezone)::date
            - (((EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fc.timezone)::date)::integer - fc.roast_target_day) + 7) % 7) AS roast_week_start
    FROM facility_config fc
)
SELECT
    facility_id AS open_order_total_id, facility_id, company_id,
    COALESCE((SELECT sum(od.roasted_weight) FROM order_details od JOIN orders o ON od.order_id = o.order_id
              WHERE o.order_date >= c.order_week_start AND o.facility_id = c.facility_id
                AND o.order_status <> 'Canceled'), 0::double precision) AS total_ordered_roasted,
    COALESCE((SELECT sum(od.roasted_weight) FROM order_details od JOIN orders o ON od.order_id = o.order_id
              WHERE o.order_date >= c.order_week_start AND o.facility_id = c.facility_id
                AND o.order_status <> 'Canceled'), 0::double precision)
        / NULLIF(retention_rate::double precision, 0) AS total_ordered_green,
    COALESCE((SELECT sum(rl.roasted_weight) FROM roast_log rl
              WHERE rl."charged?" = true AND rl.roast_date >= c.roast_week_start AND rl.facility_id = c.facility_id), 0::numeric) AS total_roasted,
    COALESCE((SELECT sum(cwo.charge_weight) FROM roast_log rl
              JOIN charge_weight_options cwo ON cwo.id = rl.charge_weight
              WHERE rl."charged?" = true AND rl.roast_date >= c.roast_week_start AND rl.facility_id = c.facility_id), 0::numeric) AS total_roasted_green
FROM calc c;

CREATE VIEW public.weekly_coffee_stock_by_origin AS
WITH direct_roasts AS (
    SELECT rl.roast_date::date AS roast_date, rl.origin_id, rl.facility_id, cwo.charge_weight AS green_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rr.recipe_id = rl.recipe_id
    JOIN charge_weight_options cwo ON cwo.id = rl.charge_weight
    WHERE rl.origin_id IS NOT NULL AND rl."charged?" = true AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend')
), blend_roasts AS (
    SELECT rl.roast_date::date AS roast_date, rc.coffee_item AS origin_id, rl.facility_id,
           cwo.charge_weight * rc.percentage AS green_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rr.recipe_id = rl.recipe_id
    JOIN recipe_components rc ON rc.recipe_id = rl.recipe_id
    JOIN charge_weight_options cwo ON cwo.id = rl.charge_weight
    WHERE rl.origin_id IS NULL AND rr.roast_type = 'Pre-Blend' AND rl."charged?" = true
), all_roasts AS (
    SELECT roast_date, origin_id, facility_id, green_lbs FROM direct_roasts
    UNION ALL
    SELECT roast_date, origin_id, facility_id, green_lbs FROM blend_roasts
), all_purchases AS (
    SELECT sr.date_received AS received_date, p.origin AS origin_id, p.facility_id, p.amount AS purchased_lbs
    FROM coffee_inventory_purchased p
    JOIN shipment_received sr ON sr.shipment_id = p.shipment_id
    WHERE sr.date_received IS NOT NULL AND COALESCE(sr.voided, false) = false
), origins AS (
    SELECT DISTINCT ci.origin_id, ci.facility_id, ci.company_id, ci.bag_size, ci.origin AS origin_name
    FROM coffee_inventory ci WHERE ci.origin_id IS NOT NULL
), date_spine AS (
    SELECT o.origin_id, o.facility_id, o.company_id, o.bag_size, o.origin_name, gs.week_start::date AS week_start
    FROM origins o
    JOIN LATERAL generate_series(date_trunc('week', now() - '1 year'::interval), date_trunc('week', now()), '7 days'::interval) gs(week_start) ON true
)
SELECT
    ((facility_id || '_') || origin_id || '_' || week_start) AS week_stock_id,
    week_start, origin_id, origin_name, facility_id, company_id,
    GREATEST(0::numeric, (
        COALESCE((SELECT ci.inventory_count_bags * ci.bag_size::numeric FROM coffee_inventory ci
                  WHERE ci.origin_id = ds.origin_id AND ci.facility_id = ds.facility_id LIMIT 1), 0)
        + COALESCE((SELECT sum(p.purchased_lbs) FROM all_purchases p
                    WHERE p.origin_id = ds.origin_id AND p.facility_id = ds.facility_id
                      AND p.received_date > (SELECT COALESCE(ci.last_inventory, '1970-01-01'::date) FROM coffee_inventory ci WHERE ci.origin_id = ds.origin_id AND ci.facility_id = ds.facility_id LIMIT 1)
                      AND p.received_date <= ds.week_start), 0)
        - COALESCE((SELECT sum(r.green_lbs) FROM all_roasts r
                    WHERE r.origin_id = ds.origin_id AND r.facility_id = ds.facility_id
                      AND r.roast_date > (SELECT COALESCE(ci.last_inventory, '1970-01-01'::date) FROM coffee_inventory ci WHERE ci.origin_id = ds.origin_id AND ci.facility_id = ds.facility_id LIMIT 1)
                      AND r.roast_date <= ds.week_start), 0)
    )) AS stock_lbs
FROM date_spine ds;

CREATE VIEW public.roast_detail AS
WITH facility_params AS (
    SELECT f.facility_id, f.company_id,
        COALESCE(NULLIF(f.time_zone, ''), 'Pacific/Honolulu') AS timezone,
        COALESCE((SELECT cp.value_number::integer FROM company_parameters cp WHERE cp.parameter_id = 'RF1iFWjOh7' AND cp.facility_id = f.facility_id LIMIT 1), 4) AS roast_reset_day,
        COALESCE((SELECT cp.value_number FROM company_parameters cp WHERE cp.parameter_id = '761fd894' AND cp.facility_id = f.facility_id LIMIT 1), 25::numeric) AS charge_weight,
        COALESCE((SELECT cp.value_number FROM company_parameters cp WHERE cp.parameter_id = '1de271df' AND cp.facility_id = f.facility_id LIMIT 1), 0.82) AS retention_rate
    FROM facilities f
), calc AS (
    SELECT fp.facility_id, fp.company_id, fp.timezone, fp.charge_weight, fp.retention_rate,
        (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date
            - (((EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date)::integer - fp.roast_reset_day) + 7) % 7) AS roast_week_start
    FROM facility_params fp
), origin_facility AS (
    SELECT DISTINCT rc.coffee_item AS origin, f.facility_id, f.company_id
    FROM recipe_components rc
    JOIN roast_recipes rr ON rc.recipe_id = rr.recipe_id
    JOIN facilities f ON f.company_id = rr.company_id AND (rr.facility_id IS NULL OR rr.facility_id = f.facility_id)
), per_origin AS (
    SELECT of2.origin, of2.facility_id, of2.company_id,
        (COALESCE((SELECT sum(rsl.lbs_in_stock) FROM roast_stock_log rsl WHERE rsl.origin_id = of2.origin AND rsl.facility_id = of2.facility_id AND (rsl.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start), 0)
         + COALESCE((SELECT sum(rsl.lbs_in_stock * rc.percentage) FROM roast_stock_log rsl JOIN recipe_components rc ON rsl.blend_id = rc.recipe_id WHERE rc.coffee_item = of2.origin AND rsl.facility_id = of2.facility_id AND (rsl.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start), 0)) AS in_stock_roasted,
        COALESCE((SELECT sum(od.quantity * p.weight_lbs * rc.percentage) FROM order_details od JOIN orders o ON od.order_id = o.order_id JOIN products p ON od.product_id = p.product_id JOIN recipe_components rc ON p.recipe_id = rc.recipe_id WHERE rc.coffee_item = of2.origin AND o.order_status = 'Open' AND o.facility_id = of2.facility_id), 0) AS total_ordered,
        (COALESCE((SELECT sum(rl.roasted_weight) FROM roast_log rl WHERE rl.origin_id = of2.origin AND rl."charged?" = true AND rl.roast_date >= c.roast_week_start AND rl.facility_id = of2.facility_id), 0)
         + COALESCE((SELECT sum(rl.roasted_weight * rc.percentage) FROM roast_log rl JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id WHERE rr.roast_type = 'Pre-Blend' AND rc.coffee_item = of2.origin AND rl."charged?" = true AND rl.roast_date >= c.roast_week_start AND rl.facility_id = of2.facility_id), 0)) AS total_roasted,
        c.retention_rate,
        COALESCE(
            (SELECT avg(recent.cw) FROM (SELECT cwo2.charge_weight AS cw FROM roast_log rl JOIN charge_weight_options cwo2 ON cwo2.id = rl.charge_weight WHERE rl.origin_id = of2.origin AND rl.facility_id = of2.facility_id AND cwo2.charge_weight > 0 ORDER BY rl.roast_date DESC LIMIT 5) recent),
            c.charge_weight, 25::numeric
        ) AS effective_charge_weight
    FROM origin_facility of2 JOIN calc c ON c.facility_id = of2.facility_id
)
SELECT (origin || '-' || facility_id) AS roast_detail_id, origin, facility_id, company_id,
    in_stock_roasted, total_roasted, total_ordered,
    GREATEST(0::numeric, (total_ordered - in_stock_roasted) - total_roasted) AS final_roasted_weight,
    GREATEST(0::numeric, (total_ordered - in_stock_roasted) - total_roasted) / NULLIF(retention_rate, 0) AS green_to_roast,
    (GREATEST(0::numeric, (total_ordered - in_stock_roasted) - total_roasted) / NULLIF(retention_rate, 0)) / NULLIF(effective_charge_weight, 0) AS roasts_remaining
FROM per_origin;

CREATE VIEW public.roast_detail_by_blend AS
WITH facility_params AS (
    SELECT f.facility_id, f.company_id,
        COALESCE(NULLIF(f.time_zone, ''), 'Pacific/Honolulu') AS timezone,
        COALESCE((SELECT cp.value_number::integer FROM company_parameters cp WHERE cp.parameter_id = 'RF1iFWjOh7' AND cp.facility_id = f.facility_id LIMIT 1), 4) AS roast_reset_day,
        COALESCE((SELECT cp.value_number FROM company_parameters cp WHERE cp.parameter_id = '761fd894' AND cp.facility_id = f.facility_id LIMIT 1), 25::numeric) AS charge_weight,
        COALESCE((SELECT cp.value_number FROM company_parameters cp WHERE cp.parameter_id = '1de271df' AND cp.facility_id = f.facility_id LIMIT 1), 0.82) AS retention_rate
    FROM facilities f
), calc AS (
    SELECT fp.facility_id, fp.company_id, fp.timezone, fp.charge_weight, fp.retention_rate,
        (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date
            - (((EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date)::integer - fp.roast_reset_day) + 7) % 7) AS roast_week_start
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
        COALESCE(
            (SELECT avg(recent.cw) FROM (SELECT cwo2.charge_weight AS cw FROM roast_log rl JOIN charge_weight_options cwo2 ON cwo2.id = rl.charge_weight WHERE rl.recipe_id = rf.recipe_id AND rl.facility_id = rf.facility_id AND cwo2.charge_weight > 0 ORDER BY rl.roast_date DESC LIMIT 5) recent),
            c.charge_weight, 25::numeric
        ) AS effective_charge_weight
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

-- ── Update trigger to populate roast_date_utc on new rows ───────────────────
CREATE OR REPLACE FUNCTION public.trg_stamp_roasted_weight()
RETURNS trigger LANGUAGE plpgsql AS $function$
DECLARE
    v_retention     numeric;
    v_charge_weight numeric;
    v_tz            text;
BEGIN
    -- Resolve charge_weight UUID → numeric via join
    SELECT cwo.charge_weight INTO v_charge_weight
    FROM public.charge_weight_options cwo
    WHERE cwo.id = NEW.charge_weight LIMIT 1;

    -- Fallback for any legacy numeric string rows
    IF v_charge_weight IS NULL AND NEW.charge_weight ~ '^[0-9]+(\.[0-9]+)?$' THEN
        v_charge_weight := NEW.charge_weight::numeric;
    END IF;

    -- Leave charge_weight as UUID (don't overwrite)

    -- 3-tier retention factor
    SELECT value_number INTO v_retention FROM company_parameters
    WHERE parameter_id = '1de271df' AND facility_id = NEW.facility_id LIMIT 1;
    IF v_retention IS NULL OR v_retention = 0 THEN
        SELECT amount INTO v_retention FROM standard_parameters WHERE parameters_id = '1de271df' LIMIT 1;
    END IF;
    IF v_retention IS NULL OR v_retention = 0 THEN v_retention := 0.82; END IF;

    NEW.roasted_weight := ROUND(COALESCE(v_charge_weight, 0) * v_retention, 2);

    -- Populate roast_date_utc: convert local roast_date → UTC using facility timezone
    SELECT COALESCE(time_zone, 'UTC') INTO v_tz
    FROM public.facilities WHERE facility_id = NEW.facility_id;

    IF NEW.roast_date IS NOT NULL THEN
        NEW.roast_date_utc := NEW.roast_date AT TIME ZONE v_tz;
    END IF;

    RETURN NEW;
END;
$function$;
