-- customer_category: global rows + per-tenant rows.
--
-- Was a fully global single-table catalog. Any tenant's seed
-- migration could pollute the global list (Social Hour's demo
-- added "Hotel" + "Wholesale" which then leaked into every
-- roaster's dropdown).
--
-- New model matches the pattern we use for channel, product_type,
-- management_type, size, etc.:
--   - company_id NULL  → global (visible to all tenants)
--   - company_id set   → owned by that tenant only
-- RLS lets anyone read globals + members read their own.
-- The 7 base categories (Cafe / Grocery / Hospitality / Non
-- Traditional / Online / Restaurant / VIP) stay global. Hotel +
-- Wholesale demo additions get removed (Hotel has 0 customers;
-- Wholesale's 2 customers get reassigned to Cafe before delete).

-- 1) Reassign Wholesale customers BEFORE deleting the category so
--    the data has somewhere to land. Both are demo data (Harbor
--    Brew Co. + Maple Street Coffee).
UPDATE public.customers
SET    customer_category = 'Cafe'
WHERE  customer_category = 'Wholesale';

-- 2) Add company_id column + surrogate PK.
--    Old PK was the category name itself — fine for global-only but
--    blocks per-tenant rows (each tenant would want their own
--    "Custom Type" without colliding with another tenant's row).
ALTER TABLE public.customer_category
  DROP CONSTRAINT IF EXISTS customer_category_pkey;

ALTER TABLE public.customer_category
  ADD COLUMN IF NOT EXISTS id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ADD COLUMN IF NOT EXISTS company_id text REFERENCES public.companies(company_id) ON DELETE CASCADE;

-- 3) Unique per (name, company). NULL company_id = global; coalesce
--    so the unique constraint treats globals as a single namespace
--    (you can't have two global rows with the same name).
CREATE UNIQUE INDEX IF NOT EXISTS customer_category_name_company_idx
  ON public.customer_category (customer_category, COALESCE(company_id, '__global__'));

-- 4) Drop demo-polluted rows. By this point no customer row
--    references either (Wholesale rebased above, Hotel already
--    had zero customers).
DELETE FROM public.customer_category
WHERE  customer_category IN ('Hotel', 'Wholesale')
  AND  company_id IS NULL;

-- 5) RLS — replace the wide-open "Public Read Access" with the
--    standard global-or-member pattern.
DROP POLICY IF EXISTS "Public Read Access" ON public.customer_category;
DROP POLICY IF EXISTS catalog_read ON public.customer_category;

-- Anyone can read globals (needed for storefront / unauth contexts
-- + any future public surface that lists categories).
CREATE POLICY public_read_global ON public.customer_category
  FOR SELECT
  USING (company_id IS NULL);

-- Tenant members can read + write their own company's rows. Writes
-- to globals are blocked at the RLS layer (only service_role can
-- seed new globals via migrations).
CREATE POLICY tenant_company_access ON public.customer_category
  FOR ALL
  USING (company_id IN (SELECT auth_company_ids()))
  WITH CHECK (company_id IN (SELECT auth_company_ids()));

-- Grant SELECT to anon so unauth shop surfaces (e.g. categorized
-- public storefronts later) can read globals. Authenticated already
-- has SELECT.
GRANT SELECT ON public.customer_category TO anon;

-- Verification (post-push):
--   SELECT customer_category, company_id FROM customer_category ORDER BY 1;
--   -- Expected: 7 globals (Cafe, Grocery, Hospitality, Non Traditional, Online, Restaurant, VIP)
--   -- No Hotel. No Wholesale.
