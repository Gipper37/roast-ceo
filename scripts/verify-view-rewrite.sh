#!/usr/bin/env bash
# Prove a view rewrite changes the PLAN and not the ANSWER.
#
# Runs the live view and a candidate definition side by side, per facility, on
# PROD (read-only), and compares a hash of the full sorted result. A rewrite is
# only safe if every facility's hash is identical — "it looked right on Maui" is
# how the Roast Plan / LFP reconcile invariant gets broken quietly.
#
#   ./scripts/verify-view-rewrite.sh <view_name> <candidate.sql>
#
# candidate.sql holds ONLY the SELECT body (what pg_get_viewdef returns). The
# script wraps it, filters it by facility, hashes it, and diffs.
set -euo pipefail

PSQL=${PSQL:-/opt/homebrew/Cellar/postgresql@17/17.8/bin/psql}
DSN=${DSN:-"postgresql://postgres@db.pwpslalerytymorcodlv.supabase.co:5432/postgres"}
export PGPASSWORD=${PGPASSWORD:-'SDH-h3FNHXSrxj-'}

VIEW=${1:?usage: $0 <view_name> <candidate.sql>}
CAND=${2:?usage: $0 <view_name> <candidate.sql>}
[[ -f "$CAND" ]] || { echo "no such file: $CAND" >&2; exit 2; }

# Hash the WHOLE row set, order-independently: every row cast to text, sorted,
# concatenated, md5'd. A single changed digit anywhere moves the hash.
hash_sql() { printf 'select coalesce(md5(string_agg(x, chr(10) order by x)), Q(empty)) , count(*) from (select t::text as x from (%s) t) s;' "$1" | sed "s/Q(empty)/'(empty)'/"; }

FACILITIES=$($PSQL "$DSN" -Atc "select facility_id from public.facilities order by facility_id;")
[[ -n "$FACILITIES" ]] || { echo "no facilities returned" >&2; exit 1; }

fail=0
printf '%-40s %-34s %-34s %s\n' FACILITY LIVE CANDIDATE ROWS
for f in $FACILITIES; do
  live_q="select * from public.$VIEW where facility_id = '$f'"
  # pg_get_viewdef ends with a semicolon; strip it or the subquery will not close.
  body=$(sed -e 's/;[[:space:]]*$//' "$CAND")
  cand_q="select * from ( $body ) v where v.facility_id = '$f'"

  live=$($PSQL "$DSN" -Atc "$(hash_sql "$live_q")" | tr '|' ' ')
  cand=$($PSQL "$DSN" -Atc "$(hash_sql "$cand_q")" | tr '|' ' ')

  lh=${live%% *}; ln=${live##* }
  ch=${cand%% *}; cn=${cand##* }

  if [[ "$lh" == "$ch" && "$ln" == "$cn" ]]; then
    printf '%-40s %-34s %-34s %s  ✓\n' "$f" "${lh:0:32}" "${ch:0:32}" "$ln"
  else
    printf '%-40s %-34s %-34s %s/%s  ✗ MISMATCH\n' "$f" "${lh:0:32}" "${ch:0:32}" "$ln" "$cn"
    fail=1
  fi
done

if [[ $fail -ne 0 ]]; then
  echo
  echo "✗ the candidate does NOT return the same answer — do not ship it"
  exit 1
fi
echo
echo "✓ identical output on every facility"
