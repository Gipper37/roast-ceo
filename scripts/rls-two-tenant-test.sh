#!/usr/bin/env bash
# ============================================================
# Two-tenant RLS smoke test
# ============================================================
# Picks two real auth users from different companies. Impersonates
# each (via request.jwt.claims sub) and queries the same tenant
# tables. Verifies:
#
#   1. User A sees rows that all belong to A's company
#   2. User B sees rows that all belong to B's company
#   3. The row sets do not overlap
#
# Failure means a tenant table is leaking data across companies —
# the worst category of bug.
#
# Usage:
#   ./scripts/rls-two-tenant-test.sh prod
#   ./scripts/rls-two-tenant-test.sh staging

set -euo pipefail

ENV=${1:-prod}
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

URL="postgresql://postgres@db.${REF}.supabase.co:5432/postgres"

echo "Two-tenant RLS smoke test against $ENV"
echo "==="

PGPASSWORD="$PW" "$PG" "$URL" -v ON_ERROR_STOP=1 <<'SQL'
DO $$
DECLARE
  user_a uuid;
  user_b uuid;
  company_a text;
  company_b text;
  a_count int;
  b_count int;
  overlap_count int;
  total_checks int := 0;
  failures int := 0;
  r record;
BEGIN
  -- Pick two users from different companies
  SELECT t.auth_user_id, t.company_id INTO user_a, company_a
  FROM public.team t
  WHERE t.auth_user_id IS NOT NULL
  ORDER BY t.created_at LIMIT 1;

  SELECT t.auth_user_id, t.company_id INTO user_b, company_b
  FROM public.team t
  WHERE t.auth_user_id IS NOT NULL AND t.company_id != company_a
  ORDER BY t.created_at LIMIT 1;

  IF user_a IS NULL OR user_b IS NULL OR company_a = company_b THEN
    RAISE EXCEPTION 'Need at least 2 distinct companies with team users';
  END IF;

  RAISE NOTICE 'User A: % (company %)', user_a, company_a;
  RAISE NOTICE 'User B: % (company %)', user_b, company_b;
  RAISE NOTICE '---';

  -- For each tenant table with a company_id column, count what A
  -- sees vs B sees and verify no overlap.
  FOR r IN
    SELECT c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN information_schema.columns col
      ON col.table_schema = n.nspname AND col.table_name = c.relname
     AND col.column_name = 'company_id'
    WHERE n.nspname = 'public'
      AND c.relkind = 'r'
      AND c.relrowsecurity = true
      AND EXISTS (
        SELECT 1 FROM pg_policy p
        WHERE p.polrelid = c.oid
          AND pg_get_expr(p.polqual, c.oid) LIKE '%auth_company_ids%'
      )
      -- Exclude tables that have an intentional public-read policy
      -- (USING expr doesn't reference any auth_* helper). Examples:
      -- shop_config (USING is_enabled = true) lets anyone read enabled
      -- shops by slug — cross-tenant by design.
      AND NOT EXISTS (
        SELECT 1 FROM pg_policy p
        WHERE p.polrelid = c.oid
          AND p.polcmd IN ('r', '*')
          AND pg_get_expr(p.polqual, c.oid) NOT LIKE '%auth_%'
      )
    ORDER BY c.relname
  LOOP
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims',
      json_build_object('sub', user_a::text)::text, true);
    EXECUTE format(
      'SELECT count(*) FROM public.%I WHERE company_id != %L',
      r.relname, company_a) INTO a_count;

    PERFORM set_config('request.jwt.claims',
      json_build_object('sub', user_b::text)::text, true);
    EXECUTE format(
      'SELECT count(*) FROM public.%I WHERE company_id != %L',
      r.relname, company_b) INTO b_count;

    -- Reset role
    RESET ROLE;

    total_checks := total_checks + 1;
    IF a_count > 0 OR b_count > 0 THEN
      failures := failures + 1;
      RAISE WARNING '  LEAK %: A saw % foreign rows, B saw % foreign rows',
        r.relname, a_count, b_count;
    END IF;
  END LOOP;

  RESET ROLE;
  RAISE NOTICE '---';
  RAISE NOTICE 'Tables checked: %', total_checks;
  RAISE NOTICE 'Cross-tenant leaks: %', failures;

  IF failures > 0 THEN
    RAISE EXCEPTION '✗ % table(s) leak data across tenants', failures;
  ELSE
    RAISE NOTICE '✓ No cross-tenant leaks. User A only sees company % rows; User B only sees company % rows.', company_a, company_b;
  END IF;
END
$$ LANGUAGE plpgsql;
SQL
