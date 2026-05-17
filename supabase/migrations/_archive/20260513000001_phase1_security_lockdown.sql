-- Phase 1 — emergency security lockdown (REVOKE anon only).
--
-- ── The problem ────────────────────────────────────────────────────
-- The legacy Supabase default left every public table with broad
-- SELECT/INSERT/UPDATE/DELETE grants to BOTH `anon` and
-- `authenticated`. With the anon key bundled into the frontend
-- (NEXT_PUBLIC_SUPABASE_ANON_KEY is publicly readable by design),
-- ANY visitor can hit the Data API directly:
--
--     curl https://<proj>.supabase.co/rest/v1/company_kyc \
--          -H "apikey: <NEXT_PUBLIC_SUPABASE_ANON_KEY>"
--
-- and dump KYC, payment transactions, auth catalogs, etc. Production
-- traffic doesn't notice because the server actions all use
-- `createClient` from `lib/supabase/server.ts` which loads
-- `SUPABASE_SERVICE_ROLE_KEY` and bypasses RLS entirely. The exposure
-- only matters for direct anon-key probes — which an attacker can do
-- trivially.
--
-- ── Why REVOKE FROM anon (and not also from authenticated) ─────────
-- 13 client-side files call createClient from @/lib/supabase/client
-- and read tables directly. Those calls execute as the `authenticated`
-- role (the session JWT travels with the request) once a user is
-- logged in. They depend on:
--   (a) the `authenticated` GRANT, and
--   (b) either no RLS, or a policy that admits the row.
-- Touching `authenticated` grants — or flipping RLS on a table
-- without a matching policy — would silently break those reads.
-- This Phase 1 leaves both untouched and ONLY revokes anon.
--
-- After this migration:
--   - anon: blocked from EVERY public table at the grant layer
--   - authenticated: unchanged (existing client queries keep working)
--   - service_role: unchanged (server actions keep working)
--
-- Phase 2 (separate effort) will:
--   - Enable RLS on the tables that still lack it
--   - Write per-table policies scoped by company_id
--   - Tighten authenticated grants once the policy layer is solid
--
-- ── Scope ──────────────────────────────────────────────────────────
-- Sweeps EVERY table in `public`. The Supabase guidance going forward
-- (May 30 default change) is exactly this: no default Data-API access,
-- explicit grants only. We're catching up by closing the anon door
-- entirely; explicit grants get re-added in Phase 2 only for the
-- tables that need anon access (none today — even the shop login flow
-- hits server actions, not the Data API directly).

BEGIN;

DO $$
DECLARE
  t record;
  revoked_count int := 0;
BEGIN
  FOR t IN
    SELECT tablename
    FROM pg_tables
    WHERE schemaname = 'public'
    ORDER BY tablename
  LOOP
    EXECUTE format('REVOKE ALL ON TABLE public.%I FROM anon', t.tablename);
    revoked_count := revoked_count + 1;
  END LOOP;
  RAISE NOTICE 'Phase 1 lockdown: revoked all anon grants on % public tables', revoked_count;
END $$;

-- Belt-and-suspenders: also revoke default privileges so any NEW
-- tables created after this migration don't accidentally inherit
-- anon grants from the schema-level default. Future per-table
-- explicit grants (Phase 2) can re-add specific permissions as
-- needed.
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON FUNCTIONS FROM anon;

-- Also revoke schema USAGE so anon can't even list tables. Service
-- role + authenticated keep schema usage (default).
-- NOTE: leave authenticated USAGE intact — server-side auth flows
-- (login, shop public storefront sign-in) need it.
REVOKE USAGE ON SCHEMA public FROM anon;

-- Sanity report — log any remaining anon privileges for review.
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
    RAISE WARNING 'Anon still has privileges on % tables: %', leak_count, leak_list;
  ELSE
    RAISE NOTICE 'Anon has no privileges remaining on any public table — Phase 1 complete.';
  END IF;
END $$;

COMMIT;
