-- ============================================================
-- Add catalog_read_global policies to every global-lookup table
-- ============================================================
-- channel was the surfaced symptom (..28000003) but the audit found
-- 3 more lookup tables with the same RLS-hides-globals bug:
--   management_type, product_type, size
--
-- All have rows where company_id IS NULL (intentional globals shared
-- across tenants) but only a tenant-scoped policy that filters them
-- out. Writes still require tenant ownership; this is read-only.
-- customer_category already has its public_read_global policy.
-- ============================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy WHERE polname = 'catalog_read_global'
      AND polrelid = 'public.management_type'::regclass
  ) THEN
    CREATE POLICY catalog_read_global ON public.management_type
      FOR SELECT TO authenticated
      USING (company_id IS NULL);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policy WHERE polname = 'catalog_read_global'
      AND polrelid = 'public.product_type'::regclass
  ) THEN
    CREATE POLICY catalog_read_global ON public.product_type
      FOR SELECT TO authenticated
      USING (company_id IS NULL);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policy WHERE polname = 'catalog_read_global'
      AND polrelid = 'public.size'::regclass
  ) THEN
    CREATE POLICY catalog_read_global ON public.size
      FOR SELECT TO authenticated
      USING (company_id IS NULL);
  END IF;
END $$;
