-- Migration: Fix week boundary views
-- 1. order_graphs_week: replace hardcoded ISO Monday with dynamic orders_reset_day
-- 2. Helper function for roast_reset_day with proper fallback chain
-- 3. weekly_grand_total: fix roast_target_day default 1 → 4, add standard_parameters fallback

BEGIN;

-- ══════════════════════════════════════════════════════════════════════
-- 1. order_graphs_week — make week boundaries respect orders_reset_day
-- ══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW public.order_graphs_week AS
WITH facility_params AS (
    SELECT f.facility_id,
           f.company_id,
           COALESCE(
             (SELECT cp.value_number::integer FROM company_parameters cp
              WHERE cp.parameter_id = 'orders_reset_day' AND cp.facility_id = f.facility_id LIMIT 1),
             (SELECT sp.amount::integer FROM standard_parameters sp
              WHERE sp.parameters_id = 'orders_reset_day' LIMIT 1),
             6
           ) AS orders_reset_day,
           (SELECT min(o.order_date) FROM orders o
            WHERE o.facility_id = f.facility_id AND o.order_status <> 'Canceled') AS first_order_date
    FROM facilities f
),
spine AS (
    SELECT fp.facility_id,
           fp.company_id,
           fp.orders_reset_day,
           gs::date AS week_start
    FROM facility_params fp,
    LATERAL generate_series(
        fp.first_order_date::date
            - ((EXTRACT(dow FROM fp.first_order_date)::integer - fp.orders_reset_day + 7) % 7),
        CURRENT_DATE + interval '364 days',
        interval '7 days'
    ) AS gs
    WHERE fp.first_order_date IS NOT NULL
),
agg AS (
    SELECT s.facility_id,
           s.company_id,
           s.week_start,
           COALESCE(sum(od.total_price), 0) AS revenue,
           COALESCE(sum(od.unit_cost_at_sale), 0) AS cogs,
           COALESCE(sum(od.total_price) - sum(od.unit_cost_at_sale), 0) AS gross_profit,
           round((COALESCE(sum(od.unit_cost_at_sale), 0) / NULLIF(sum(od.total_price), 0)) * 100, 1) AS cogs_pct,
           round(((COALESCE(sum(od.total_price), 0) - COALESCE(sum(od.unit_cost_at_sale), 0)) / NULLIF(sum(od.total_price), 0)) * 100, 1) AS margin_pct,
           count(DISTINCT o.order_id) AS order_count,
           round(COALESCE(sum(od.roasted_weight), 0)::numeric, 2) AS total_roasted_weight
    FROM spine s
    LEFT JOIN orders o ON o.facility_id = s.facility_id
        AND (o.order_date::date - ((EXTRACT(dow FROM o.order_date)::integer - s.orders_reset_day + 7) % 7)) = s.week_start
        AND o.order_status <> 'Canceled'
    LEFT JOIN order_details od ON od.order_id = o.order_id
    GROUP BY s.facility_id, s.company_id, s.week_start
)
SELECT (facility_id || '_' || week_start) AS week_report_id,
       week_start, facility_id, company_id,
       revenue, cogs, gross_profit, cogs_pct, margin_pct,
       order_count, total_roasted_weight,
       round(avg(revenue)                OVER w26, 2) AS revenue_6mo_avg,
       round(avg(cogs)                   OVER w26, 2) AS cogs_6mo_avg,
       round(avg(gross_profit)           OVER w26, 2) AS gross_profit_6mo_avg,
       round(avg(cogs_pct)               OVER w26, 1) AS cogs_pct_6mo_avg,
       round(avg(margin_pct)             OVER w26, 1) AS margin_pct_6mo_avg,
       round(avg(total_roasted_weight)   OVER w26, 2) AS roasted_weight_6mo_avg
FROM agg
WINDOW w26 AS (PARTITION BY facility_id ORDER BY week_start ROWS BETWEEN 25 PRECEDING AND CURRENT ROW)
ORDER BY week_start DESC, facility_id;


-- ══════════════════════════════════════════════════════════════════════
-- 2. Helper function for roast_reset_day with proper fallback chain
-- ══════════════════════════════════════════════════════════════════════
-- roast_detail and roast_detail_by_blend currently only check
-- company_parameters with fallback to hardcoded 4. This helper adds
-- the standard_parameters fallback that other views already have.
-- Future view recreations can use this function.

CREATE OR REPLACE FUNCTION public.get_roast_reset_day(p_facility_id text)
RETURNS integer LANGUAGE sql STABLE AS $$
    SELECT COALESCE(
        (SELECT cp.value_number::integer FROM company_parameters cp
         WHERE cp.parameter_id = 'RF1iFWjOh7' AND cp.facility_id = p_facility_id LIMIT 1),
        (SELECT sp.amount::integer FROM standard_parameters sp
         WHERE sp.parameters_id = 'RF1iFWjOh7' LIMIT 1),
        4
    );
$$;

COMMENT ON FUNCTION get_roast_reset_day IS 'Roast week reset day with full fallback: company → standard → 4 (Thursday)';


-- ══════════════════════════════════════════════════════════════════════
-- 3. weekly_grand_total — fix roast_target_day default 1 → 4
-- ══════════════════════════════════════════════════════════════════════
-- Only patching the facility_config CTE. The rest of the view stays the same.
-- Must recreate since views can't be partially altered.

CREATE OR REPLACE VIEW public.weekly_grand_total AS
WITH facility_config AS (
    SELECT f.facility_id,
           f.company_id,
           COALESCE(NULLIF(f.time_zone, ''), 'UTC') AS timezone,
           COALESCE(
             (SELECT cp.value_number::integer FROM company_parameters cp
              WHERE cp.parameter_id = 'RF1iFWjOh7' AND cp.facility_id = f.facility_id LIMIT 1),
             (SELECT sp.amount::integer FROM standard_parameters sp
              WHERE sp.parameters_id = 'RF1iFWjOh7' LIMIT 1),
             4
           ) AS roast_target_day,
           COALESCE(
             (SELECT cp.value_number FROM company_parameters cp
              WHERE cp.parameter_id = '1de271df' AND cp.facility_id = f.facility_id LIMIT 1),
             0.82
           ) AS retention_rate,
           COALESCE(
             (SELECT cp.value_number::integer FROM company_parameters cp
              WHERE cp.parameter_id = 'orders_reset_day' AND cp.facility_id = f.facility_id LIMIT 1),
             (SELECT sp.amount::integer FROM standard_parameters sp
              WHERE sp.parameters_id = 'orders_reset_day' LIMIT 1),
             6
           ) AS orders_reset_day,
           COALESCE(
             (SELECT cp.value_number FROM company_parameters cp
              WHERE cp.parameter_id = 'roast_capacity_hrs' AND cp.facility_id = f.facility_id LIMIT 1),
             (SELECT sp.amount FROM standard_parameters sp
              WHERE sp.parameters_id = 'roast_capacity_hrs' LIMIT 1),
             35
           ) AS facility_capacity_hrs
    FROM facilities f
),
calc AS (
    SELECT fc.facility_id,
           fc.company_id,
           fc.retention_rate,
           fc.facility_capacity_hrs,
           COALESCE(NULLIF(
             (SELECT sum(COALESCE(ru.capacity_hrs_per_week, fc.facility_capacity_hrs))
              FROM roaster_units ru
              WHERE ru.facility_id = fc.facility_id AND ru.is_active = true),
             0), fc.facility_capacity_hrs) AS total_capacity_hrs,
           (CURRENT_TIMESTAMP AT TIME ZONE fc.timezone)::date
             - ((EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fc.timezone)::date)::integer
                 - fc.orders_reset_day + 7) % 7) AS order_week_start,
           (CURRENT_TIMESTAMP AT TIME ZONE fc.timezone)::date
             - ((EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fc.timezone)::date)::integer
                 - fc.roast_target_day + 7) % 7) AS roast_week_start
    FROM facility_config fc
)
SELECT facility_id AS open_order_total_id,
       facility_id,
       company_id,
       COALESCE((SELECT sum(od.roasted_weight)
                 FROM order_details od JOIN orders o ON od.order_id = o.order_id
                 WHERE o.order_date >= c.order_week_start AND o.facility_id = c.facility_id
                   AND o.order_status <> 'Canceled'), 0) AS total_ordered_roasted,
       (COALESCE((SELECT sum(od.roasted_weight)
                  FROM order_details od JOIN orders o ON od.order_id = o.order_id
                  WHERE o.order_date >= c.order_week_start AND o.facility_id = c.facility_id
                    AND o.order_status <> 'Canceled'), 0)
        / NULLIF(retention_rate, 0)::double precision) AS total_ordered_green,
       COALESCE((SELECT sum(rl.roasted_weight)
                 FROM roast_log rl
                 WHERE rl."charged?" = true AND rl.roast_date >= c.roast_week_start
                   AND rl.facility_id = c.facility_id), 0) AS total_roasted,
       COALESCE((SELECT sum(rl.charge_weight_lbs)
                 FROM roast_log rl
                 WHERE rl."charged?" = true AND rl.roast_date >= c.roast_week_start
                   AND rl.facility_id = c.facility_id), 0) AS total_roasted_green,
       (SELECT max(rl.batches_since_chaff) FROM roast_log rl
        WHERE rl.facility_id = c.facility_id) AS batches_since_chaff,
       COALESCE((SELECT count(DISTINCT o.order_id)
                 FROM orders o
                 WHERE o.order_date >= c.order_week_start AND o.facility_id = c.facility_id
                   AND o.order_status <> 'Canceled'), 0) AS order_count,
       COALESCE((SELECT sum(od.quantity)
                 FROM order_details od JOIN orders o ON od.order_id = o.order_id
                 WHERE o.order_date >= c.order_week_start AND o.facility_id = c.facility_id
                   AND o.order_status <> 'Canceled'), 0) AS products_sold,
       COALESCE((SELECT count(*)
                 FROM roast_log rl
                 WHERE rl."charged?" = true AND rl.roast_date >= c.roast_week_start
                   AND rl.facility_id = c.facility_id), 0) AS roast_count,
       round(((COALESCE((SELECT count(*)
                         FROM roast_log rl
                         WHERE rl."charged?" = true AND rl.roast_date >= c.roast_week_start
                           AND rl.facility_id = c.facility_id), 0))::numeric
              * COALESCE((SELECT avg(gaps.gap_minutes)
                          FROM (SELECT (EXTRACT(epoch FROM (roast_log.roast_date
                                  - lag(roast_log.roast_date) OVER (PARTITION BY roast_log.roaster_unit_id ORDER BY roast_log.roast_date)))
                                  / 60.0) AS gap_minutes
                                FROM roast_log
                                WHERE roast_log."charged?" = true
                                  AND roast_log.roast_date >= c.roast_week_start
                                  AND roast_log.facility_id = c.facility_id) gaps
                          WHERE gaps.gap_minutes > 0 AND gaps.gap_minutes <= 25), 0)
              / 60.0), 2) AS roasting_hours,
       round(((((COALESCE((SELECT count(*)
                           FROM roast_log rl
                           WHERE rl."charged?" = true AND rl.roast_date >= c.roast_week_start
                             AND rl.facility_id = c.facility_id), 0))::numeric
                * COALESCE((SELECT avg(gaps.gap_minutes)
                            FROM (SELECT (EXTRACT(epoch FROM (roast_log.roast_date
                                    - lag(roast_log.roast_date) OVER (PARTITION BY roast_log.roaster_unit_id ORDER BY roast_log.roast_date)))
                                    / 60.0) AS gap_minutes
                                  FROM roast_log
                                  WHERE roast_log."charged?" = true
                                    AND roast_log.roast_date >= c.roast_week_start
                                    AND roast_log.facility_id = c.facility_id) gaps
                            WHERE gaps.gap_minutes > 0 AND gaps.gap_minutes <= 25), 0)
                / 60.0) / NULLIF(total_capacity_hrs, 0)) * 100), 1) AS capacity_pct
FROM calc c;

COMMIT;
