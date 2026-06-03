-- ============================================================
-- Recurring weekly shipping days
-- ============================================================
-- Operators want to set "we ship every Tuesday + Friday" once instead
-- of adding individual dates every week. Recurring rules expand into
-- the next N weeks of concrete shipping dates at read time.
--
-- One-off shipping_date rows (20260529000001) still work and stack on
-- top — useful for "we're also doing a special Monday shipment that
-- week."
-- ============================================================

CREATE TABLE IF NOT EXISTS public.shipping_recurring_day (
  id          text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  company_id  text NOT NULL REFERENCES public.companies(company_id) ON DELETE CASCADE,
  day_of_week text NOT NULL CHECK (day_of_week IN ('mon','tue','wed','thu','fri','sat','sun')),
  notes       text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, day_of_week)
);

CREATE INDEX IF NOT EXISTS shipping_recurring_day_company_idx
  ON public.shipping_recurring_day (company_id);

ALTER TABLE public.shipping_recurring_day ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tenant_company_access ON public.shipping_recurring_day;
CREATE POLICY tenant_company_access ON public.shipping_recurring_day
  FOR ALL TO authenticated
  USING (company_id IN (SELECT public.auth_company_ids()))
  WITH CHECK (company_id IN (SELECT public.auth_company_ids()));

NOTIFY pgrst, 'reload schema';
