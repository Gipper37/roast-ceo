-- Migration 00133: Change avg_weekly_revenue/gross_profit to avg_monthly in order_graphs_weekly_avg_by_year

DROP VIEW IF EXISTS public.order_graphs_weekly_avg_by_year;

CREATE VIEW public.order_graphs_weekly_avg_by_year AS
WITH monthly AS (
    SELECT
        facility_id,
        company_id,
        EXTRACT(year FROM week_start)::integer             AS year_start,
        date_trunc('month', week_start)                    AS month_start,
        SUM(revenue)                                       AS monthly_revenue,
        SUM(gross_profit)                                  AS monthly_gross_profit
    FROM public.order_graphs_week
    WHERE week_start <= CURRENT_DATE
    GROUP BY facility_id, company_id, EXTRACT(year FROM week_start), date_trunc('month', week_start)
),
weekly AS (
    SELECT
        facility_id,
        company_id,
        EXTRACT(year FROM week_start)::integer             AS year_start,
        ROUND(AVG(total_roasted_weight)::numeric,       2) AS avg_weekly_roasted_weight
    FROM public.order_graphs_week
    WHERE week_start <= CURRENT_DATE
    GROUP BY facility_id, company_id, EXTRACT(year FROM week_start)
),
yearly AS (
    SELECT
        m.facility_id,
        m.company_id,
        m.year_start,
        ROUND(AVG(m.monthly_revenue),      2) AS avg_monthly_revenue,
        ROUND(AVG(m.monthly_gross_profit), 2) AS avg_monthly_gross_profit
    FROM monthly m
    GROUP BY m.facility_id, m.company_id, m.year_start
)
SELECT
    y.facility_id || '_' || y.year_start   AS year_report_id,
    y.year_start,
    y.facility_id,
    y.company_id,
    y.avg_monthly_revenue,
    y.avg_monthly_gross_profit,
    w.avg_weekly_roasted_weight
FROM yearly y
JOIN weekly w ON w.facility_id = y.facility_id AND w.year_start = y.year_start
ORDER BY y.year_start DESC, y.facility_id;
