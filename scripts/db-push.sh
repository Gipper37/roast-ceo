#!/usr/bin/env bash
# ============================================================
# db-push.sh — apply pending migrations to staging (default) or prod
# ============================================================
#
# DEFAULT: staging. Just run `./scripts/db-push.sh` and it pushes to
# the staging project — safe to iterate against.
#
# PROD: pass `--prod` AND type the project ref to confirm. This makes
# accidentally hitting prod meaningfully harder than the right path.
#
# Both modes REFUSE to run on a dirty tree (uncommitted changes under
# supabase/ or schema.sql). The commit-first rule is non-negotiable.
#
# Reads passwords from the macOS keychain entries created during
# secret-setup, with env-var fallbacks for CI.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Parse args
TARGET=staging
EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prod|--production)
      TARGET=prod; shift ;;
    --staging)
      TARGET=staging; shift ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *)
      EXTRA_ARGS+=("$1"); shift ;;
  esac
done

# Dirty-tree check
if [[ "${FORCE_DIRTY:-}" != "1" ]]; then
  DIRTY=$(git status --porcelain supabase/migrations/ supabase/functions/ schema.sql 2>/dev/null || true)
  if [[ -n "$DIRTY" ]]; then
    echo "✗ db-push refused: uncommitted changes under supabase/ or schema.sql"
    echo ""
    echo "$DIRTY"
    echo ""
    echo "Commit the migration first:"
    echo "  git add supabase/migrations/<file>"
    echo "  git commit -m \"<topic>: <what it does>\""
    echo "  ./scripts/db-push.sh                 # → staging (default)"
    echo "  ./scripts/db-push.sh --prod          # → prod (with confirm)"
    echo ""
    echo "Real emergency? FORCE_DIRTY=1 ./scripts/db-push.sh  (then commit ASAP)"
    exit 1
  fi
fi

# Resolve project ref + password from keychain or env
if [[ "$TARGET" == prod ]]; then
  REF=${SUPABASE_PROD_REF:-$(security find-generic-password -s 'supabase-prod-ref' -w 2>/dev/null || true)}
  PW=${SUPABASE_PROD_DB_PASSWORD:-$(security find-generic-password -s 'supabase-prod-db-pw' -w 2>/dev/null || true)}
  ENV_LABEL="PROD (pwpslalerytymorcodlv)"
else
  REF=${SUPABASE_STAGING_REF:-$(security find-generic-password -s 'supabase-staging-ref' -w 2>/dev/null || true)}
  PW=${SUPABASE_STAGING_DB_PASSWORD:-$(security find-generic-password -s 'supabase-staging-db-pw' -w 2>/dev/null || true)}
  ENV_LABEL="staging ($REF)"
fi

if [[ -z "${REF:-}" || -z "${PW:-}" ]]; then
  echo "✗ Missing project ref or password for $TARGET"
  exit 1
fi

# Prod confirmation
if [[ "$TARGET" == prod ]]; then
  echo ""
  echo "⚠️  You are about to push migrations DIRECTLY TO PROD."
  echo "    Project: $REF"
  echo ""
  echo "    The canonical path is: tag a release (release-YYYY-MM-DD)"
  echo "    and let CI apply to prod after staging has been verified."
  echo "    Use this manual path only for emergencies."
  echo ""
  echo -n "    Type the project ref ($REF) to confirm: "
  read -r CONFIRM
  if [[ "$CONFIRM" != "$REF" ]]; then
    echo "✗ Confirmation did not match. Aborting."
    exit 1
  fi
fi

# Link + push
SUPABASE="$(brew --prefix 2>/dev/null)/bin/supabase"
[[ -x "$SUPABASE" ]] || SUPABASE="supabase"

echo "→ linking $ENV_LABEL"
"$SUPABASE" link --project-ref "$REF" --password "$PW" >/dev/null

echo "→ $SUPABASE db push --linked ${EXTRA_ARGS[*]:-}"
exec "$SUPABASE" db push --linked --password "$PW" "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"
