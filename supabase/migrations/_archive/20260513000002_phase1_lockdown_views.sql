-- Phase 1 lockdown — views follow-up.
--
-- The previous migration (20260513000001) used pg_tables to sweep all
-- TABLES in `public` and revoke anon grants. Views aren't in pg_tables
-- — they're in pg_views — so 21 of them stayed wide open with anon
-- SELECT (the warning at the end of that migration listed them).
--
-- This sweeps every view in `public` and revokes anon SELECT, closing
-- the same Data API exposure path. Same safety profile: leaves
-- authenticated + service_role grants alone.

BEGIN;

DO $$
DECLARE
  v record;
  revoked int := 0;
BEGIN
  FOR v IN
    SELECT viewname FROM pg_views WHERE schemaname = 'public'
    UNION
    SELECT matviewname FROM pg_matviews WHERE schemaname = 'public'
    ORDER BY 1
  LOOP
    EXECUTE format('REVOKE ALL ON public.%I FROM anon', v.viewname);
    revoked := revoked + 1;
  END LOOP;
  RAISE NOTICE 'Phase 1 view lockdown: revoked anon on % public views', revoked;
END $$;

DO $$
DECLARE
  leak_count int;
  leak_list text;
BEGIN
  SELECT COUNT(DISTINCT table_name), string_agg(DISTINCT table_name, ', ' ORDER BY table_name)
  INTO leak_count, leak_list
  FROM information_schema.table_privileges
  WHERE table_schema = 'public' AND grantee = 'anon';
  IF leak_count > 0 THEN
    RAISE WARNING 'Anon still has privileges on % objects: %', leak_count, leak_list;
  ELSE
    RAISE NOTICE 'Anon has no privileges remaining on any public object — Phase 1 fully complete.';
  END IF;
END $$;

COMMIT;
