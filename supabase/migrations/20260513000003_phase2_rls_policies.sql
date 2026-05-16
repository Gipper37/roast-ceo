-- =============================================================================
-- Phase 2: RLS policies — per-table, scoped by company/facility/user.
-- =============================================================================
-- Phase 1 (20260513000001) revoked the anon role on every public table/view —
-- the REST surface returns 401 to unauthenticated callers. Phase 2 builds the
-- policy layer so the `authenticated` role can eventually replace `service_role`
-- in the app's data path WITHOUT cross-tenant leakage.
--
-- Strategy
--   * service_role bypasses RLS entirely → existing app code (server actions
--     using service_role) is untouched. These policies are forward-looking.
--   * Every tenant table: `company_id IN (auth_company_ids())`.
--   * Per-user state (user_parameters, user_roaster_settings): scope by
--     auth.uid() AND company.
--   * Customer-facing tables (orders, customers): allow customer_users access
--     restricted to their own customer_id (shop login).
--   * Global catalog tables (permissions, roles, countries, plans, etc.):
--     SELECT-only for authenticated; writes stay service_role-only.
--   * Admin/log tables (developer_*, subscription_admin_log,
--     payment_webhook_events, roaster_model_smartroast_calibration): no
--     authenticated access at all (RLS enabled, zero policies).
--
-- Idempotent: every CREATE POLICY is preceded by DROP POLICY IF EXISTS.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Helper functions
-- -----------------------------------------------------------------------------
-- Each is SECURITY DEFINER + STABLE so it can sit inside policy USING() clauses
-- without recursing into the RLS check on `team` itself. STRICT not used (we
-- want to handle the anonymous case gracefully: returns empty set, not NULL).

CREATE OR REPLACE FUNCTION public.auth_company_ids()
RETURNS SETOF text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT company_id
  FROM public.team
  WHERE auth_user_id = auth.uid()
    AND COALESCE(is_active, true) = true
    AND company_id IS NOT NULL;
$$;

CREATE OR REPLACE FUNCTION public.auth_facility_ids()
RETURNS SETOF text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT facility_id
  FROM public.team
  WHERE auth_user_id = auth.uid()
    AND COALESCE(is_active, true) = true
    AND facility_id IS NOT NULL;
$$;

-- Customer (shop) users: returns customer_ids the current auth user owns.
CREATE OR REPLACE FUNCTION public.auth_customer_ids()
RETURNS SETOF text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT customer_id
  FROM public.customer_users
  WHERE auth_user_id = auth.uid();
$$;

-- Company-admin check (used by KYC, payments, billing surfaces).
CREATE OR REPLACE FUNCTION public.auth_is_company_admin(p_company_id text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.team
    WHERE auth_user_id = auth.uid()
      AND company_id = p_company_id
      AND role IN ('company_admin', 'facility_admin')
      AND COALESCE(is_active, true) = true
  );
$$;

-- Lock helpers down: only authenticated callers should touch these. service_role
-- gets implicit access via SUPERUSER. anon was already revoked in Phase 1 from
-- the public schema, but be explicit.
REVOKE ALL ON FUNCTION public.auth_company_ids()       FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.auth_facility_ids()      FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.auth_customer_ids()      FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.auth_is_company_admin(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.auth_company_ids()       TO authenticated;
GRANT EXECUTE ON FUNCTION public.auth_facility_ids()      TO authenticated;
GRANT EXECUTE ON FUNCTION public.auth_customer_ids()      TO authenticated;
GRANT EXECUTE ON FUNCTION public.auth_is_company_admin(text) TO authenticated;

-- -----------------------------------------------------------------------------
-- 2. Tenant tables — company_id scoping
-- -----------------------------------------------------------------------------
-- One uniform FOR ALL policy per table: row visible iff its company_id is in
-- the caller's set. Same predicate for USING (read/update/delete row visibility)
-- and WITH CHECK (insert/update target row).

DO $$
DECLARE
  t text;
  tenant_tables text[] := ARRAY[
    'bag_sizes',
    'blending_worksheet',
    'channel',
    'charge_weight_options',
    'chargebacks',
    'coffee_inventory',
    'coffee_inventory_history',
    'coffee_inventory_purchased',
    'coffee_source',
    'coffee_usage_by_month',
    'companies',
    'company_kyc',
    'company_kyc_beneficial_owners',
    'company_kyc_documents',
    'company_parameters',
    'consumable_inventory',
    'consumable_inventory_history',
    'consumable_inventory_purchased',
    'consumable_type',
    'contact_role',
    'contacts',
    'customer_notes_detail',
    'customer_sales_filter',
    'customers',
    'data_imports',
    'facilities',
    'invitations',
    'invoice_documents',
    'management_type',
    'open_order_totals',
    'order_details',
    'order_statuses',
    'orders',
    'payment_transactions',
    'payouts',
    'prep_type',
    'product_consumables',
    'product_filter',
    'product_groups',
    'product_type',
    'products',
    'products_price_log',
    'recent_coffee_order',
    'recipe_components',
    'restock_category',
    'roast_log',
    'roast_profiles',
    'roast_recipes',
    'roast_sessions',
    'roast_smartroast_log',
    'roast_stock_log',
    'roaster_bank_accounts',
    'roaster_unit_smartroast_calibration',
    'roaster_units',
    'sales_area',
    'sales_category',
    'sales_city',
    'sales_data_filter',
    'sales_goals',
    'sales_notes',
    'sales_parameters',
    'sales_state_backup',
    'sales_tasks',
    'sales_tracking',
    'shipment_received',
    'shop_config',
    'shop_invitations',
    'shop_order_ref_counter',
    'shopify_connections',
    'shopify_product_mappings',
    'size',
    'staged_line_items',
    'staged_shipments',
    'statements',
    'subscriptions',
    'supplier',
    'supplier_category',
    'tax_forms',
    'weekly_roast_snapshot'
  ];
BEGIN
  FOREACH t IN ARRAY tenant_tables LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS tenant_company_access ON public.%I', t);
    EXECUTE format($p$
      CREATE POLICY tenant_company_access ON public.%I
        FOR ALL TO authenticated
        USING (company_id IN (SELECT public.auth_company_ids()))
        WITH CHECK (company_id IN (SELECT public.auth_company_ids()))
    $p$, t);
  END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- 3. Facility-only tables (no company_id column, but facility_id present)
-- -----------------------------------------------------------------------------
-- `recipe_weekly_targets`, `roast_events`, `roast_temp_nodes` are scoped by
-- facility — bridge through facilities.company_id.

ALTER TABLE public.recipe_weekly_targets ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_facility_access ON public.recipe_weekly_targets;
CREATE POLICY tenant_facility_access ON public.recipe_weekly_targets
  FOR ALL TO authenticated
  USING (facility_id IN (SELECT public.auth_facility_ids()))
  WITH CHECK (facility_id IN (SELECT public.auth_facility_ids()));

ALTER TABLE public.roast_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_facility_access ON public.roast_events;
CREATE POLICY tenant_facility_access ON public.roast_events
  FOR ALL TO authenticated
  USING (facility_id IN (SELECT public.auth_facility_ids()))
  WITH CHECK (facility_id IN (SELECT public.auth_facility_ids()));

ALTER TABLE public.roast_temp_nodes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_facility_access ON public.roast_temp_nodes;
CREATE POLICY tenant_facility_access ON public.roast_temp_nodes
  FOR ALL TO authenticated
  USING (facility_id IN (SELECT public.auth_facility_ids()))
  WITH CHECK (facility_id IN (SELECT public.auth_facility_ids()));

-- -----------------------------------------------------------------------------
-- 4. Per-user tables — scope by auth.uid()
-- -----------------------------------------------------------------------------

-- user_parameters: one user's overrides only (still bounded by company too).
ALTER TABLE public.user_parameters ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS user_owns_row ON public.user_parameters;
CREATE POLICY user_owns_row ON public.user_parameters
  FOR ALL TO authenticated
  USING (user_id = auth.uid()
         AND company_id IN (SELECT public.auth_company_ids()))
  WITH CHECK (user_id = auth.uid()
              AND company_id IN (SELECT public.auth_company_ids()));

-- user_roaster_settings: keyed by email, gated by company.
ALTER TABLE public.user_roaster_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS user_owns_row ON public.user_roaster_settings;
CREATE POLICY user_owns_row ON public.user_roaster_settings
  FOR ALL TO authenticated
  USING (
    company_id IN (SELECT public.auth_company_ids())
    AND lower(email) = lower((SELECT email FROM auth.users WHERE id = auth.uid()))
  )
  WITH CHECK (
    company_id IN (SELECT public.auth_company_ids())
    AND lower(email) = lower((SELECT email FROM auth.users WHERE id = auth.uid()))
  );

-- team: members of any of the caller's companies are visible. Writes restricted
-- to admins of that company.
ALTER TABLE public.team ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS team_read_same_company ON public.team;
CREATE POLICY team_read_same_company ON public.team
  FOR SELECT TO authenticated
  USING (
    company_id IN (SELECT public.auth_company_ids())
    OR auth_user_id = auth.uid()
  );
DROP POLICY IF EXISTS team_self_update ON public.team;
CREATE POLICY team_self_update ON public.team
  FOR UPDATE TO authenticated
  USING (auth_user_id = auth.uid())
  WITH CHECK (auth_user_id = auth.uid());
DROP POLICY IF EXISTS team_admin_write ON public.team;
CREATE POLICY team_admin_write ON public.team
  FOR ALL TO authenticated
  USING (public.auth_is_company_admin(company_id))
  WITH CHECK (public.auth_is_company_admin(company_id));

-- -----------------------------------------------------------------------------
-- 5. Customer (shop) tables — customer_users-mediated access
-- -----------------------------------------------------------------------------
-- A shop buyer is an auth user with a row in customer_users. They can:
--   - read their own customer record
--   - read their own orders + order_details
--   - read their own customer_users row(s)
-- Roaster team access already granted via section 2 (customers, orders,
-- order_details are tenant tables). RLS combines policies with OR — multiple
-- policies on the same table both pass.

DROP POLICY IF EXISTS shop_buyer_self_customer ON public.customers;
CREATE POLICY shop_buyer_self_customer ON public.customers
  FOR SELECT TO authenticated
  USING (customer_id IN (SELECT public.auth_customer_ids()));

DROP POLICY IF EXISTS shop_buyer_self_orders ON public.orders;
CREATE POLICY shop_buyer_self_orders ON public.orders
  FOR SELECT TO authenticated
  USING (customer_id IN (SELECT public.auth_customer_ids()));

DROP POLICY IF EXISTS shop_buyer_self_order_details ON public.order_details;
CREATE POLICY shop_buyer_self_order_details ON public.order_details
  FOR SELECT TO authenticated
  USING (customer_id IN (SELECT public.auth_customer_ids()));

ALTER TABLE public.customer_users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS shop_buyer_self_customer_users ON public.customer_users;
CREATE POLICY shop_buyer_self_customer_users ON public.customer_users
  FOR SELECT TO authenticated
  USING (auth_user_id = auth.uid());
-- Roaster admins of the customer's company can manage their shop users.
DROP POLICY IF EXISTS roaster_manage_customer_users ON public.customer_users;
CREATE POLICY roaster_manage_customer_users ON public.customer_users
  FOR ALL TO authenticated
  USING (
    customer_id IN (
      SELECT c.customer_id FROM public.customers c
      WHERE c.company_id IN (SELECT public.auth_company_ids())
    )
  )
  WITH CHECK (
    customer_id IN (
      SELECT c.customer_id FROM public.customers c
      WHERE c.company_id IN (SELECT public.auth_company_ids())
    )
  );

-- -----------------------------------------------------------------------------
-- 6. Global catalog tables — read-only for authenticated
-- -----------------------------------------------------------------------------
-- No tenant column, content is reference data shared across all companies.
-- Writes stay service_role-only (handled by the missing INSERT/UPDATE policy).

DO $$
DECLARE
  t text;
  catalog_tables text[] := ARRAY[
    'app_menu',
    'customer_category',
    'get_started',
    'onboarding_slides',
    'permissions',
    'plan_permissions',
    'role_permissions',
    'sales_region',
    'sales_state',
    'setup_countries',
    'setup_timezones',
    'standard_parameters',
    'stock_types',
    'subscription_plans',
    'user_roles',
    'company_signup_form'
  ];
BEGIN
  FOREACH t IN ARRAY catalog_tables LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS catalog_read ON public.%I', t);
    EXECUTE format($p$
      CREATE POLICY catalog_read ON public.%I
        FOR SELECT TO authenticated
        USING (true)
    $p$, t);
  END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- 7. Service-role-only tables — RLS on, no policies → authenticated locked out
-- -----------------------------------------------------------------------------
-- Webhook ingestion, audit/admin logs, cross-tenant ML calibration, internal
-- staging. Frontend has no business reading these directly; if anything ever
-- needs them it goes through a server action with service_role.

ALTER TABLE public.developer_users                       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.developer_impersonation_log           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_admin_log                ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_webhook_events                ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.roaster_model_smartroast_calibration  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staged_import_sessions                ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.roast_log_recipes                     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.roast_profile_nodes                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_activity                        ENABLE ROW LEVEL SECURITY;

-- Developer self-read (lets a logged-in dev confirm their own dev-portal access
-- without service_role).
DROP POLICY IF EXISTS dev_self_read ON public.developer_users;
CREATE POLICY dev_self_read ON public.developer_users
  FOR SELECT TO authenticated
  USING (auth_user_id = auth.uid());

COMMIT;

-- =============================================================================
-- Verification queries (run manually post-push):
--   SELECT relname,
--          relrowsecurity AS rls_on,
--          (SELECT count(*) FROM pg_policies p
--             WHERE p.schemaname='public' AND p.tablename=c.relname) AS policies
--   FROM pg_class c
--   JOIN pg_namespace n ON n.oid=c.relnamespace
--   WHERE n.nspname='public' AND c.relkind='r'
--   ORDER BY relrowsecurity, policies, relname;
--
-- Expected after this migration: every base table in public has
-- relrowsecurity=true. Tables with ZERO policies are intentionally
-- service-role-only (see section 7).
-- =============================================================================
