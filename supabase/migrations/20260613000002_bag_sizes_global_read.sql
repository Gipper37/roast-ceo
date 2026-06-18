-- ============================================================================
-- bag_sizes: allow authenticated tenants to read GLOBAL rows (company_id IS NULL)
-- ----------------------------------------------------------------------------
-- bag_sizes had only the tenant_company_access policy (company_id IN
-- auth_company_ids()), so the 6 standard global bag sizes (company_id IS NULL:
-- 154/132/100/152/66/110) were invisible to EVERY tenant — the "Add Coffee
-- Source" bag-size dropdown came up empty for any company without its own sizes
-- (e.g. MCR). Every sibling global lookup (size, channel, product_type) already
-- has this `catalog_read_global` policy; bag_sizes was the anomaly. Mirror it.
-- ============================================================================

BEGIN;

DROP POLICY IF EXISTS catalog_read_global ON public.bag_sizes;
CREATE POLICY catalog_read_global ON public.bag_sizes
    AS PERMISSIVE FOR SELECT TO authenticated
    USING (company_id IS NULL);

COMMIT;
