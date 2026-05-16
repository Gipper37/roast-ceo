-- Migration 00140: Full backfill of order_details.total_price from price log
-- and unit_cost_at_sale from current products.total_unit_cogs

-- ── 1. Backfill total_price from price log history ────────────────────────────
-- For each order_detail, find the price log entry valid on that order date
-- (valid_from <= order_date < next_price_date) and recalculate total_price.
-- Orders with no matching price log entry are left unchanged.

WITH price_windows AS (
    SELECT
        ppl.product_id,
        ppl.facility_id,
        ppl.price,
        ppl.date_updated AS valid_from,
        LEAD(ppl.date_updated) OVER (
            PARTITION BY ppl.product_id, ppl.facility_id
            ORDER BY ppl.date_updated
        ) AS valid_to
    FROM public.products_price_log ppl
    WHERE ppl.price > 0
)
UPDATE public.order_details od
SET total_price = od.quantity * pw.price
FROM public.orders o,
     price_windows pw
WHERE od.order_id = o.order_id
  AND pw.product_id = od.product_id
  AND o.order_date >= pw.valid_from
  AND (pw.valid_to IS NULL OR o.order_date < pw.valid_to)
  AND (pw.facility_id IS NULL OR pw.facility_id = o.facility_id)
  AND o.order_status != 'Canceled'
  AND COALESCE(od.quantity, 0) > 0;

-- ── 2. Backfill unit_cost_at_sale from current products.total_unit_cogs ───────
-- No historical COGS log exists, so current product COGS is used for all orders.
-- This gives consistent, accurate COGS based on the latest cost structure.

UPDATE public.order_details od
SET unit_cost_at_sale = od.quantity * p.total_unit_cogs
FROM public.products p,
     public.orders o
WHERE od.product_id = p.product_id
  AND od.order_id = o.order_id
  AND o.order_status != 'Canceled'
  AND COALESCE(od.quantity, 0) > 0
  AND p.total_unit_cogs IS NOT NULL
  AND p.total_unit_cogs > 0;
