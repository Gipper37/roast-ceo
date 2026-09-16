#!/usr/bin/env bash
# Rehearse a pg_cron migration before it ever runs on prod.
#
# WHY. Staging and local have no pg_cron, so every migration that touches
# cron.schedule sits behind `if exists (select 1 from pg_extension ...)` and its
# real branch is NEVER executed until prod runs it for the first time — inside a
# release tag, where a raise aborts the whole tag. `supabase db push` to staging
# proves only that the guard works.
#
# WHAT THIS DOES. Spins up a throwaway PostgreSQL cluster under /tmp, fakes the
# pg_extension row the guard looks for, hand-builds the slice of pg_cron a
# migration actually touches (cron.job, cron.job_run_details, cron.schedule,
# cron.unschedule), seeds a plausible run log, and runs the file(s) you name.
# Nothing is scheduled — the stubs only record what was asked for, which is
# exactly what a probe should be asserting.
#
#   ./scripts/rehearse-cron-migration.sh supabase/migrations/2026*_my_cron_change.sql
#
# Exit 0 means the cron branch ran and every probe passed. The cluster is torn
# down on the way out, pass or fail.
set -euo pipefail

PGBIN="${PGBIN:-/opt/homebrew/Cellar/postgresql@17/17.8/bin}"
PORT="${PORT:-55432}"
DATA="$(mktemp -d /tmp/ccpg-rehearse.XXXXXX)"
DSN="postgresql://postgres@127.0.0.1:${PORT}/rehearse"

cleanup() {
  "$PGBIN/pg_ctl" -D "$DATA/data" stop -m immediate >/dev/null 2>&1 || true
  rm -rf "$DATA"
}
trap cleanup EXIT

[[ $# -gt 0 ]] || { echo "usage: $0 <migration.sql> [more.sql ...]" >&2; exit 2; }

# LC_ALL=C: without it the postmaster "became multithreaded during startup" on
# macOS and refuses to start. -k in $DATA would exceed the 103-byte socket path
# limit, so this listens on loopback instead.
LC_ALL=C "$PGBIN/initdb" -D "$DATA/data" -U postgres -A trust >/dev/null
LC_ALL=C "$PGBIN/pg_ctl" -D "$DATA/data" \
  -o "-p $PORT -k $DATA -c listen_addresses=127.0.0.1" -l "$DATA/log" start >/dev/null
"$PGBIN/psql" "postgresql://postgres@127.0.0.1:${PORT}/postgres" -qAtc "create database rehearse;" >/dev/null

"$PGBIN/psql" "$DSN" -qv ON_ERROR_STOP=1 >/dev/null <<'SQL'
-- The guard's whole question is "is there a row in pg_extension". Answer it
-- directly rather than installing a stub .control file into the PostgreSQL
-- share directory, which is a shared install nobody should be writing to.
set allow_system_table_mods = on;
insert into pg_extension (oid, extname, extowner, extnamespace, extrelocatable, extversion)
values (99999, 'pg_cron', 10, 11, false, '1.0');
reset allow_system_table_mods;

create schema cron;

create table cron.job (
  jobid    bigserial primary key,
  schedule text not null,
  command  text not null,
  nodename text not null default 'localhost',
  nodeport int  not null default 5432,
  database text not null default current_database(),
  username text not null default current_user,
  active   boolean not null default true,
  jobname  text
);
create unique index on cron.job (jobname, username);

create table cron.job_run_details (
  jobid          bigint,
  runid          bigserial primary key,
  job_pid        int,
  database       text,
  username       text,
  command        text,
  status         text,
  return_message text,
  start_time     timestamptz,
  end_time       timestamptz
);

create function cron.schedule(job_name text, schedule text, command text) returns bigint
language plpgsql as $f$
declare v_id bigint;
begin
  insert into cron.job (schedule, command, jobname) values (schedule, command, job_name)
  on conflict (jobname, username) do update
    set schedule = excluded.schedule, command = excluded.command
  returning jobid into v_id;
  return v_id;
end $f$;

create function cron.unschedule(job_id bigint) returns boolean
language plpgsql as $f$
begin
  delete from cron.job where jobid = job_id;
  return found;
end $f$;

-- A job already on the old schedule, so a re-schedule has something to replace.
insert into cron.job (schedule, command, jobname)
values ('15 seconds', 'CALL public.drain_lot_recompute_queue()', 'lot_recompute_drain');

-- 90 days of finished runs, plus ONE still in flight (end_time null). A prune
-- that deletes the in-flight row is deleting a row out from under a live job.
insert into cron.job_run_details (jobid, database, username, command, status, start_time, end_time)
select 1, current_database(), current_user, 'x', 'succeeded',
       now() - (g || ' days')::interval,
       now() - (g || ' days')::interval + interval '3 ms'
  from generate_series(1, 90) g;
insert into cron.job_run_details (jobid, database, username, command, status, start_time, end_time)
values (1, current_database(), current_user, 'in flight', 'running', now(), null);
SQL

echo "── rehearsing on a stubbed pg_cron ──"
for f in "$@"; do
  echo "── $(basename "$f")"
  "$PGBIN/psql" "$DSN" -v ON_ERROR_STOP=1 -f "$f" 2>&1 | sed 's/^/   /'
  rc=${PIPESTATUS[0]}
  if [[ $rc -ne 0 ]]; then echo "   ✗ FAILED (exit $rc)"; exit "$rc"; fi
  echo "   ✓ applied"
done

echo "── cron.job after ──"
"$PGBIN/psql" "$DSN" -c "select jobname, schedule, command from cron.job order by jobname;"
echo "── run log after (an in-flight row must survive any prune) ──"
"$PGBIN/psql" "$DSN" -c "select count(*) as total, count(*) filter (where end_time is null) as inflight from cron.job_run_details;"
