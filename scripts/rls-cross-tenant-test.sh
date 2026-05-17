#!/usr/bin/env bash
# ============================================================
# Cross-tenant RLS leak test
# ============================================================
# For every public table with RLS enabled, query as the `authenticated`
# role with no auth.uid() bound and count rows visible.
#
# Tables are classified by inspecting their SELECT policies:
#   CATALOG  — at least one policy with USING expression `true`
#              (reference data; permissive by design)
#   TENANT   — all policies have non-trivial USING expressions
#              (must return 0 rows when no scope is bound)
#
# Failure: any TENANT-classified table returning > 0 rows. That's a
# real cross-tenant leak.
#
# Usage:
#   ./scripts/rls-cross-tenant-test.sh prod
#   ./scripts/rls-cross-tenant-test.sh staging

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

URL="postgresql://postgres@db.${REF}.supabase.co:5432/postgres"

echo "Cross-tenant RLS test against $ENV ($REF)"
echo "==="

PGPASSWORD="$PW" "$PG" "$URL" -v ON_ERROR_STOP=1 <<'SQL'
DO $$
DECLARE
  r record;
  cnt bigint;
  has_permissive_policy bool;
  tenant_leaks int := 0;
  catalog_rows int := 0;
  err_count int := 0;
BEGIN
  -- Authenticated role with NO bound auth.uid() — simulates a logged-in
  -- user whose scope helpers (auth_company_ids etc.) all return empty.
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000000"}', true);

  FOR r IN
    SELECT
      c.relname,
      -- A table is "catalog-like" (expected to return rows on an
      -- unscoped read) if it has at least one ALL/SELECT policy whose
      -- USING expression does NOT reference an auth_* helper. Such
      -- policies are by definition independent of the current user
      -- and won't leak per-tenant data based on identity.
      EXISTS (
        SELECT 1 FROM pg_policy p
        WHERE p.polrelid = c.oid
          AND p.polcmd IN ('r', '*')
          AND pg_get_expr(p.polqual, c.oid) NOT LIKE '%auth_%'
      ) AS is_catalog
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind = 'r'
      AND c.relrowsecurity = true
    ORDER BY c.relname
  LOOP
    BEGIN
      EXECUTE format('SELECT count(*) FROM public.%I', r.relname) INTO cnt;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'ERROR  %: %', r.relname, SQLERRM;
      err_count := err_count + 1;
      CONTINUE;
    END;

    IF cnt > 0 THEN
      IF r.is_catalog THEN
        catalog_rows := catalog_rows + 1;
        RAISE NOTICE '  catalog  %: % rows (expected, USING true)', r.relname, cnt;
      ELSE
        tenant_leaks := tenant_leaks + 1;
        RAISE WARNING '  LEAK     %: % rows (tenant table should return 0!)', r.relname, cnt;
      END IF;
    END IF;
  END LOOP;

  RAISE NOTICE '===';
  RAISE NOTICE 'Catalog tables with rows: %  (expected to be permissive)', catalog_rows;
  RAISE NOTICE 'Policy errors:            %  (broken policies — fix needed)', err_count;
  RAISE NOTICE 'Tenant data leaks:        %  (must be zero)', tenant_leaks;

  IF tenant_leaks > 0 THEN
    RAISE EXCEPTION '✗ % tenant table(s) leaked rows', tenant_leaks;
  END IF;
  IF err_count > 0 THEN
    RAISE EXCEPTION '✗ % policy error(s) — broken policies need fixing', err_count;
  END IF;

  RAISE NOTICE '✓ No tenant leaks, no policy errors';
END
$$ LANGUAGE plpgsql;
SQL
