-- Migration 00096: Round revenue, cogs, gross_profit to 2 decimal places
--
-- SUM(unit_cost_at_sale) inherits the full precision of COGS calculations
-- (e.g. 7.82934...), causing AppSheet to display "infinite" decimal places
-- despite the Price column type being set to 0 decimals. Revenue shows 2
-- decimals for the same reason. Fix: ROUND to 2dp at the SQL level.

CREATE OR REPLACE VIEW public.monthly_financials WITH (security_invoker = 'true') AS
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
