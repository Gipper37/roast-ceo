-- ============================================================
-- RLS audit — Phase 1 (DB cleanup)
-- ============================================================
-- Closes three categories of gaps found by the 2026-05-17 audit:
--
--   1. Tables with RLS on but ZERO policies (only accessible via
--      service_role today — invisible the moment the frontend stops
--      bypassing RLS in Phase 2+).
--
--   2. Policies with role = `-` (applies to ALL roles including
--      `anon`). For reference tables this is debatable; for tenant
--      data tables (vmi_checkins, vmi_checkin_items) it is a real
--      bug — anonymous users could read every roaster's check-in
--      history if they knew the right URL.
--
--   3. Duplicate redundant policies left from earlier iterations
--      (older `<table> tenant access` style next to the newer
--      `tenant_facility_access` / `tenant_company_access` snake_case
--      naming). Cleaned up for clarity.
--
-- All policy expressions reuse existing helper functions:
--   auth_company_ids()  — companies the current auth.uid() belongs to
--   auth_facility_ids() — facilities the current auth.uid() can see
-- ============================================================


-- ============================================================
-- (1) Tables with RLS on + zero policies — add tenant-scoped policies
-- ============================================================

-- roast_log_recipes: pivot table joining roast_log → roast_recipes.
-- No tenant columns of its own; scope through roast_log.
CREATE POLICY tenant_via_roast_log ON public.roast_log_recipes
  FOR ALL TO authenticated
  USING (roast_log_id IN (
    SELECT rl.roast_log_id
    FROM public.roast_log rl
    WHERE rl.company_id IN (SELECT auth_company_ids())
  ));

-- roast_profile_nodes: child of roast_profiles. Scope through profile.
CREATE POLICY tenant_via_profile ON public.roast_profile_nodes
  FOR ALL TO authenticated
  USING (profile_id IN (
    SELECT rp.profile_id
    FROM public.roast_profiles rp
    WHERE rp.company_id IN (SELECT auth_company_ids())
  ));

-- sales_activity: small (16 rows) catalog table of activity types.
-- Read-only for any authenticated user; writes restricted to
-- service_role (which bypasses RLS implicitly — no INSERT policy needed).
CREATE POLICY catalog_read ON public.sales_activity
  FOR SELECT TO authenticated
  USING (true);

-- staged_import_sessions: child of data_imports. Scope through import.
CREATE POLICY tenant_via_import ON public.staged_import_sessions
  FOR ALL TO authenticated
  USING (import_id IN (
    SELECT di.import_id
    FROM public.data_imports di
    WHERE di.company_id IN (SELECT auth_company_ids())
  ));


-- ============================================================
-- (1b) Intentionally admin-only tables — leave policies absent,
-- but add a comment so the next auditor knows it is by design.
-- ============================================================

COMMENT ON TABLE public.developer_impersonation_log IS
  'Dev portal only. No RLS policies by design — service_role writes from /app/dev impersonation flow; reads from developer admin tooling.';

COMMENT ON TABLE public.marketing_pageview IS
  'Public marketing-site pageview ingest. No RLS policies by design — service_role inserts from /api/marketing/pageview beacon; reads from /app/dev/traffic admin dashboard.';

COMMENT ON TABLE public.payment_webhook_events IS
  'Payment provider (Activity Pay) webhook log. No RLS policies by design — service_role inserts/reads from /api/webhooks/activitypay handler.';

COMMENT ON TABLE public.subscription_admin_log IS
  'Audit log of admin subscription overrides. No RLS policies by design — service_role writes from internal admin actions; reads from dev portal.';

COMMENT ON TABLE public.roaster_model_smartroast_calibration IS
  'Cross-tenant aggregated calibration data (mean/stddev across all companies). No RLS policies by design — service_role recomputes nightly; reads via SmartRoast inference function.';


-- ============================================================
-- (2) Tighten role = `-` policies that should not include anon
-- ============================================================

-- vmi_checkins: TENANT DATA. Role=`-` was a bug — let anon read everything.
DROP POLICY IF EXISTS tenant_company_access ON public.vmi_checkins;
CREATE POLICY tenant_company_access ON public.vmi_checkins
  FOR ALL TO authenticated
  USING (company_id IN (SELECT auth_company_ids()));

-- vmi_checkin_items: same bug.
DROP POLICY IF EXISTS tenant_via_checkin ON public.vmi_checkin_items;
CREATE POLICY tenant_via_checkin ON public.vmi_checkin_items
  FOR ALL TO authenticated
  USING (vmi_checkin_id IN (
    SELECT vmi_checkin_id
    FROM public.vmi_checkins
    WHERE company_id IN (SELECT auth_company_ids())
  ));

-- customer_category.public_read_global: keep semantically, but
-- restrict to authenticated. Global categories are reference data,
-- still no reason anon needs them.
DROP POLICY IF EXISTS public_read_global ON public.customer_category;
CREATE POLICY public_read_global ON public.customer_category
  FOR SELECT TO authenticated
  USING (company_id IS NULL);


-- ============================================================
-- (3) Drop redundant / legacy policies
-- ============================================================

-- Reference tables: collapse `Public Read Access`, `Global Read`, etc.
-- down to a single `catalog_read` policy (already exists for authenticated).
DROP POLICY IF EXISTS "Public Read Access" ON public.sales_state;
DROP POLICY IF EXISTS "Global Read"        ON public.sales_state;
DROP POLICY IF EXISTS "Public Read Access" ON public.sales_region;
DROP POLICY IF EXISTS "Public Read"        ON public.setup_countries;
DROP POLICY IF EXISTS "Public Read Access" ON public.setup_countries;
DROP POLICY IF EXISTS "Public Read Access" ON public.setup_timezones;
DROP POLICY IF EXISTS "Public Read Access" ON public.user_roles;

-- Roast tables: drop legacy `<table> tenant access` policies (used the
-- older user_facility_ids() helper); keep the newer snake_case
-- tenant_company_access / tenant_facility_access policies.
DROP POLICY IF EXISTS "roast_events tenant access"      ON public.roast_events;
DROP POLICY IF EXISTS "roast_log tenant access"         ON public.roast_log;
DROP POLICY IF EXISTS "roast_sessions tenant access"    ON public.roast_sessions;
DROP POLICY IF EXISTS "roast_temp_nodes tenant access"  ON public.roast_temp_nodes;


-- ============================================================
-- Done. Verify with:
--   SELECT count(*) FROM pg_policy p JOIN pg_class c ON p.polrelid=c.oid
--     JOIN pg_namespace n ON c.relnamespace=n.oid
--     WHERE n.nspname='public' AND p.polroles::regrole[] = ARRAY[0::regrole];
--   -- should be 1 (only shop_config.public_read_enabled, by design)
-- ============================================================
