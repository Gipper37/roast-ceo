-- Migration 00146: Add cogs_pct to order_profitability view

DROP VIEW IF EXISTS public.order_profitability;
CREATE VIEW public.order_profitability AS
SELECT
    o.order_id,
    o.facility_id,
    o.company_id,
    o.order_date,
    o.order_status,
    o.customer_id,
    COALESCE(SUM(od.total_price), 0)        AS revenue,
    COALESCE(SUM(od.unit_cost_at_sale), 0)  AS cogs,
    COALESCE(SUM(od.total_price), 0) - COALESCE(SUM(od.unit_cost_at_sale), 0) AS gross_profit,
    ROUND(COALESCE(SUM(od.unit_cost_at_sale), 0)
        / NULLIF(COALESCE(SUM(od.total_price), 0), 0) * 100, 1) AS cogs_pct,
    ROUND((COALESCE(SUM(od.total_price), 0) - COALESCE(SUM(od.unit_cost_at_sale), 0))
        / NULLIF(COALESCE(SUM(od.total_price), 0), 0) * 100, 1) AS margin_pct,
    CASE
        WHEN COALESCE(SUM(od.unit_cost_at_sale), 0) = 0         THEN true
        WHEN ROUND((COALESCE(SUM(od.total_price), 0) - COALESCE(SUM(od.unit_cost_at_sale), 0))
            / NULLIF(COALESCE(SUM(od.total_price), 0), 0) * 100, 1) < 0   THEN true
        WHEN ROUND((COALESCE(SUM(od.total_price), 0) - COALESCE(SUM(od.unit_cost_at_sale), 0))
            / NULLIF(COALESCE(SUM(od.total_price), 0), 0) * 100, 1) > 90  THEN true
        ELSE false
    END AS data_warning
FROM public.orders o
JOIN public.order_details od ON od.order_id = o.order_id
WHERE o.order_status != 'Canceled'
GROUP BY o.order_id, o.facility_id, o.company_id, o.order_date, o.order_status, o.customer_id;
