-- =============================================================================
-- Standing Order V2 — Draft status + standing_order_lines template table
-- =============================================================================
-- Phase 2 build: Standing Order management type ships with a daily
-- timezone-aware cron that auto-creates a Draft order at the
-- customer's cadence. Operator confirms (Draft → Open) or denies
-- (Draft → Cancelled) from a "Drafts awaiting confirmation" section
-- on /orders. Cron skips a customer if they already have a Draft
-- waiting (no double-up).
--
-- Two schema changes:
--
--   1. New `Draft` value in order_statuses (reference table).
--      Existing app code already filters by order_status; adding a
--      new value lets Drafts coexist with Open / Packed / Delivered
--      / Cancelled in the same orders table without a separate
--      tables-for-drafts split.
--
--   2. New `standing_order_lines` table — per-customer template the
--      cron uses to build the Draft. When empty, cron falls back
--      to the customer's most recent non-Cancelled order's items
--      (zero-config V1 behavior).
-- =============================================================================

-- 1) New order status. order_statuses is a tiny reference table —
-- PK is status_id (text). Sort_order=0 puts Draft above Open in
-- any sorted UI list (Open=1, Packed=2, Delivered=3, Canceled=4).
INSERT INTO public.order_statuses (status_id, display_name, sort_order)
VALUES ('Draft', 'Draft', 0)
ON CONFLICT (status_id) DO NOTHING;

-- 2) standing_order_lines — the editable template per customer.
CREATE TABLE IF NOT EXISTS public.standing_order_lines (
  standing_order_line_id  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id             text NOT NULL REFERENCES public.customers(customer_id) ON DELETE CASCADE,
  -- Tenant scoping mirrors the rest of the app (Phase 2 RLS policy
  -- predicate: company_id IN (auth_company_ids())).
  company_id              text NOT NULL REFERENCES public.companies(company_id) ON DELETE CASCADE,
  product_id              text NOT NULL REFERENCES public.products(product_id) ON DELETE RESTRICT,
  quantity                numeric NOT NULL CHECK (quantity > 0),
  -- Mirrors order_details.coffee_prep — the Whole Bean / Pre-Ground /
  -- Espresso Ground choice that gets carried into the Draft order.
  coffee_prep             text NOT NULL DEFAULT 'Whole Bean',
  -- Visual ordering inside the per-customer template editor. Operator
  -- can drag to reorder; cron renders Draft lines in the same order.
  position                int NOT NULL DEFAULT 0,
  created_at              timestamptz NOT NULL DEFAULT now(),
  updated_at              timestamptz NOT NULL DEFAULT now(),
  created_by              text,
  updated_by              text,
  -- One template line per (customer, product, prep) — prevents the
  -- editor from accidentally producing duplicate items in the Draft.
  UNIQUE (customer_id, product_id, coffee_prep)
);

CREATE INDEX IF NOT EXISTS standing_order_lines_customer_idx
  ON public.standing_order_lines (customer_id, position);

CREATE INDEX IF NOT EXISTS standing_order_lines_company_idx
  ON public.standing_order_lines (company_id);

-- 3) RLS — match the customers/orders posture. Tenant-scoped policy
-- so authenticated users (when the app moves off service_role)
-- only see their own company's templates. Service role bypasses
-- as usual.
ALTER TABLE public.standing_order_lines ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_company_access ON public.standing_order_lines;
CREATE POLICY tenant_company_access ON public.standing_order_lines
  FOR ALL TO authenticated
  USING (company_id IN (SELECT public.auth_company_ids()))
  WITH CHECK (company_id IN (SELECT public.auth_company_ids()));

-- 4) standing_order_candidates RPC — the daily-but-timezone-aware
-- query the cron calls. Returns customers due for a Draft
-- generation right now, but ONLY for facilities currently at
-- their local midnight hour. Vercel Cron fires this endpoint
-- every hour at :00 UTC; the endpoint internally filters to
-- "facilities at midnight local" so each tenant gets their
-- drafts at their own midnight (UK at midnight London,
-- Hawaii at midnight Honolulu, etc.).
--
-- Skips customers who already have a Draft pending — no
-- double-up if the cron re-runs (idempotent within the same
-- midnight hour).
--
-- SECURITY DEFINER so the route's service_role client can call
-- it. Read-only function — no INSERT/UPDATE.
CREATE OR REPLACE FUNCTION public.standing_order_candidates()
RETURNS TABLE(customer_id text, company_id text, facility_id text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT c.customer_id, c.company_id, c.facility_id
  FROM public.customers c
  JOIN public.facilities f ON f.facility_id = c.facility_id
  WHERE c.management_type = 'Standing Order'
    AND c.is_active = true
    AND c.company_id IS NOT NULL
    AND c.facility_id IS NOT NULL
    -- Facility is currently AT midnight local time (the hour 0 in
    -- its own timezone). Default Pacific/Honolulu mirrors the
    -- existing facility_params pattern in roast_detail_by_blend.
    AND EXTRACT(HOUR FROM (now() AT TIME ZONE COALESCE(NULLIF(f.time_zone, ''), 'Pacific/Honolulu'))) = 0
    -- Cadence reached. Same math as the reminder cron.
    AND c.last_order_date IS NOT NULL
    AND c.effective_interval_wks IS NOT NULL
    AND c.last_order_date + (c.effective_interval_wks || ' weeks')::interval <= CURRENT_DATE
    -- Skip customers that already have a Draft pending for them.
    -- One Draft at a time; operator must Confirm or Deny before
    -- another auto-create runs.
    AND NOT EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.customer_id = c.customer_id
        AND o.facility_id = c.facility_id
        AND o.order_status = 'Draft'
    );
$$;

REVOKE ALL ON FUNCTION public.standing_order_candidates() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.standing_order_candidates() TO service_role;

-- =============================================================================
-- Verification (post-push):
--   SELECT order_status FROM order_statuses ORDER BY sort_order, order_status;
--     -- Expected: 'Draft' present.
--   \d standing_order_lines
--     -- Expected: PK on standing_order_line_id, FKs on customer_id /
--     -- company_id / product_id, UNIQUE (customer_id, product_id,
--     -- coffee_prep), 2 indexes, RLS enabled.
--   SELECT * FROM standing_order_candidates();
--     -- Expected: empty (no Standing Order customers yet for SHCRUSA).
-- =============================================================================
