#!/usr/bin/env bash
# Wrapper around `supabase db push` that REFUSES to apply migrations
# when the migrations directory has uncommitted changes.
#
# Why this exists:
#   For months the workflow was "write migration → supabase db push →
#   maybe commit later." Result: 349 migrations applied to prod that
#   were never in git, no reproducible history, no way to rebuild a
#   fresh DB. This script makes the unwanted path mechanically harder
#   than the right path.
#
# Usage:
#   ./scripts/db-push.sh                   # equivalent to `supabase db push --linked`
#   ./scripts/db-push.sh --include-all     # forwarded to supabase
#   FORCE_DIRTY=1 ./scripts/db-push.sh     # escape hatch (emergencies only)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

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
    echo "  ./scripts/db-push.sh"
    echo ""
    echo "Real emergency? FORCE_DIRTY=1 ./scripts/db-push.sh  (then commit ASAP)"
    exit 1
  fi
fi

SUPABASE="$(brew --prefix 2>/dev/null)/bin/supabase"
if [[ ! -x "$SUPABASE" ]]; then
  SUPABASE="supabase"
fi

echo "→ $SUPABASE db push --linked $*"
exec "$SUPABASE" db push --linked "$@"
