-- Migration 00080: monthly_financials view
--
-- Historical monthly financial summary — one row per facility per calendar month.
-- Returns all months with order data, newest first. Canceled orders excluded.
--
-- Columns: revenue, cogs, gross_profit, margin_pct — all four metrics the
-- business needs for a P&L graph over time.
--
-- Key column: monthly_financial_id = facility_id || '_' || 'YYYY-MM'
-- This is stable and unique per (facility, month), usable as an AppSheet row key.
--
-- AppSheet use: graph datasource — line or bar chart with month_start on x-axis,
-- up to 4 series (revenue, cogs, gross_profit, margin_pct). Scoped per facility
-- via AppSheet's built-in company/facility filter. Unlike weekly_grand_total,
-- this is fully historical — every past month is visible, nothing rolls off.

CREATE VIEW public.monthly_financials WITH (security_invoker = 'true') AS
SELECT
    o.facility_id
        || '_'
        || TO_CHAR(DATE_TRUNC('month', o.order_date)::date, 'YYYY-MM')     AS monthly_financial_id,
    o.facility_id,
    f.company_id,
    DATE_TRUNC('month', o.order_date)::date                                 AS month_start,
    COALESCE(SUM(od.total_price),       0)                                  AS revenue,
    COALESCE(SUM(od.unit_cost_at_sale), 0)                                  AS cogs,
    COALESCE(SUM(od.total_price),       0)
        - COALESCE(SUM(od.unit_cost_at_sale), 0)                            AS gross_profit,
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
