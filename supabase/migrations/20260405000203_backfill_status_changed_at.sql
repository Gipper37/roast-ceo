-- Backfill status_changed_at for delivered/packed/canceled orders where it's NULL.
-- Use updated_at as the best available proxy for when the status last changed.
-- This fixes the totals view delivered_qty and packed_qty which filter by status_changed_at >= week_start.

UPDATE public.orders
SET status_changed_at = COALESCE(updated_at, created_at, NOW())
WHERE status_changed_at IS NULL
  AND order_status IN ('Delivered', 'Packed', 'Canceled');
