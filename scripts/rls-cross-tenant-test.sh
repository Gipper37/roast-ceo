#!/usr/bin/env bash
# ============================================================
# Cross-tenant RLS leak test
# ============================================================
# For every public table with RLS enabled — and every public VIEW that
# authenticated may SELECT — query as the `authenticated` role with no
# auth.uid() bound and count rows visible.
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
      (
        EXISTS (
          SELECT 1 FROM pg_policy p
          WHERE p.polrelid = c.oid
            AND p.polcmd IN ('r', '*')
            AND pg_get_expr(p.polqual, c.oid) NOT LIKE '%auth_%'
        )
      ) AS is_catalog,
      -- SHARED DEFAULTS: "(company_id IS NULL OR company_id IN auth_company_ids())".
      -- Global rows everyone may read, plus each tenant's own. The OR'd tenant
      -- clause trips the auth_ heuristic above, so these used to be named in a
      -- hand-kept allowlist — which is both a maintenance tax and too blunt:
      -- allowlisting a table stops it being checked AT ALL, so a genuine tenant
      -- row leaking from one would go unseen. Detect the shape instead, then
      -- count only the rows that would actually be a leak (company_id NOT NULL).
      EXISTS (
        SELECT 1 FROM pg_policy p
        WHERE p.polrelid = c.oid
          AND p.polcmd IN ('r', '*')
          AND pg_get_expr(p.polqual, c.oid) LIKE '%company_id IS NULL%'
          AND pg_get_expr(p.polqual, c.oid) LIKE '%auth_company_ids%'
      ) AS is_shared_default
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind = 'r'
      AND c.relrowsecurity = true
    ORDER BY c.relname
  LOOP
    BEGIN
      IF r.is_shared_default AND NOT r.is_catalog THEN
        -- Only a row that BELONGS to some tenant can be a leak here; the global
        -- rows are visible on purpose. This is stricter than skipping the table.
        EXECUTE format('SELECT count(*) FROM public.%I WHERE company_id IS NOT NULL', r.relname) INTO cnt;
      ELSE
        EXECUTE format('SELECT count(*) FROM public.%I', r.relname) INTO cnt;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'ERROR  %: %', r.relname, SQLERRM;
      err_count := err_count + 1;
      CONTINUE;
    END;

    IF cnt > 0 THEN
      IF r.is_catalog THEN
        catalog_rows := catalog_rows + 1;
        RAISE NOTICE '  catalog  %: % rows (expected, USING true)', r.relname, cnt;
      ELSIF r.is_shared_default THEN
        -- cnt is already tenant-owned-only here, so reaching this branch with
        -- cnt > 0 IS a leak.
        tenant_leaks := tenant_leaks + 1;
        RAISE WARNING '  LEAK     %: % tenant-owned rows visible (shared-defaults table)', r.relname, cnt;
      ELSE
        tenant_leaks := tenant_leaks + 1;
        RAISE WARNING '  LEAK     %: % rows (tenant table should return 0!)', r.relname, cnt;
      END IF;
    END IF;
  END LOOP;

  -- ── Views ──────────────────────────────────────────────────────────────
  -- A view has no policies of its own. With security_invoker it inherits the
  -- RLS of every table underneath it; without it, it runs as its owner
  -- (postgres, BYPASSRLS) and returns every tenant's rows — the class of
  -- leak 20260910000001 closed for 27 views. Classify a view as catalog only
  -- when EVERY base table it reaches (through other views too) is catalog;
  -- otherwise it must return 0 rows to an unscoped authenticated caller.
  FOR r IN
    WITH RECURSIVE base AS (
      SELECT v.oid AS view_oid, t.oid AS rel_oid, t.relkind
        FROM pg_class v
        JOIN pg_namespace n ON n.oid = v.relnamespace AND n.nspname = 'public'
        JOIN pg_rewrite rw ON rw.ev_class = v.oid
        JOIN pg_depend d ON d.objid = rw.oid AND d.classid = 'pg_rewrite'::regclass
                        AND d.refclassid = 'pg_class'::regclass
        JOIN pg_class t ON t.oid = d.refobjid
       WHERE v.relkind = 'v' AND t.oid <> v.oid AND t.relkind IN ('r', 'v', 'm', 'p')
      UNION
      SELECT b.view_oid, t.oid, t.relkind
        FROM base b
        JOIN pg_rewrite rw ON rw.ev_class = b.rel_oid AND b.relkind = 'v'
        JOIN pg_depend d ON d.objid = rw.oid AND d.classid = 'pg_rewrite'::regclass
                        AND d.refclassid = 'pg_class'::regclass
        JOIN pg_class t ON t.oid = d.refobjid
       WHERE t.oid <> b.rel_oid AND t.relkind IN ('r', 'v', 'm', 'p')
    )
    SELECT c.relname,
           bool_and(
             b.relkind IN ('r', 'p') AND EXISTS (
               SELECT 1 FROM pg_policy p
                WHERE p.polrelid = b.rel_oid AND p.polcmd IN ('r', '*')
                  AND pg_get_expr(p.polqual, b.rel_oid) NOT LIKE '%auth_%'
             )
           ) AS is_catalog
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      JOIN base b ON b.view_oid = c.oid
     WHERE n.nspname = 'public' AND c.relkind = 'v'
       AND has_table_privilege('authenticated', c.oid, 'SELECT')
     GROUP BY c.relname
     ORDER BY c.relname
  LOOP
    BEGIN
      EXECUTE format('SELECT count(*) FROM public.%I', r.relname) INTO cnt;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'ERROR  view %: %', r.relname, SQLERRM;
      err_count := err_count + 1;
      CONTINUE;
    END;
    IF cnt > 0 THEN
      IF r.is_catalog THEN
        catalog_rows := catalog_rows + 1;
        RAISE NOTICE '  catalog  view %: % rows (all base tables catalog)', r.relname, cnt;
      ELSE
        tenant_leaks := tenant_leaks + 1;
        RAISE WARNING '  LEAK     view %: % rows (tenant view should return 0!)', r.relname, cnt;
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
