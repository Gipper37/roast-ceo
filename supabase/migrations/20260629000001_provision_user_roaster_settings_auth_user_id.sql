-- Fix: every newly provisioned user_roaster_settings row had auth_user_id = NULL,
-- so the table's RLS policy `USING (auth_user_id = auth.uid())` matched ZERO rows
-- for that user — they couldn't read OR write their own roaster settings (the
-- wk-avg/orders toggle, projected source, picked roaster all silently froze).
--
-- The auto-provision trigger inserted email/facility/company/roaster but never
-- auth_user_id. This:
--   (1) makes the trigger set auth_user_id from the team row, and
--   (2) backfills it on conflict if a later team insert (e.g. invite accept)
--       supplies the auth_user_id after the settings row already existed, and
--   (3) one-time backfills existing rows from team (idempotent — matches the
--       data correction already applied live).

CREATE OR REPLACE FUNCTION public.provision_user_roaster_settings()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_default_roaster uuid;
BEGIN
    IF NEW.email IS NOT NULL THEN
        SELECT roaster_unit_id INTO v_default_roaster
          FROM public.roaster_units
         WHERE facility_id = NEW.facility_id AND is_active = true
         ORDER BY created_at
         LIMIT 1;

        INSERT INTO public.user_roaster_settings
            (email, facility_id, company_id, roaster_unit_id, auth_user_id)
        VALUES
            (NEW.email, NEW.facility_id, NEW.company_id, v_default_roaster, NEW.auth_user_id)
        ON CONFLICT (email) DO UPDATE
            -- Backfill auth_user_id when the existing row is missing it and the
            -- new team row supplies one (e.g. invite accept linking the auth
            -- user after the settings row was auto-created). Never overwrite a
            -- good value, and never blank it back to NULL.
            SET auth_user_id = EXCLUDED.auth_user_id
            WHERE public.user_roaster_settings.auth_user_id IS NULL
              AND EXCLUDED.auth_user_id IS NOT NULL;
    END IF;
    RETURN NEW;
END;
$function$;

-- One-time backfill for rows that predate the trigger fix (scoped to NULLs so a
-- correct value is never disturbed; auth_user_id is the same person regardless
-- of which company team row matches the email).
UPDATE public.user_roaster_settings urs
SET auth_user_id = t.auth_user_id
FROM public.team t
WHERE lower(t.email) = lower(urs.email)
  AND t.is_active = true
  AND t.auth_user_id IS NOT NULL
  AND urs.auth_user_id IS NULL;
