-- Migration 00132: Simplify order_graphs_weekly_avg_by_year to only avg weekly revenue, gross profit, roasted weight

DROP VIEW IF EXISTS public.order_graphs_weekly_avg_by_year;

CREATE VIEW public.order_graphs_weekly_avg_by_year AS
WITH yearly AS (
    SELECT
        facility_id,
        company_id,
        EXTRACT(year FROM week_start)::integer             AS year_start,
        ROUND(AVG(revenue),                             2) AS avg_weekly_revenue,
        ROUND(AVG(gross_profit),                        2) AS avg_weekly_gross_profit,
        ROUND(AVG(total_roasted_weight)::numeric,       2) AS avg_weekly_roasted_weight
    FROM public.order_graphs_week
    WHERE week_start <= CURRENT_DATE
    GROUP BY facility_id, company_id, EXTRACT(year FROM week_start)
)
SELECT
    facility_id || '_' || year_start            AS year_report_id,
    year_start,
    facility_id,
    company_id,
    avg_weekly_revenue,
    avg_weekly_gross_profit,
    avg_weekly_roasted_weight
FROM yearly
ORDER BY year_start DESC, facility_id;
