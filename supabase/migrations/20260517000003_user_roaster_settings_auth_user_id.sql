-- ============================================================
-- user_roaster_settings: add auth_user_id FK and switch RLS off email
-- ============================================================
-- The interim fix (20260517000002) introduced auth_user_email() — a
-- SECURITY DEFINER helper that fetches the current user's email from
-- auth.users so the policy could join by email without exposing
-- auth.users to authenticated.
--
-- A proper FK is cleaner: add user_roaster_settings.auth_user_id and
-- write the policy against auth.uid() directly. No SECURITY DEFINER
-- helper required, no email-string normalization weirdness, future
-- email changes don't break ownership.
--
-- Backfill: every existing row gets its auth_user_id resolved by
-- looking up auth.users by lower(email). Rows whose email doesn't
-- match any auth user remain NULL (orphaned settings — harmless,
-- they simply won't be visible/editable until reclaimed).
-- ============================================================

ALTER TABLE public.user_roaster_settings
  ADD COLUMN IF NOT EXISTS auth_user_id uuid;

-- Backfill from email
UPDATE public.user_roaster_settings urs
SET auth_user_id = u.id
FROM auth.users u
WHERE urs.auth_user_id IS NULL
  AND lower(urs.email) = lower(u.email);

-- Index for the RLS lookup
CREATE INDEX IF NOT EXISTS user_roaster_settings_auth_user_id_idx
  ON public.user_roaster_settings (auth_user_id);

-- New policy: ownership by auth_user_id directly, with company scope
-- preserved as a defense-in-depth check.
DROP POLICY IF EXISTS user_owns_row ON public.user_roaster_settings;
CREATE POLICY user_owns_row ON public.user_roaster_settings
  FOR ALL TO authenticated
  USING (
    auth_user_id = auth.uid()
    AND company_id IN (SELECT auth_company_ids())
  );

-- The interim helper is no longer needed.
DROP FUNCTION IF EXISTS public.auth_user_email();
