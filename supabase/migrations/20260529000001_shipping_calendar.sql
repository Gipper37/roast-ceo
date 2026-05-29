-- ============================================================
-- Shipping calendar + per-order tracking fields
-- ============================================================
-- New feature: company-wide shipping date list, queued shipping
-- orders auto-target the next future shipping date, operator marks
-- shipped (stamps delivery_date + tracking + carrier, flips status).
--
-- order_status gets a new value 'Shipped' to parallel 'Delivered' for
-- shipping-zone orders. No CHECK constraint to amend — order_status is
-- a free text column today.
-- ============================================================

-- ── Company-wide shipping calendar ──────────────────────────────
CREATE TABLE IF NOT EXISTS public.shipping_date (
  id         text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  company_id text NOT NULL REFERENCES public.companies(company_id) ON DELETE CASCADE,
  ship_date  date NOT NULL,
  notes      text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, ship_date)
);

CREATE INDEX IF NOT EXISTS shipping_date_company_id_ship_date_idx
  ON public.shipping_date (company_id, ship_date);

ALTER TABLE public.shipping_date ENABLE ROW LEVEL SECURITY;

-- Read + write require the user to be on a team for the company.
-- Mirrors the pattern on sales_area_day / customer_delivery_day.
DROP POLICY IF EXISTS tenant_company_access ON public.shipping_date;
CREATE POLICY tenant_company_access ON public.shipping_date
  FOR ALL TO authenticated
  USING (company_id IN (SELECT public.auth_company_ids()))
  WITH CHECK (company_id IN (SELECT public.auth_company_ids()));

-- ── Order tracking fields ───────────────────────────────────────
-- All nullable — shipping-zone orders accumulate them, delivery
-- orders never use them.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS tracking_number text,
  ADD COLUMN IF NOT EXISTS carrier         text,
  ADD COLUMN IF NOT EXISTS shipped_at      timestamptz;

-- Carrier whitelist. Optional; NULL is fine. 'Other' lets operators
-- track anything not in the big-three (DHL, regional couriers, etc.)
-- without us having to keep extending the enum.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'orders_carrier_chk'
  ) THEN
    ALTER TABLE public.orders
      ADD CONSTRAINT orders_carrier_chk
      CHECK (carrier IS NULL OR carrier IN ('USPS','UPS','FedEx','Other'));
  END IF;
END $$;

-- Force PostgREST to pick up the new columns immediately so the
-- frontend doesn't get "column orders.tracking_number does not
-- exist in the API schema cache" on first call.
NOTIFY pgrst, 'reload schema';
