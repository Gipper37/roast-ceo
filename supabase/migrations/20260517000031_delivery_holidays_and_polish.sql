-- ============================================================
-- Delivery routing — holidays + integration polish
-- ============================================================
-- Adds the holiday calendar referenced in the Phase 1 design (flag-
-- only handling: holiday dates surface as a banner on Today /
-- Schedule views; no auto-rescheduling). Also adds a small index
-- so the sidebar nav badge query for "today's stop count" is cheap.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.company_holiday (
  company_id    text NOT NULL REFERENCES public.companies(company_id) ON DELETE CASCADE,
  holiday_date  date NOT NULL,
  label         text NOT NULL,
  notes         text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  created_by    text,
  PRIMARY KEY (company_id, holiday_date)
);
CREATE INDEX company_holiday_date_idx ON public.company_holiday (holiday_date);

ALTER TABLE public.company_holiday ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_company_access ON public.company_holiday
  FOR ALL TO authenticated USING (company_id IN (SELECT auth_company_ids()));

COMMENT ON TABLE public.company_holiday IS
  'Per-tenant holiday calendar for delivery routing. Phase 1 behavior is flag-only — dates appearing here trigger warning banners on the Today / Schedule views so the operator can manually reschedule. No automatic date-shifting (deferred to Phase 4 with a more complete calendar system).';


-- Composite index to make the sidebar "today's stop count" query
-- (status IN open/packed + delivery_date = today + scoped by
-- company via existing RLS) cheap to evaluate per page load.
CREATE INDEX IF NOT EXISTS orders_status_delivery_date_idx
  ON public.orders (delivery_date, order_status)
  WHERE delivery_date IS NOT NULL AND order_status IN ('Open', 'Packed');
