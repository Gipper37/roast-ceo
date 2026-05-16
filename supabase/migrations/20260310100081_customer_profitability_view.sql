-- Migration 00081: customer_profitability view
-- Per-customer lifetime P&L aggregated across all valid orders.
-- Excludes: Canceled orders, zero-revenue orders, zero-COGS orders (samples/errors/missing data).
-- Includes data_warning flag for missing or suspicious COGS.

CREATE VIEW public.customer_profitability WITH (security_invoker = 'true') AS
WITH order_revenue AS (
    SELECT order_id,
           SUM(total_price)       AS order_total,
           SUM(unit_cost_at_sale) AS order_cogs
    FROM public.order_details
    GROUP BY order_id
)
SELECT
    c.customer_id,
    c.name_company                                                                AS customer_name,
    c.company_id,
    COUNT(DISTINCT o.order_id)                                                   AS total_orders,
    COALESCE(SUM(od.total_price),       0)                                       AS revenue,
    COALESCE(SUM(od.unit_cost_at_sale), 0)                                       AS cogs,
    COALESCE(SUM(od.total_price), 0)
        - COALESCE(SUM(od.unit_cost_at_sale), 0)                                 AS gross_profit,
    ROUND(
        (COALESCE(SUM(od.total_price), 0) - COALESCE(SUM(od.unit_cost_at_sale), 0))
        / NULLIF(COALESCE(SUM(od.total_price), 0), 0) * 100,
        1
    )                                                                             AS margin_pct,
    CASE
        WHEN COALESCE(SUM(od.unit_cost_at_sale), 0) = 0                          THEN TRUE
        WHEN ROUND(
               (COALESCE(SUM(od.total_price), 0) - COALESCE(SUM(od.unit_cost_at_sale), 0))
               / NULLIF(COALESCE(SUM(od.total_price), 0), 0) * 100, 1) < 0      THEN TRUE
        WHEN ROUND(
               (COALESCE(SUM(od.total_price), 0) - COALESCE(SUM(od.unit_cost_at_sale), 0))
               / NULLIF(COALESCE(SUM(od.total_price), 0), 0) * 100, 1) > 90     THEN TRUE
        ELSE FALSE
    END                                                                           AS data_warning
FROM public.customers c
JOIN public.orders        o   ON o.customer_id  = c.customer_id
JOIN order_revenue        orv ON orv.order_id   = o.order_id
                              AND orv.order_total > 0
                              AND orv.order_cogs  > 0
JOIN public.order_details od  ON od.order_id    = o.order_id
WHERE o.order_status != 'Canceled'
GROUP BY c.customer_id, c.name_company, c.company_id;
