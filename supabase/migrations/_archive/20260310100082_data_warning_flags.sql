-- Migration 00082: Add data_warning boolean to product_margins and order_profitability.
-- Flags: COGS = 0 (missing data), margin < 0% (below cost), margin > 90% (suspiciously high).
-- Uses CREATE OR REPLACE VIEW — no drop needed.

CREATE OR REPLACE VIEW public.product_margins WITH (security_invoker = 'true') AS
SELECT
    p.product_id,
    p.product_name,
    p.company_id,
    p.facility_id,
    p.price,
    p.total_unit_cogs,
    ROUND((p.price - p.total_unit_cogs)::numeric, 2)                             AS gross_profit_per_unit,
    ROUND(((p.price - p.total_unit_cogs) / NULLIF(p.price, 0)) * 100, 1)        AS margin_pct,
    p.weight_lbs,
    p.size,
    CASE
        WHEN p.total_unit_cogs = 0                                                THEN TRUE
        WHEN ((p.price - p.total_unit_cogs) / NULLIF(p.price, 0)) * 100 < 0     THEN TRUE
        WHEN ((p.price - p.total_unit_cogs) / NULLIF(p.price, 0)) * 100 > 90    THEN TRUE
        ELSE FALSE
    END                                                                           AS data_warning
FROM public.products p
WHERE NOT p."archived?";

CREATE OR REPLACE VIEW public.order_profitability WITH (security_invoker = 'true') AS
SELECT
    o.order_id,
    o.facility_id,
    o.company_id,
    o.order_date,
    o.order_status,
    o.customer_id,
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
FROM public.orders o
JOIN public.order_details od ON od.order_id = o.order_id
WHERE o.order_status != 'Canceled'
GROUP BY o.order_id, o.facility_id, o.company_id, o.order_date, o.order_status, o.customer_id;
