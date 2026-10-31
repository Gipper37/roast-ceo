#!/usr/bin/env bash
# ============================================================
# backfill-freight-per-unit.sh — correct stored freight-per-unit rates
# ============================================================
#
# Migration 20261030000004 stops NEW rows storing a rounded
# shipping_cost_unit. This corrects the ones already stored. It is deliberately
# NOT part of that migration: the work is ~285ms per consumable line (almost
# all of it recost_orders_for_consumable_purchase against ~40k order_details),
# which is ~81s over the rows in scope and exceeded the 120s statement_timeout
# on prod, rolling the whole release back. Worse, it would have held write locks
# across inventory and the order book for two minutes inside one transaction.
#
# So: small batches, each its own committed transaction, resumable, with a lock
# timeout so it yields to real users instead of blocking them.
#
# Run the migration FIRST — without it the trigger re-derives the same rounded
# value and this does nothing (it will tell you so rather than spin).
#
#   ./scripts/backfill-freight-per-unit.sh --staging
#   ./scripts/backfill-freight-per-unit.sh --prod --batch 5
#   ./scripts/backfill-freight-per-unit.sh --prod --dry-run
#
# There is NO default environment. Naming it is the point.

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

TARGET=""; BATCH=5; PAUSE=0.5; DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prod|--production) TARGET=prod; shift ;;
    --staging)           TARGET=staging; shift ;;
    --batch)             BATCH="$2"; shift 2 ;;
    --pause)             PAUSE="$2"; shift 2 ;;
    --dry-run)           DRY=1; shift ;;
    -h|--help)           sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$TARGET" ]]; then
  echo "✗ Say which database: --staging or --prod. There is no default." >&2
  exit 2
fi

if [[ "$TARGET" == prod ]]; then
  REF=${SUPABASE_PROD_REF:-$(security find-generic-password -s 'supabase-prod-ref' -w 2>/dev/null || true)}
  PW=${SUPABASE_PROD_DB_PASSWORD:-$(security find-generic-password -s 'supabase-prod-db-pw' -w 2>/dev/null || true)}
  URL="postgresql://postgres@db.${REF}.supabase.co:5432/postgres"
else
  REF=${SUPABASE_STAGING_REF:-$(security find-generic-password -s 'supabase-staging-ref' -w 2>/dev/null || true)}
  PW=${SUPABASE_STAGING_DB_PASSWORD:-$(security find-generic-password -s 'supabase-staging-db-pw' -w 2>/dev/null || true)}
  # Staging has no IPv4 on the direct host; the pooler is the reachable route.
  URL="postgresql://postgres.${REF}@aws-1-us-west-1.pooler.supabase.com:5432/postgres"
fi
[[ -n "${REF:-}" && -n "${PW:-}" ]] || { echo "✗ missing ref or password for $TARGET" >&2; exit 1; }

PSQL="/opt/homebrew/Cellar/postgresql@17/17.8/bin/psql"
[[ -x "$PSQL" ]] || PSQL=psql
export PGPASSWORD="$PW" PGCONNECT_TIMEOUT=25

# 🔴 READ THE BANNER. The two environments are one word apart.
echo ""
echo "  ================================================================"
echo "   backfill-freight-per-unit   ->   $(tr '[:lower:]' '[:upper:]' <<<"$TARGET")   ($REF)"
echo "  ================================================================"

q() { "$PSQL" -X -q -At "$URL" -c "$1"; }

REMAINING_SQL="select count(*) from public.shipment_received
 where shipping_cost is not null
   and shipping_cost_unit is distinct from
       (case when shipment_total_weight_units > 0
             then shipping_cost / shipment_total_weight_units else 0 end);"
ERROR_SQL="select coalesce(round(sum(abs(shipping_cost_unit * shipment_total_weight_units - shipping_cost)), 2), 0)
 from public.shipment_received where shipping_cost is not null and shipment_total_weight_units > 0;"

# Without the migration the trigger re-derives the same rounded value and every
# batch is a no-op; say so instead of looping forever.
if q "select pg_get_functiondef(p.oid) like '%ROUND%' from pg_proc p
        join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.proname='calculate_shipping_per_unit';" | grep -q '^t$'; then
  echo "  ✗ calculate_shipping_per_unit still ROUNDs on this database."
  echo "    Apply migration 20261030000004 first, or every batch is a no-op."
  exit 1
fi

TODO=$(q "$REMAINING_SQL"); ERR0=$(q "$ERROR_SQL")
echo "  rows to correct : $TODO"
echo "  freight misstated: \$$ERR0"
echo "  batch size      : $BATCH   pause: ${PAUSE}s"
echo ""
if [[ "$DRY" == 1 ]]; then echo "  --dry-run: nothing written."; exit 0; fi
if [[ "$TODO" == 0 ]]; then echo "  ✓ nothing to do."; exit 0; fi

PASS=0
while :; do
  LEFT=$(q "$REMAINING_SQL")
  [[ "$LEFT" == 0 ]] && break
  PASS=$((PASS+1))
  TRY=0
  until "$PSQL" -X -q -v batch="$BATCH" -f scripts/backfill-freight-per-unit.sql "$URL" >/dev/null 2>/tmp/bf.err; do
    TRY=$((TRY+1))
    if grep -qiE 'lock_timeout|canceling statement' /tmp/bf.err && [[ $TRY -lt 4 ]]; then
      echo "  batch $PASS: contended, retry $TRY in 3s"; sleep 3; continue
    fi
    echo "  ✗ batch $PASS failed:"; sed 's/^/    /' /tmp/bf.err; exit 1
  done
  AFTER=$(q "$REMAINING_SQL")
  printf "  batch %-3s %4s -> %-4s remaining\n" "$PASS" "$LEFT" "$AFTER"
  if [[ "$AFTER" == "$LEFT" ]]; then
    echo "  ✗ a batch committed but corrected nothing — stopping rather than spinning."; exit 1
  fi
  sleep "$PAUSE"
done

ERR1=$(q "$ERROR_SQL")
echo ""
echo "  ✓ 0 rows left to correct"
echo "    freight misstated: \$$ERR0  ->  \$$ERR1"
