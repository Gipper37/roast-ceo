-- Migration: Add index and foreign key on order_details.order_id
--
-- Issue 9: order_details.order_id (text, nullable) has no index and no FK
-- referencing orders.order_id. This causes two distinct problems:
--
-- PERFORMANCE: order_id is the primary join column in order_details — used by
-- every trigger that aggregates by order (update_totals_from_order,
-- update_order_aggregates, handle_order_detail_logic, etc.). Without an index
-- PostgreSQL does a full sequential scan of every row in order_details each time.
-- As order history grows this becomes a major bottleneck.
-- Existing indexes for comparison: idx_order_details_facility, idx_order_details_product.
--
-- INTEGRITY: Without a FK, order_detail rows can reference a deleted or
-- non-existent order_id. These "orphaned" line items are silently included in
-- all stock, roast, and total calculations, causing incorrect results.
--
-- ============================================================
-- Fix 1: Index
-- Follows existing naming convention: idx_order_details_<column>
-- CREATE INDEX IF NOT EXISTS is idempotent.
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_order_details_order
    ON public.order_details USING btree (order_id);


-- ============================================================
-- Fix 2: Foreign Key (NOT VALID + ON DELETE CASCADE)
--
-- ON DELETE CASCADE: order_details rows are entirely derived from their
-- parent order (handle_order_detail_logic denormalizes order_date,
-- customer_id, company_id, facility_id from the parent). A line item
-- without a parent order has no meaningful context and should be
-- removed automatically when the order is deleted.
--
-- NOT VALID: Skips the full-table scan of existing data at creation time.
-- This means the constraint is enforced for all future inserts/updates
-- immediately, but existing rows are not validated until the VALIDATE
-- statement below is run explicitly.
--
-- Use NOT VALID because:
--   a) order_id is nullable — existing NULL values pass the FK check regardless.
--   b) If any non-NULL orphaned rows exist in current data, adding the
--      constraint WITHOUT NOT VALID would fail with a hard error here.
--
-- TO VALIDATE EXISTING DATA (run in a maintenance window after confirming
-- or cleaning up any orphaned rows):
--
--   ALTER TABLE public.order_details
--       VALIDATE CONSTRAINT order_details_order_id_fkey;
--
-- To find orphaned rows before validating:
--
--   SELECT od.order_detail_id, od.order_id
--   FROM public.order_details od
--   LEFT JOIN public.orders o ON od.order_id = o.order_id
--   WHERE od.order_id IS NOT NULL AND o.order_id IS NULL;
-- ============================================================

ALTER TABLE ONLY public.order_details
    ADD CONSTRAINT order_details_order_id_fkey
    FOREIGN KEY (order_id)
    REFERENCES public.orders (order_id)
    ON DELETE CASCADE
    NOT VALID;
