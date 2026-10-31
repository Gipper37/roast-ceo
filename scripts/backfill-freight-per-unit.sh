#!/usr/bin/env bash
# ============================================================
# backfill-freight-per-unit.sh — correct stored freight-per-unit rates
# ============================================================
#
# Migration 20261030000004 stops NEW rows storing a rounded
# shipping_cost_unit. This corrects the ones already stored, and is
# deliberately NOT part of that migration: re-deriving a rate fires the whole
# consumable/order/coffee cascade, which on prod exceeded the 120s
# statement_timeout and rolled the release back (SQLSTATE 57014).
#
# One shipment per transaction, committed as it goes. Interrupt it freely; the
# selection predicate mirrors calculate_shipping_per_unit exactly, so a row
# stops matching the moment it is correct and a re-run picks up what is left.
#
# A shipment whose order re-cost exceeds --timeout is SKIPPED and named at the
# end rather than stopping the run or being silently dropped.
#
#   ./scripts/backfill-freight-per-unit.sh --staging
#   ./scripts/backfill-freight-per-unit.sh --prod
#   ./scripts/backfill-freight-per-unit.sh --prod --timeout 90s
#   ./scripts/backfill-freight-per-unit.sh --prod --dry-run
#
# There is NO default environment. Naming it is the point.

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

TARGET=""; ROWTIMEOUT="30s"; PAUSE=0.3; DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prod|--production) TARGET=prod; shift ;;
    --staging)           TARGET=staging; shift ;;
    --timeout)           ROWTIMEOUT="$2"; shift 2 ;;
    --pause)             PAUSE="$2"; shift 2 ;;
    --dry-run)           DRY=1; shift ;;
    -h|--help)           sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$TARGET" ]] || { echo "✗ Say which database: --staging or --prod. There is no default." >&2; exit 2; }

if [[ "$TARGET" == prod ]]; then
  REF=${SUPABASE_PROD_REF:-$(security find-generic-password -s 'supabase-prod-ref' -w 2>/dev/null || true)}
  PW=${SUPABASE_PROD_DB_PASSWORD:-$(security find-generic-password -s 'supabase-prod-db-pw' -w 2>/dev/null || true)}
  URL="postgresql://postgres@db.${REF}.supabase.co:5432/postgres"
else
  REF=${SUPABASE_STAGING_REF:-$(security find-generic-password -s 'supabase-staging-ref' -w 2>/dev/null || true)}
  PW=${SUPABASE_STAGING_DB_PASSWORD:-$(security find-generic-password -s 'supabase-staging-db-pw' -w 2>/dev/null || true)}
  # Staging's direct host has no A record; the pooler is the reachable route.
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

PRED="shipping_cost is not null
   and shipping_cost_unit is distinct from
       (case when shipment_total_weight_units > 0
             then shipping_cost / shipment_total_weight_units else 0 end)"
REMAINING_SQL="select count(*) from public.shipment_received where $PRED;"
IDS_SQL="select shipment_id from public.shipment_received where $PRED order by shipment_id;"
ERROR_SQL="select coalesce(round(sum(abs(shipping_cost_unit * shipment_total_weight_units - shipping_cost)), 2), 0)
 from public.shipment_received where shipping_cost is not null and shipment_total_weight_units > 0;"

# Without the migration the trigger re-derives the same rounded value and every
# row is a no-op; say so instead of grinding through all of them.
if q "select pg_get_functiondef(p.oid) like '%ROUND%' from pg_proc p
        join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.proname='calculate_shipping_per_unit';" | grep -q '^t$'; then
  echo "  ✗ calculate_shipping_per_unit still ROUNDs here."
  echo "    Apply migration 20261030000004 first, or every row is a no-op."
  exit 1
fi

TODO=$(q "$REMAINING_SQL"); ERR0=$(q "$ERROR_SQL")
echo "  rows to correct  : $TODO"
echo "  freight misstated: \$$ERR0"
echo "  per-row timeout  : $ROWTIMEOUT"
echo ""
[[ "$DRY" == 1 ]] && { echo "  --dry-run: nothing written."; exit 0; }
[[ "$TODO" == 0 ]] && { echo "  ✓ nothing to do."; exit 0; }

# 🔴 NOT mapfile, and NOT an array. macOS ships bash 3.2: `mapfile` does not
# exist (exit 127), and `${#arr[@]}` on an empty array trips `set -u`. A list
# in a file and a counter work in every shell this will ever meet.
IDLIST="$(mktemp)"; trap 'rm -f "$IDLIST" /tmp/bf.err' EXIT
q "$IDS_SQL" > "$IDLIST"
DONE=0; SKIP_N=0; SKIPPED=""
while IFS= read -r SID || [ -n "$SID" ]; do
  [ -z "$SID" ] && continue
  TRY=0
  while :; do
    if "$PSQL" -X -q -v ON_ERROR_STOP=1 -v sid="$SID" -v rowtimeout="$ROWTIMEOUT" \
         -f scripts/backfill-freight-per-unit.sql "$URL" >/dev/null 2>/tmp/bf.err; then
      DONE=$((DONE+1)); printf "  ✓ %-40s (%s/%s)\n" "$SID" "$DONE" "$TODO"; break
    fi
    TRY=$((TRY+1))
    # Contention is worth retrying. A statement timeout is not: it means this
    # shipment's order re-cost genuinely needs longer, and retrying burns the
    # same time again. Tell them apart by the message.
    if grep -qi 'lock_timeout' /tmp/bf.err && [[ $TRY -lt 4 ]]; then
      echo "  … $SID lock contended, retry $TRY"; sleep 3; continue
    fi
    if grep -qi 'statement timeout' /tmp/bf.err; then
      SKIP_N=$((SKIP_N+1)); SKIPPED="$SKIPPED $SID"
      printf "  ⊘ %-40s skipped: order re-cost > %s\n" "$SID" "$ROWTIMEOUT"; break
    fi
    echo "  ✗ $SID failed:"; sed 's/^/      /' /tmp/bf.err; exit 1
  done
  sleep "$PAUSE"
done < "$IDLIST"

LEFT=$(q "$REMAINING_SQL"); ERR1=$(q "$ERROR_SQL")
echo ""
echo "  corrected        : $DONE"
echo "  still to correct : $LEFT"
echo "  freight misstated: \$$ERR0  ->  \$$ERR1"
if [ "$SKIP_N" -gt 0 ]; then
  # 🔴 Never a silent cap. What was dropped gets named.
  echo ""
  echo "  ⊘ $SKIP_N shipment(s) skipped — their order re-cost exceeds $ROWTIMEOUT:"
  for S in $SKIPPED; do echo "      $S"; done
  # Say only what is measured. The cascade below is the SAME code path a
  # freight edit in the app takes, and the `authenticated` role's
  # statement_timeout is 60s -- so a shipment slower than that cannot be
  # edited there. Whether these particular ones cross 60s is a measurement,
  # not an inference: time them before claiming it.
  echo "    The same cascade runs when freight is edited in the app, where"
  echo "    signed-in users get 60s. Time these before claiming they break it."
  exit 2
fi
echo "  ✓ nothing skipped"
