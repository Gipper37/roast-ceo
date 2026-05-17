-- Migration 00097: Add cogs_pct to monthly_financials view
--
-- cogs_pct = cogs / revenue * 100 (1 decimal place, matches margin_pct)
-- Null-safe: returns NULL when revenue = 0 to avoid divide-by-zero.

-- CREATE OR REPLACE can't add columns before existing ones; drop and recreate.
DROP VIEW IF EXISTS public.monthly_financials;

CREATE VIEW public.monthly_financials WITH (security_invoker = 'true') AS
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
ORDER BY month_start DESC;
