-- Migration 00130: Switch order_graphs_weekly_avg_by_month to monthly totals
--
-- revenue, cogs, gross_profit, order_count → monthly totals (SUM)
-- roasted_weight stays as avg_weekly_roasted_weight (AVG)
-- cogs_pct / margin_pct → derived from totals (more accurate than avg of weekly pcts)
-- 12-month rolling averages updated to avg monthly totals accordingly.

DROP VIEW IF EXISTS public.order_graphs_weekly_avg_by_month;

CREATE VIEW public.order_graphs_weekly_avg_by_month AS
WITH monthly AS (
    SELECT
        facility_id,
        company_id,
        date_trunc('month', week_start)::date              AS month_start,
        ROUND(SUM(revenue),                             2) AS total_revenue,
        ROUND(SUM(cogs),                                2) AS total_cogs,
        ROUND(SUM(gross_profit),                        2) AS total_gross_profit,
        ROUND(SUM(cogs)         / NULLIF(SUM(revenue), 0) * 100, 1) AS cogs_pct,
        ROUND(SUM(gross_profit) / NULLIF(SUM(revenue), 0) * 100, 1) AS margin_pct,
        SUM(order_count)                                   AS total_orders,
        ROUND(AVG(total_roasted_weight)::numeric,       2) AS avg_weekly_roasted_weight,
        COUNT(*)                                           AS weeks_in_month
    FROM public.order_graphs_week
    WHERE week_start <= CURRENT_DATE
    GROUP BY facility_id, company_id, date_trunc('month', week_start)
)
SELECT
    facility_id || '_' || month_start           AS month_report_id,
    month_start,
    facility_id,
    company_id,
    total_revenue,
    total_cogs,
    total_gross_profit,
    cogs_pct,
    margin_pct,
    total_orders,
    avg_weekly_roasted_weight,
    weeks_in_month,
    -- 12-month rolling averages
    ROUND(AVG(total_revenue)              OVER w12, 2) AS revenue_12mo_avg,
    ROUND(AVG(total_cogs)                 OVER w12, 2) AS cogs_12mo_avg,
    ROUND(AVG(cogs_pct)                  OVER w12, 1) AS cogs_pct_12mo_avg,
    ROUND(AVG(margin_pct)                OVER w12, 1) AS margin_pct_12mo_avg,
    ROUND(AVG(avg_weekly_roasted_weight) OVER w12, 2) AS roasted_weight_12mo_avg
FROM monthly
WINDOW w12 AS (
    PARTITION BY facility_id
    ORDER BY month_start
    ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
)
ORDER BY month_start DESC, facility_id;
