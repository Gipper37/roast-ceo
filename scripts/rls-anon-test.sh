#!/usr/bin/env bash
# ============================================================
# Anon surface test
# ============================================================
# What a signed-out visitor -- anyone on the internet with the project's
# publishable key -- can read or write.
#
# This exists because nothing checked it. rls-cross-tenant-test.sh and
# rls-two-tenant-test.sh both bind the `authenticated` role and compare one
# tenant against another; `grep -c anon` is 0 in each. So the anon surface had
# never been in a release check, and shop_config sat readable by the entire
# internet -- all 28 columns of every enabled shop, including company_id,
# facility_id, stripe_connect_account_id and invoice_payment_instructions --
# for five months without a single pass noticing.
#
# The rule this enforces: anon may read ONLY what a signed-out visitor
# genuinely needs, and may write NOTHING.
#
#   ALLOWED_READ  the tables a logged-out page actually renders from.
#                 Adding one here is a decision; the diff should show it.
#
# Failure: anon holding any write grant, anon reading a table not on the list,
# or a policy whose roles include anon or public on a table carrying tenant
# data.
#
# Usage:
#   ./scripts/rls-anon-test.sh prod
#   ./scripts/rls-anon-test.sh staging

set -euo pipefail

ENV=${1:-staging}
PG=/opt/homebrew/Cellar/postgresql@17/17.8/bin/psql
[[ -x "$PG" ]] || PG=psql

case "$ENV" in
  prod)
    REF=${SUPABASE_PROD_REF:-$(security find-generic-password -s 'supabase-prod-ref' -w 2>/dev/null)}
    PW=${SUPABASE_PROD_DB_PASSWORD:-$(security find-generic-password -s 'supabase-prod-db-pw' -w 2>/dev/null)}
    ;;
  staging)
    REF=${SUPABASE_STAGING_REF:-$(security find-generic-password -s 'supabase-staging-ref' -w 2>/dev/null)}
    PW=${SUPABASE_STAGING_DB_PASSWORD:-$(security find-generic-password -s 'supabase-staging-db-pw' -w 2>/dev/null)}
    ;;
  *)
    echo "Usage: $0 [prod|staging]"; exit 2 ;;
esac

if [[ -z "${REF:-}" || -z "${PW:-}" ]]; then
  echo "✗ Missing REF or PW for $ENV"; exit 1
fi

if [[ "$ENV" == staging ]]; then
  URL="postgresql://postgres.${REF}@aws-1-us-west-1.pooler.supabase.com:5432/postgres"
else
  URL="postgresql://postgres@db.${REF}.supabase.co:5432/postgres"
fi

echo "Anon surface test against $ENV ($REF)"
echo "==="

PGPASSWORD="$PW" "$PG" "$URL" -v ON_ERROR_STOP=1 <<'SQL'
DO $$
DECLARE
  r record;
  cnt bigint;
  failures int := 0;
  -- A signed-out visitor renders the pricing page and a customer-category
  -- picker. Nothing else. shop_config came off this list on 2026-10-03: the
  -- storefront is server-rendered on the service role and never read it as
  -- anon.
  allowed_read text[] := ARRAY['customer_category', 'subscription_plans'];
BEGIN
  -- 1. anon must hold no write grant anywhere.
  FOR r IN
    SELECT table_name, privilege_type
      FROM information_schema.role_table_grants
     WHERE table_schema = 'public' AND grantee = 'anon'
       AND privilege_type <> 'SELECT'
     ORDER BY 1, 2
  LOOP
    RAISE WARNING '✗ anon can % on %', r.privilege_type, r.table_name;
    failures := failures + 1;
  END LOOP;

  -- 2. anon may read only the allowed list, and every read is counted so a
  --    table that is allowed but unexpectedly full is still visible here.
  FOR r IN
    SELECT DISTINCT table_name
      FROM information_schema.role_table_grants
     WHERE table_schema = 'public' AND grantee = 'anon' AND privilege_type = 'SELECT'
     ORDER BY 1
  LOOP
    BEGIN
      EXECUTE format('SELECT count(*) FROM public.%I', r.table_name) INTO cnt;
    EXCEPTION WHEN OTHERS THEN
      cnt := -1;
    END;
    IF r.table_name = ANY(allowed_read) THEN
      RAISE NOTICE '  ok   anon reads %  (% rows)', r.table_name, cnt;
    ELSE
      RAISE WARNING '✗ anon can read %, which is not on the allowed list (% rows)', r.table_name, cnt;
      failures := failures + 1;
    END IF;
  END LOOP;

  -- 3. A policy naming anon or public only matters on a table anon can
  --    actually REACH. RLS runs after grants, so `TO public` on a table with no
  --    anon grant is unreachable: 37 such policies exist on prod and flagging
  --    them all is how the one that matters gets lost in the noise. Counted as
  --    a failure only where the grant exists too; reported as a note otherwise,
  --    because the day someone adds a grant they become live.
  FOR r IN
    SELECT p.tablename, p.policyname, p.cmd
      FROM pg_policies p
     WHERE p.schemaname = 'public'
       AND ('anon' = ANY(p.roles) OR 'public' = ANY(p.roles))
       AND NOT (p.tablename = ANY(allowed_read))
       AND EXISTS (
         SELECT 1 FROM information_schema.role_table_grants g
          WHERE g.table_schema = 'public' AND g.grantee = 'anon'
            AND g.table_name = p.tablename)
     ORDER BY 1, 2
  LOOP
    RAISE WARNING '✗ policy %.% (%) is reachable by anon', r.tablename, r.policyname, r.cmd;
    failures := failures + 1;
  END LOOP;

  SELECT count(*) INTO cnt
    FROM pg_policies p
   WHERE p.schemaname = 'public'
     AND ('anon' = ANY(p.roles) OR 'public' = ANY(p.roles))
     AND NOT EXISTS (
       SELECT 1 FROM information_schema.role_table_grants g
        WHERE g.table_schema = 'public' AND g.grantee = 'anon'
          AND g.table_name = p.tablename);
  IF cnt > 0 THEN
    RAISE NOTICE '  note % policy(ies) name anon or public on tables anon holds no grant on. Unreachable today; live the moment a grant is added.', cnt;
  END IF;

  IF failures > 0 THEN
    RAISE EXCEPTION '% anon surface failure(s)', failures;
  END IF;
  RAISE NOTICE '✓ anon can read only % and can write nothing', array_to_string(allowed_read, ', ');
END $$;
SQL
