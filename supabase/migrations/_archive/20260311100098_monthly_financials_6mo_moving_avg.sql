-- Migration 00098: Add 6-month moving average for cogs_pct and margin_pct
--
-- Uses a CTE + window function (ROWS BETWEEN 5 PRECEDING AND CURRENT ROW)
-- scoped per facility so multi-facility averages don't bleed across tenants.
-- Months with fewer than 6 prior months still return an average (of whatever
-- data exists) — they don't go NULL.
--
-- Must DROP + recreate (adding new columns, can't use CREATE OR REPLACE).

DROP VIEW IF EXISTS public.monthly_financials;

CREATE VIEW public.monthly_financials WITH (security_invoker = 'true') AS
WITH monthly AS (
    SELECT
        o.facility_id
            || '_'
            || TO_CHAR(DATE_TRUNC('month', o.order_date)::date, 'YYYY-MM')     AS monthly_financial_id,
        o.facility_id,
        f.company_id,
        DATE_TRUNC('month', o.order_date)::date                                 AS month_start,
        ROUND(COALESCE(SUM(od.total_price),       0), 2)                        AS revenue,
        ROUND(COALESCE(SUM(od.unit_cost_at_sale), 0), 2)                        AS cogs,
        ROUND(
            COALESCE(SUM(od.total_price), 0)
            - COALESCE(SUM(od.unit_cost_at_sale), 0),
            2
        )                                                                        AS gross_profit,
        ROUND(
            COALESCE(SUM(od.unit_cost_at_sale), 0)
            / NULLIF(COALESCE(SUM(od.total_price), 0), 0) * 100,
            1
        )                                                                        AS cogs_pct,
        ROUND(
            (COALESCE(SUM(od.total_price), 0) - COALESCE(SUM(od.unit_cost_at_sale), 0))
            / NULLIF(COALESCE(SUM(od.total_price), 0), 0) * 100,
            1
        )                                                                        AS margin_pct
    FROM public.order_details od
    JOIN public.orders     o ON od.order_id    = o.order_id
    JOIN public.facilities f ON o.facility_id  = f.facility_id
    WHERE o.order_status != 'Canceled'
    GROUP BY o.facility_id, f.company_id, DATE_TRUNC('month', o.order_date)
)
SELECT
    monthly_financial_id,
    facility_id,
    company_id,
    month_start,
    revenue,
    cogs,
    gross_profit,
    cogs_pct,
    margin_pct,
    ROUND(
        AVG(cogs_pct) OVER (
            PARTITION BY facility_id
            ORDER BY month_start
            ROWS BETWEEN 5 PRECEDING AND CURRENT ROW
        ),
        1
    ) AS cogs_pct_6mo_avg,
    ROUND(
        AVG(margin_pct) OVER (
            PARTITION BY facility_id
            ORDER BY month_start
            ROWS BETWEEN 5 PRECEDING AND CURRENT ROW
        ),
        1
    ) AS margin_pct_6mo_avg
FROM monthly
ORDER BY month_start DESC;
