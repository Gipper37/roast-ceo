-- Fix weekly_grand_total view
--
-- Root cause: view pulled timezone, roast_target_day, and retention_rate from
-- standard_parameters, which has no rows for these parameter IDs. The config CTE
-- therefore returned 0 rows, causing the entire view to return 0 rows.
--
-- Correct sources (matching every other function in the schema):
--   timezone        → facilities.time_zone (COALESCE 'UTC')
--   roast_target_day → company_parameters WHERE parameter_id = 'RF1iFWjOh7' AND facility_id
--   retention_rate  → company_parameters WHERE parameter_id = '1de271df'  AND facility_id
--
-- Additional fixes:
--   • Returns 1 row per facility (was 1 global row) — enables AppSheet facility filter
--   • Adds facility_id and company_id output columns for AppSheet row-level filtering
--   • Replaces gen_random_uuid() key (changed every query) with stable facility_id value
--   • All metric subqueries are now scoped to facility_id

DROP VIEW IF EXISTS public.weekly_grand_total;

CREATE VIEW public.weekly_grand_total
WITH (security_invoker='true') AS
WITH facility_config AS (
    SELECT
        f.facility_id,
        f.company_id,
        COALESCE(f.time_zone, 'UTC') AS timezone,
        COALESCE(
            (SELECT cp.value_number::integer
             FROM public.company_parameters cp
             WHERE cp.parameter_id = 'RF1iFWjOh7'
               AND cp.facility_id = f.facility_id
             LIMIT 1),
            1  -- default: Monday (matches roast function fallback)
        ) AS roast_target_day,
        COALESCE(
            (SELECT cp.value_number
             FROM public.company_parameters cp
             WHERE cp.parameter_id = '1de271df'
               AND cp.facility_id = f.facility_id
             LIMIT 1),
            0.82  -- matches fallback used in all trigger functions
        ) AS retention_rate
    FROM public.facilities f
),
calc AS (
    SELECT
        fc.facility_id,
        fc.company_id,
        fc.retention_rate,
        date_trunc('week', (CURRENT_TIMESTAMP AT TIME ZONE fc.timezone))::date AS order_week_start,
        ((CURRENT_TIMESTAMP AT TIME ZONE fc.timezone)::date - (
            EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fc.timezone)::date)::integer
            - fc.roast_target_day + 7
        ) % 7) AS roast_week_start
    FROM facility_config fc
)
SELECT
    c.facility_id                         AS open_order_total_id,
    c.facility_id,
    c.company_id,
    COALESCE(
        (SELECT SUM(od.roasted_weight)
         FROM public.order_details od
         JOIN public.orders o ON od.order_id = o.order_id
         WHERE o.order_date  >= c.order_week_start
           AND o.facility_id  = c.facility_id),
        0::double precision
    )                                     AS total_ordered_roasted,
    COALESCE(
        (SELECT SUM(od.roasted_weight)
         FROM public.order_details od
         JOIN public.orders o ON od.order_id = o.order_id
         WHERE o.order_date  >= c.order_week_start
           AND o.facility_id  = c.facility_id),
        0::double precision
    ) / NULLIF(c.retention_rate::double precision, 0::double precision)
                                          AS total_ordered_green,
    COALESCE(
        (SELECT SUM(rl.roasted_weight)
         FROM public.roast_log rl
         WHERE rl."charged?"   = true
           AND rl.roast_date   >= c.roast_week_start
           AND rl.facility_id   = c.facility_id),
        0::numeric
    )                                     AS total_roasted,
    COALESCE(
        (SELECT SUM(rl.charge_weight)
         FROM public.roast_log rl
         WHERE rl."charged?"   = true
           AND rl.roast_date   >= c.roast_week_start
           AND rl.facility_id   = c.facility_id),
        0::numeric
    )                                     AS total_roasted_green
FROM calc c;
