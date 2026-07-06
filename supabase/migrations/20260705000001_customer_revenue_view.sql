-- customer_revenue: per-customer net revenue + order count, WITHOUT the COGS
-- requirement that customer_profitability imposes.
--
-- The customers page read revenue from customer_profitability, whose JOIN requires
-- orv.order_cogs > 0 — so any order with revenue but no cost (imported/historical
-- QB orders, or any un-costed order) is dropped and the customer shows blank
-- revenue even though the orders exist (MCR: 89 of 194 customers hidden, incl. all
-- Minit Stop). Revenue must not be hidden by missing COGS. This view is what the
-- customers page reads for its revenue column; customer_profitability is left
-- as-is for margin analysis (its data_warning flag already marks un-costed orders).
--
-- Net revenue = SUM(total_price) over non-canceled orders, so credit memos
-- (negative total_price) correctly reduce revenue. security_invoker so RLS on the
-- underlying tables scopes each caller to their own company.
CREATE OR REPLACE VIEW public.customer_revenue
  WITH (security_invoker = true) AS
SELECT c.customer_id,
       c.company_id,
       count(DISTINCT o.order_id)                  AS total_orders,
       COALESCE(sum(od.total_price), 0::numeric)   AS revenue
FROM public.customers c
  JOIN public.orders o        ON o.customer_id = c.customer_id
                             AND o.order_status <> 'Canceled'::text
  JOIN public.order_details od ON od.order_id = o.order_id
GROUP BY c.customer_id, c.company_id;

GRANT SELECT ON public.customer_revenue TO authenticated;

NOTIFY pgrst, 'reload schema';
