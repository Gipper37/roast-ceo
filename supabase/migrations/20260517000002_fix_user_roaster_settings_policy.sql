-- ============================================================
-- Fix user_roaster_settings RLS policy
-- ============================================================
-- The existing policy joined to auth.users by email to identify
-- the current user, which requires SELECT grant on auth.users —
-- which `authenticated` does not have. Result: every query against
-- user_roaster_settings as the authenticated role failed with
-- "permission denied for table users".
--
-- This was masked because every caller used service_role (which
-- bypasses RLS entirely). Phase 3+4 of the RLS audit switched the
-- frontend to RLS-respecting clients, which surfaced the bug.
--
-- Fix: replace the email-join with a SECURITY DEFINER helper that
-- looks up the current user's email without exposing auth.users.
-- ============================================================

CREATE OR REPLACE FUNCTION public.auth_user_email()
RETURNS text
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth
STABLE
AS $$
  SELECT email::text FROM auth.users WHERE id = auth.uid()
$$;

REVOKE EXECUTE ON FUNCTION public.auth_user_email() FROM public;
GRANT EXECUTE ON FUNCTION public.auth_user_email() TO authenticated;

DROP POLICY IF EXISTS user_owns_row ON public.user_roaster_settings;

CREATE POLICY user_owns_row ON public.user_roaster_settings
  FOR ALL TO authenticated
  USING (
    company_id IN (SELECT auth_company_ids())
    AND lower(email) = lower(auth_user_email())
  );
