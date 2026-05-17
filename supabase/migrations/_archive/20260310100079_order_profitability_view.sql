-- Migration 00079: order_profitability view
--
-- Per-order revenue, COGS, gross profit, and margin %, aggregated from
-- order_details. Both total_price and unit_cost_at_sale are auto-populated by
-- handle_order_detail_logic() on every INSERT, so no manual data entry needed.
--
-- Canceled orders are excluded — they don't represent real revenue or COGS.
--
-- AppSheet use: supplement or replace the orders list with profit/margin columns.
-- Can also be filtered/grouped by customer_id for customer-level profitability.

CREATE VIEW public.order_profitability WITH (security_invoker = 'true') AS
SELECT
    o.order_id,
    o.facility_id,
    o.company_id,
    o.order_date,
    o.order_status,
    o.customer_id,
    COALESCE(SUM(od.total_price),       0)                                  AS revenue,
    COALESCE(SUM(od.unit_cost_at_sale), 0)                                  AS cogs,
    COALESCE(SUM(od.total_price),       0)
        - COALESCE(SUM(od.unit_cost_at_sale), 0)                            AS gross_profit,
    ROUND(
        (COALESCE(SUM(od.total_price), 0) - COALESCE(SUM(od.unit_cost_at_sale), 0))
        / NULLIF(COALESCE(SUM(od.total_price), 0), 0) * 100,
        1
    )                                                                        AS margin_pct
FROM public.orders o
JOIN public.order_details od ON od.order_id = o.order_id
WHERE o.order_status != 'Canceled'
GROUP BY o.order_id, o.facility_id, o.company_id, o.order_date, o.order_status, o.customer_id;
