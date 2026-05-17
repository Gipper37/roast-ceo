-- =============================================================================
-- email_log — add tenant_company_access RLS policy
-- =============================================================================
-- email_log was created in 20260514000003 with RLS enabled but ZERO
-- policies, meaning the `authenticated` role couldn't see any rows
-- (only service_role bypassed). Frontend reads currently route
-- through service_role server actions so it worked, but the table
-- doesn't match the Phase 2 RLS posture for tenant-scoped tables.
--
-- Adding the standard tenant policy so the email_log behaves like
-- every other tenant-scoped table (customers, orders, etc.):
-- authenticated users see rows where company_id matches a company
-- they belong to (via team membership). Inserts must also belong
-- to one of their companies.
--
-- Future-proof: when the app moves customer-detail / reports
-- queries off service_role to the authenticated client, the
-- Reminders section + Account Management report tab will continue
-- to work without code changes.
-- =============================================================================

DROP POLICY IF EXISTS tenant_company_access ON public.email_log;
CREATE POLICY tenant_company_access ON public.email_log
  FOR ALL TO authenticated
  USING (company_id IN (SELECT public.auth_company_ids()))
  WITH CHECK (company_id IN (SELECT public.auth_company_ids()));

-- Verification:
--   SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='email_log';
--   -- Expected: tenant_company_access
