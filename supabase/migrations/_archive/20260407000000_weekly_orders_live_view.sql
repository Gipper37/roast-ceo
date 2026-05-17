-- Live view for weekly order_count and products_sold.
-- Replaces the stale weekly_roast_snapshot data for these two fields.
-- Week starts on Monday (date_trunc('week', ...)).

CREATE OR REPLACE VIEW weekly_orders_live AS
SELECT
    date_trunc('week', od.order_date)::date AS week_start,
    od.facility_id,
    COUNT(DISTINCT od.order_id)             AS order_count,
    SUM(od.quantity)                        AS products_sold
FROM public.order_details od
JOIN public.orders o ON o.order_id = od.order_id
WHERE o.order_status != 'Canceled'
  AND od.quantity > 0
GROUP BY 1, 2;
