-- ============================================================
-- Seed the 7 global customer_category rows
-- ============================================================
-- These exist on prod (set up via the archived
-- ..20260516000004_customer_category_company_scope migration) but
-- weren't carried into the squashed baseline, so any fresh
-- Supabase project (notably staging when it was first provisioned)
-- started with zero categories. AddCustomerModal then showed a
-- blank required dropdown with no way to add.
--
-- Idempotent: per-row INSERT...ON CONFLICT DO NOTHING against the
-- partial unique index (customer_category, COALESCE(company_id, '__global__'))
-- so re-applying on prod (where the rows already exist) is a no-op.
-- ============================================================

INSERT INTO public.customer_category (customer_category, company_id)
VALUES
  ('Cafe', NULL),
  ('Grocery', NULL),
  ('Hospitality', NULL),
  ('Non Traditional', NULL),
  ('Online', NULL),
  ('Restaurant', NULL),
  ('VIP', NULL)
ON CONFLICT (customer_category, COALESCE(company_id, '__global__'::text)) DO NOTHING;
