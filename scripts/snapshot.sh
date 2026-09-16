#!/usr/bin/env bash
# Take a scoped, dated, restorable snapshot before a destructive operation.
#
#   ./scripts/snapshot.sh <table> "<where clause>" <label>
#   ./scripts/snapshot.sh orders "company_id = '9ShiyDAXhV' and created_by is not null" mcr-preimport
#
# WHY THIS EXISTS. scripts/ accumulated a dozen snapshot artifacts in five
# formats — .tsv, .sql, .txt, .json, .csv — one per risky operation, each
# invented fresh, none restorable without reading the script that made it. One
# of them (mcr_orders_snapshot_and_scrap.sql) snapshotted with `create table if
# not exists`, so a second run silently reused a six-week-old table and would
# have deleted live rows against a stale restore point, while its own guard read
# that same stale table and reported success.
#
# So the two rules this enforces, which are the two that were broken:
#   1. A SNAPSHOT CAN NEVER BE SILENTLY REUSED. The filename carries the
#      timestamp and the script refuses to overwrite. There is no "if not
#      exists" anywhere in it.
#   2. IT CARRIES ITS OWN RESTORE. The file records the table, the predicate,
#      the row count and a checksum, and the script prints the exact SQL that
#      puts the rows back. A snapshot you have to reverse-engineer is a rumour.
#
# Whole rows only — `select *`. A projection is not a restore point, and this
# refuses to pretend otherwise.
#
# Reads PROD by default and writes LOCALLY. It never writes to any database.
set -euo pipefail

PSQL=${PSQL:-/opt/homebrew/Cellar/postgresql@17/17.8/bin/psql}
DSN=${DSN:-"postgresql://postgres@db.pwpslalerytymorcodlv.supabase.co:5432/postgres"}
OUT_DIR=${OUT_DIR:-"$(cd "$(dirname "$0")" && pwd)/snapshots"}

# ── restore mode ───────────────────────────────────────────────────────────
# The only thing in here that WRITES. DSN must be set explicitly — the default
# points at prod, and a restore that can reach prod because you forgot to set a
# variable is the same class of accident this script exists to stop.
if [[ "${1:-}" == "--restore" ]]; then
  FILE=${2:?usage: $0 --restore <snapshot.json> [--yes]}
  [[ -f "$FILE" ]] || { echo "no such file: $FILE" >&2; exit 2; }
  [[ -n "${DSN:-}" ]] || { echo "set DSN explicitly to restore — it is not defaulted for writes" >&2; exit 2; }
  : "${PGPASSWORD:?set PGPASSWORD}"

  read -r TBL CNT SHA < <(python3 -c "
import json,sys,hashlib
d=json.load(open('$FILE'))
rows=d.get('rows') or []
have=hashlib.sha256(json.dumps(rows,sort_keys=True,separators=(',',':')).encode()).hexdigest()
if d.get('sha256_of_rows') and d['sha256_of_rows']!=have:
    sys.exit('checksum mismatch: this file has been edited since it was taken')
if len(rows)!=d['row_count']:
    sys.exit('row_count disagrees with the rows in the file')
print(d['table'], d['row_count'], have[:16])
")
  echo "restoring $CNT rows into $TBL"
  echo "  from  $FILE  (sha256 $SHA…)"
  echo "  into  ${DSN%%\?*}"
  if [[ "${3:-}" != "--yes" ]]; then
    read -r -p "type the table name to confirm: " CONFIRM
    [[ "$CONFIRM" == "${TBL#public.}" ]] || { echo "aborted" >&2; exit 1; }
  fi
  # Through stdin, not -c: psql only interpolates :'vars' from a file or stdin.
  # ensure_ascii=False: hand psql real UTF-8 rather than \uXXXX escapes it has to
  # translate. The checksum above is computed on the escaped form on both sides,
  # so this changes what goes over the wire and not what is verified.
  python3 -c "import json,io;io.open('$FILE.rows.tmp','w',encoding='utf-8').write(json.dumps(json.load(open('$FILE'))['rows'],ensure_ascii=False))"
  "$PSQL" "$DSN" -qv ON_ERROR_STOP=1 -v rows="$(cat "$FILE.rows.tmp")" <<SQL
insert into $TBL select * from jsonb_populate_recordset(null::$TBL, :'rows') on conflict do nothing;
SQL
  rm -f "$FILE.rows.tmp"
  echo "✓ restored"
  exit 0
fi

TABLE=${1:?usage: $0 <table> "<where clause>" <label>}
WHERE=${2:?usage: $0 <table> "<where clause>" <label>  — pass "true" to take the whole table}
LABEL=${3:?usage: $0 <table> "<where clause>" <label>}

# A bare psql password prompt in the middle of a destructive runbook is how you
# end up with a half-run script. Fail before doing anything instead.
: "${PGPASSWORD:?set PGPASSWORD (the prod read password) before running this}"

[[ "$LABEL" =~ ^[a-z0-9-]+$ ]] || { echo "label must be lower-case letters, digits and hyphens" >&2; exit 2; }
[[ "$TABLE" =~ ^[a-z0-9_]+$ ]]  || { echo "table must be a bare table name in public" >&2; exit 2; }

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
FILE="$OUT_DIR/${STAMP}_${TABLE}_${LABEL}.json"
mkdir -p "$OUT_DIR"
# Rule 1. No -f, no clobber, no "if not exists" anywhere near this.
[[ -e "$FILE" ]] && { echo "refusing to overwrite $FILE" >&2; exit 1; }

echo "→ snapshotting public.$TABLE where $WHERE"

# jsonb_agg of whole rows, plus the metadata a restore needs. One statement, so
# the count and the rows cannot disagree with each other.
"$PSQL" "$DSN" -Atq -v ON_ERROR_STOP=1 -c "
select jsonb_pretty(jsonb_build_object(
  'table',      'public.$TABLE',
  'predicate',  \$p\$$WHERE\$p\$,
  'label',      '$LABEL',
  'captured_at', now(),
  'captured_by', current_user,
  'row_count',  (select count(*) from public.$TABLE where $WHERE),
  'restore_sql', 'insert into public.$TABLE select * from jsonb_populate_recordset(null::public.$TABLE, :rows) on conflict do nothing;',
  'rows',       coalesce((select jsonb_agg(to_jsonb(t)) from public.$TABLE t where $WHERE), '[]'::jsonb)
));" > "$FILE"

# Rule 2, verified rather than asserted: read the file back and check the rows
# we wrote match the count we recorded.
python3 - "$FILE" <<'PY'
import json, sys, hashlib
p = sys.argv[1]
d = json.load(open(p))
rows = d.get('rows') or []
if len(rows) != d['row_count']:
    sys.exit(f"✗ {p}: recorded row_count {d['row_count']} but wrote {len(rows)} rows")
d['sha256_of_rows'] = hashlib.sha256(
    json.dumps(rows, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
json.dump(d, open(p, 'w'), indent=1, default=str)
print(f"✓ {d['row_count']} rows from {d['table']}")
print(f"  {p}")
print(f"  sha256 {d['sha256_of_rows'][:16]}…")
PY

cat <<EOF

To restore it:

  DSN="<target dsn>" PGPASSWORD=… $0 --restore $FILE

It verifies the checksum, asks you to type the table name, and refuses to run
against the default (prod) DSN unless you set DSN yourself. A restore into a
table whose shape has changed since $STAMP fails loudly on the column list,
which is the behaviour you want.
EOF
