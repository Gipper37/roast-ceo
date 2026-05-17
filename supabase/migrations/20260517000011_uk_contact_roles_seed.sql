-- ============================================================
-- Seed missing "Manager" + "General Manager" roles for Social Hour UK
-- ============================================================
-- After migration ..010 fixed cross-company contact role refs, 11 UK
-- contacts were still pointing at US-only roles ("Manager", "General
-- Manager") because the UK role catalog didn't have those labels.
-- This migration inserts them so the fix completes.
--
-- The actual contact UPDATE was already applied to prod by hand
-- (see release notes for release-2026-05-16-3); this migration just
-- ensures the seed exists for replays + does an idempotent re-run
-- of the cross-company fix in case any new orphan contacts appear.
-- ============================================================

-- Idempotent: only inserts if a role with that label doesn't already exist for UK
INSERT INTO public.contact_role (contact_role_id, contact_role, company_id, created_at)
SELECT substring(gen_random_uuid()::text, 1, 8), label, '752af3ed-4', now()
FROM (VALUES ('Manager'), ('General Manager')) v(label)
WHERE EXISTS (SELECT 1 FROM public.companies WHERE company_id = '752af3ed-4')
  AND NOT EXISTS (
    SELECT 1 FROM public.contact_role
    WHERE company_id = '752af3ed-4' AND lower(contact_role) = lower(v.label)
  );

-- Re-run the cross-company fix (no-op if already clean)
DO $$
DECLARE
  r RECORD; fix_id text; fixed int := 0;
BEGIN
  FOR r IN
    SELECT c.contact_id, c.company_id, cr.contact_role AS role_label
    FROM public.contacts c
    JOIN public.contact_role cr ON cr.contact_role_id = c.role
    WHERE c.role IS NOT NULL AND c.company_id != cr.company_id
  LOOP
    SELECT contact_role_id INTO fix_id
    FROM public.contact_role
    WHERE company_id = r.company_id AND lower(contact_role) = lower(r.role_label)
    LIMIT 1;
    IF fix_id IS NOT NULL THEN
      UPDATE public.contacts SET role = fix_id WHERE contact_id = r.contact_id;
      fixed := fixed + 1;
    END IF;
  END LOOP;
  IF fixed > 0 THEN RAISE NOTICE 'Re-fixed % contacts', fixed; END IF;
END $$;
