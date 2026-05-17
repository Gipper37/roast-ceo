-- Migration 00058: Add indexes to roast_stock_log
--
-- roast_stock_log has 63,084 sequential scans on only 1 row (live as of 2026-02-28).
-- Both roast_detail and roast_detail_by_blend views do lateral subqueries that
-- full-scan this table on every read. With 1 row it's fast now, but every new
-- stock entry multiplies the cost: 100 rows × 63k reads/day = 6.3M row reads/day.
--
-- Partial indexes on (stock_type, id, facility_id, created_at DESC) let the view
-- subqueries index-scan directly to matching rows instead of scanning the full table.

-- For roast_detail_by_blend: WHERE stock_type = 'blend' AND blend_id = X AND facility_id = Y
CREATE INDEX IF NOT EXISTS idx_roast_stock_log_blend
    ON public.roast_stock_log (blend_id, facility_id, created_at DESC)
    WHERE stock_type = 'blend';

-- For roast_detail: WHERE stock_type = 'origin' AND origin_id = X AND facility_id = Y
CREATE INDEX IF NOT EXISTS idx_roast_stock_log_origin
    ON public.roast_stock_log (origin_id, facility_id, created_at DESC)
    WHERE stock_type = 'origin';
