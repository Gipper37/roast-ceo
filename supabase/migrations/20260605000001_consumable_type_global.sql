-- ============================================================
-- Make consumable_type a global lookup table
-- ============================================================
-- consumable_type only ever has two values: 'product' (= BOM) and
-- 'operational'. There's no reason to seed those per-company — every
-- tenant has the same two. Today, the signup function creates a pair
-- per tenant which means:
--   - 2 rows × N tenants = bloat (6 today, will grow with each signup)
--   - per-tenant UUIDs break any code that wants a stable reference
--   - new tenants need a seeding step that can fail silently
--
-- Migrate to: two global rows (company_id IS NULL), all existing
-- consumable_inventory rows remapped to point at the globals, per-tenant
-- rows removed. A SELECT-only RLS policy lets every authenticated user
-- read the globals (matches the pattern we landed on customer_category,
-- channel, management_type, product_type, size).
--
-- Idempotent throughout.
-- ============================================================

-- 1. Insert the global pair (stable IDs so future references are easy).
INSERT INTO public.consumable_type (consumable_type_id, consumable_type, company_id, is_active)
VALUES
  ('global_consumable_type_product',     'product',     NULL, true),
  ('global_consumable_type_operational', 'operational', NULL, true)
ON CONFLICT (consumable_type_id) DO NOTHING;

-- 2. Remap every consumable_inventory.consumable_type FK from per-tenant
--    rows to the global ones, matched by consumable_type name.
UPDATE public.consumable_inventory ci
SET consumable_type = CASE lower(old.consumable_type)
    WHEN 'product'     THEN 'global_consumable_type_product'
    WHEN 'operational' THEN 'global_consumable_type_operational'
END
FROM public.consumable_type old
WHERE ci.consumable_type = old.consumable_type_id
  AND old.company_id IS NOT NULL
  AND lower(old.consumable_type) IN ('product', 'operational');

-- 3. Delete the per-tenant rows. Safe now that nothing references them.
DELETE FROM public.consumable_type
WHERE company_id IS NOT NULL
  AND lower(consumable_type) IN ('product', 'operational');

-- 4. Allow all authenticated users to SELECT global rows. Existing
--    tenant_company_access policy hides NULL company_id rows because
--    `company_id IN (SELECT auth_company_ids())` never matches NULL.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polname = 'catalog_read_global'
      AND polrelid = 'public.consumable_type'::regclass
  ) THEN
    CREATE POLICY catalog_read_global ON public.consumable_type
      FOR SELECT TO authenticated
      USING (company_id IS NULL);
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
