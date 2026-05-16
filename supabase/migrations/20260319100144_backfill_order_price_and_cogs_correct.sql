-- Migration 00144: Correct full backfill of order_details
-- 1. total_price from price log history (date-windowed)
-- 2. unit_cost_at_sale from get_product_cogs_on_date() — historical costs per shipment

-- ── 1. Backfill total_price ───────────────────────────────────────────────────

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

-- ── 2. Backfill unit_cost_at_sale using historical shipment costs ─────────────
-- get_product_cogs_on_date() reconstructs COGS from the shipment received
-- immediately before each order_date — exactly what the live trigger does.

WITH historical_cogs AS (
    SELECT
        od.order_detail_id,
        od.quantity,
        public.get_product_cogs_on_date(
            od.product_id,
            od.facility_id,
            od.order_date
        ) AS cogs_per_unit
    FROM public.order_details od
    JOIN public.orders o ON o.order_id = od.order_id
    WHERE o.order_status != 'Canceled'
      AND COALESCE(od.quantity, 0) > 0
)
UPDATE public.order_details od
SET unit_cost_at_sale = hc.cogs_per_unit * hc.quantity
FROM historical_cogs hc
WHERE od.order_detail_id = hc.order_detail_id
  AND hc.cogs_per_unit IS NOT NULL;
