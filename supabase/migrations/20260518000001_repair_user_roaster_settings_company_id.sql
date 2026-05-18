-- ============================================================
-- Repair: user_roaster_settings.company_id desync
-- ============================================================
-- Some users' settings rows have a stale or NULL company_id that no
-- longer matches their current team membership. RLS policy on this
-- table requires company_id IN auth_company_ids(), so the user can't
-- read their own row → app shows the "Roasting on" picker as empty
-- even though roaster_unit_id is set. They unblock by re-selecting,
-- which upserts a fresh row with the correct company.
--
-- Root cause: migration ..003 backfilled auth_user_id but didn't
-- touch company_id, so any user whose team row changed company
-- between rows being created and the backfill kept the old value
-- (or NULL for rows created before company_id was added).
--
-- Fix: align settings.company_id with team.company_id for the
-- single team row keyed on email. Idempotent.
-- ============================================================

UPDATE public.user_roaster_settings urs
SET company_id  = t.company_id,
    facility_id = COALESCE(t.facility_id, urs.facility_id),
    auth_user_id = COALESCE(t.auth_user_id, urs.auth_user_id),
    updated_at  = now()
FROM public.team t
WHERE t.email = urs.email
  AND t.is_active = true
  AND (urs.company_id IS NULL OR urs.company_id <> t.company_id);
