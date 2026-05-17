-- Live view for the current (in-progress) roast week.
-- Returns one row per facility with stats computed from roast_log + orders in real time.
-- Used by the reports page to append a live current-week row to the weekly_roast_snapshot data.

CREATE OR REPLACE VIEW public.weekly_roast_current AS
WITH fac AS (
    SELECT
        f.facility_id,
        f.company_id,
        COALESCE(NULLIF(f.time_zone, ''), 'UTC') AS tz,
        COALESCE(
            (SELECT value_number::integer FROM public.company_parameters
              WHERE parameter_id = 'RF1iFWjOh7' AND facility_id = f.facility_id LIMIT 1),
            (SELECT amount::integer FROM public.standard_parameters
              WHERE parameters_id = 'RF1iFWjOh7' LIMIT 1),
            4
        ) AS reset_day,
        COALESCE(
            (SELECT value_number::integer FROM public.company_parameters
              WHERE parameter_id = 'orders_reset_day' AND facility_id = f.facility_id LIMIT 1),
            (SELECT amount::integer FROM public.standard_parameters
              WHERE parameters_id = 'orders_reset_day' LIMIT 1),
            6
        ) AS order_reset_day,
        COALESCE(
            NULLIF((
                SELECT SUM(COALESCE(ru.capacity_hrs_per_week,
                    COALESCE(
                        (SELECT value_number FROM public.company_parameters
                          WHERE parameter_id = 'roast_capacity_hrs' AND facility_id = f.facility_id LIMIT 1),
                        35)))
                FROM public.roaster_units ru
                WHERE ru.facility_id = f.facility_id AND ru.is_active = true
            ), 0),
            COALESCE(
                (SELECT value_number FROM public.company_parameters
                  WHERE parameter_id = 'roast_capacity_hrs' AND facility_id = f.facility_id LIMIT 1),
                35)
        ) AS capacity_hrs
    FROM public.facilities f
),
fac_week AS (
    SELECT
        fac.*,
        (CURRENT_TIMESTAMP AT TIME ZONE fac.tz)::date
            - ((EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fac.tz)::date)::integer
                - fac.reset_day + 7) % 7) AS week_start,
        (CURRENT_TIMESTAMP AT TIME ZONE fac.tz)::date
            - ((EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fac.tz)::date)::integer
                - fac.order_reset_day + 7) % 7) AS order_week_start
    FROM fac
),
roast_agg AS (
    SELECT
        fw.facility_id,
        fw.company_id,
        fw.week_start,
        fw.order_week_start,
        fw.capacity_hrs,
        COUNT(rl.roast_log_id)                                                      AS roast_count,
        COALESCE(SUM(rl.roasted_weight), 0)                                         AS total_roasted,
        COALESCE(SUM(rl.charge_weight_lbs), 0)                                      AS total_roasted_green,
        ROUND(
            COUNT(rl.roast_log_id)
            * COALESCE((
                SELECT AVG(gap_minutes)
                FROM (
                    SELECT EXTRACT(EPOCH FROM (
                        rl2.roast_date - LAG(rl2.roast_date) OVER (
                            PARTITION BY rl2.roaster_unit_id ORDER BY rl2.roast_date
                        )
                    )) / 60.0 AS gap_minutes
                    FROM public.roast_log rl2
                    WHERE rl2."charged?" = true
                      AND rl2.facility_id = fw.facility_id
                      AND rl2.roast_date >= fw.week_start
                ) g
                WHERE gap_minutes > 0 AND gap_minutes <= 25
            ), 0)
            / 60.0
        , 2) AS roasting_hours
    FROM fac_week fw
    LEFT JOIN public.roast_log rl
        ON rl.facility_id = fw.facility_id
       AND rl."charged?" = true
       AND rl.roast_date >= fw.week_start
    GROUP BY fw.facility_id, fw.company_id, fw.week_start, fw.order_week_start, fw.capacity_hrs
)
SELECT
    ra.facility_id,
    ra.company_id,
    ra.week_start,
    ra.total_roasted,
    ra.total_roasted_green,
    ra.roast_count::integer,
    ra.roasting_hours,
    ROUND(ra.roasting_hours / NULLIF(ra.capacity_hrs, 0) * 100, 1)                 AS capacity_pct,
    COALESCE((
        SELECT SUM(od.roasted_weight)
        FROM public.order_details od
        JOIN public.orders o ON od.order_id = o.order_id
        WHERE o.facility_id = ra.facility_id
          AND o.order_date >= ra.order_week_start
          AND o.order_status <> 'Canceled'
    ), 0)                                                                            AS total_ordered_roasted,
    COALESCE((
        SELECT COUNT(DISTINCT o.order_id)
        FROM public.orders o
        WHERE o.facility_id = ra.facility_id
          AND o.order_date >= ra.order_week_start
          AND o.order_status <> 'Canceled'
    ), 0)::integer                                                                   AS order_count,
    COALESCE((
        SELECT SUM(od.quantity)
        FROM public.order_details od
        JOIN public.orders o ON od.order_id = o.order_id
        WHERE o.facility_id = ra.facility_id
          AND o.order_date >= ra.order_week_start
          AND o.order_status <> 'Canceled'
    ), 0)                                                                            AS products_sold
FROM roast_agg ra;
