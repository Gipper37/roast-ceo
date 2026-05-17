#!/usr/bin/env bash
# ============================================================
# release.sh — tag a release and push it (triggers CI prod deploy)
# ============================================================
#
# CI (db-push-prod.yml) is triggered by `release-*` tags. Tagging
# the current commit + pushing the tag = prod deploy.
#
#   ./scripts/release.sh             # tag = release-YYYY-MM-DD
#   ./scripts/release.sh -m "note"   # adds annotated tag message
#
# Refuses to run on a dirty tree or when main is not up to date
# with origin/main.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Dirty check
if [[ -n "$(git status --porcelain)" ]]; then
  echo "✗ Working tree is dirty. Commit before releasing."
  exit 1
fi

# Branch + sync check
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$BRANCH" != "main" ]]; then
  echo "✗ You're on $BRANCH, not main. Switch to main before releasing."
  exit 1
fi

git fetch origin --quiet
LOCAL=$(git rev-parse main)
REMOTE=$(git rev-parse origin/main)
if [[ "$LOCAL" != "$REMOTE" ]]; then
  echo "✗ Local main ($LOCAL) is not in sync with origin/main ($REMOTE)."
  echo "  Pull or push first."
  exit 1
fi

# Compute tag name
DATE=$(date +%Y-%m-%d)
TAG="release-$DATE"

# If today's tag already exists, suffix with -N
if git rev-parse "$TAG" >/dev/null 2>&1; then
  N=2
  while git rev-parse "${TAG}-${N}" >/dev/null 2>&1; do N=$((N+1)); done
  TAG="${TAG}-${N}"
fi

# Optional message
MSG="Release $DATE"
if [[ "${1:-}" == "-m" && -n "${2:-}" ]]; then
  MSG="$2"
fi

# Show what's being released — commits since last release tag
LAST=$(git tag -l 'release-*' --sort=-creatordate | head -1)
if [[ -n "$LAST" ]]; then
  echo "Commits since $LAST:"
  git log --oneline "$LAST..HEAD" | head -30
else
  echo "Last 20 commits:"
  git log --oneline -20
fi
echo ""
echo -n "Tag $TAG and push? Type 'ship' to confirm: "
read -r CONFIRM
if [[ "$CONFIRM" != "ship" ]]; then
  echo "✗ Cancelled."
  exit 1
fi

git tag -a "$TAG" -m "$MSG"
git push origin "$TAG"

echo ""
echo "✓ $TAG pushed. Watch CI:"
echo "  https://github.com/Gipper37/roast-ceo/actions/workflows/db-push-prod.yml"
