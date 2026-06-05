-- product_category table + products.category_id FK
-- For grouping product_groups into broader marketing/inventory categories
-- (e.g. "Hawaiian", "Flavor", "Organic", "VIP", "Custom Coffees").

BEGIN;

CREATE TABLE IF NOT EXISTS public.product_category (
    id          text PRIMARY KEY DEFAULT gen_random_uuid()::text,
    company_id  text NOT NULL REFERENCES public.companies(company_id) ON DELETE CASCADE,
    name        text NOT NULL,
    sort_order  integer,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    created_by  text,
    updated_by  text,
    is_active   boolean NOT NULL DEFAULT true,
    CONSTRAINT product_category_company_name_unique UNIQUE (company_id, name)
);

CREATE INDEX IF NOT EXISTS idx_product_category_company ON public.product_category(company_id);

ALTER TABLE public.product_category ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "tenant_company_access" ON public.product_category;
CREATE POLICY "tenant_company_access" ON public.product_category
    TO authenticated
    USING (company_id IN (SELECT auth_company_ids()))
    WITH CHECK (company_id IN (SELECT auth_company_ids()));

-- audit triggers (match other tables)
DROP TRIGGER IF EXISTS trg_audit_insert ON public.product_category;
CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.product_category
    FOR EACH ROW EXECUTE FUNCTION handle_new_record();

DROP TRIGGER IF EXISTS trg_audit_update ON public.product_category;
CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.product_category
    FOR EACH ROW EXECUTE FUNCTION handle_updated_record();

-- products.category_id
ALTER TABLE public.products
    ADD COLUMN IF NOT EXISTS category_id text
        REFERENCES public.product_category(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_products_category_id ON public.products(category_id);

COMMIT;
