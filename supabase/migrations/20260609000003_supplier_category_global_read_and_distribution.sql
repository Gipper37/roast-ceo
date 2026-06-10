-- 1. Add global read policy to supplier_category so all authenticated users
--    can see global categories (company_id IS NULL) — same pattern as channels.
--    The existing tenant_company_access policy blocks NULL company_id rows.
CREATE POLICY "supplier_category_global_read"
  ON public.supplier_category
  FOR SELECT
  TO authenticated
  USING (company_id IS NULL OR company_id IN (SELECT auth_company_ids()));

-- 2. Add Distribution supplier category (global)
INSERT INTO public.supplier_category (supplier_category_id, supplier_category, company_id)
VALUES ('Ds7mKP', 'Distribution', NULL)
ON CONFLICT (supplier_category_id) DO NOTHING;
