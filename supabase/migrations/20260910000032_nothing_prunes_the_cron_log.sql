-- Nothing prunes cron.job_run_details, so it has been growing since July.
--
-- pg_cron writes one row per run and never deletes any. On prod today that is
-- 427,916 rows / 71 MB, and 94% of it is lot_recompute_drain discovering that
-- its queue is empty. …031 cut that job from four runs a minute to one, which
-- slows the growth; this stops it being unbounded.
--
-- Keeping THIRTY days, not seven. That history is not decoration: the 70-day
-- run log is what made …031 an argument instead of an opinion (399,911 of
-- 403,674 drain runs under 10 ms, 34 that ever did work). Seven days cannot
-- answer a question like "how often does this actually fire".
--
-- The arithmetic, from a 7-day count of the CURRENT job set on prod:
--     lot_recompute_drain   5,753.6 /day  → 1,440 /day after …031
--     seven hourly jobs        24   /day each = 168
--     seven daily jobs          1   /day each =   7
--     lot_anchor_snapshots      0.1 /day  (weekly)
--     this prune job            1   /day
--   ≈ 1,616 rows/day × 30 days ≈ 48,500 rows. At the measured 174 bytes/row
--   that is about 8.4 MB, against 71 MB and climbing now.
--
-- Two things happen here: the standing job, and a one-time delete of the
-- 250,344 rows already past the window (427,916 total − 177,572 inside it).
--
-- ── One predicate, declared once ──────────────────────────────────────────
-- The retention rule is a single text constant. The nightly job runs it, the
-- backlog delete runs it, and the probe asserts that the scheduled command IS
-- it. Written as three separate literals, a typo in the job's copy would have
-- been asserted by nothing: the schedule would still read '25 3 * * *' and the
-- backlog would still be clear, because the one-time delete did that work
-- independently. The job is the half that runs every night forever, so it is
-- the half that has to be pinned.
--
-- ── Why the predicate is end_time and not start_time ──────────────────────
-- A run that is still executing has end_time NULL, so an end_time predicate
-- cannot delete a row out from under a running job. Every row on prod today is
-- 'succeeded' or 'failed' and every one has an end_time; a row that somehow
-- never gets one simply survives, which is the safe direction to fail.
--
-- ── What this does NOT do ─────────────────────────────────────────────────
-- It does not reclaim the 71 MB to the operating system: VACUUM cannot run
-- inside a transaction block and this file is one. Autovacuum reuses the freed
-- pages instead — the file stops growing, it does not shrink. Reclaiming it is
-- a separate deliberate operation, not a migration:
--     VACUUM FULL cron.job_run_details;
-- postgres can do that (it owns this database, and on 17 it also holds MAINTAIN
-- on the table), at the price of an ACCESS EXCLUSIVE lock on the log every cron
-- job writes to. Owner's call, out of band.
--
-- Privileges verified on prod 2026-09-16: postgres has DELETE and
-- rolbypassrls = true, so the extension's `username = CURRENT_USER` RLS policy
-- is not in the way (and all 427,916 rows are username = 'postgres' regardless).

begin;

do $$
declare
  -- The one source of truth. Everything below refers to this.
  v_prune_sql constant text :=
    $q$DELETE FROM cron.job_run_details WHERE end_time < now() - interval '30 days'$q$;
  v_schedule  constant text := '25 3 * * *';   -- 03:25, and cron.timezone is GMT
  v_job       constant text := 'cron_job_run_details_prune';
  v_deleted   bigint;
  v_found     text;
  v_command   text;
  v_stale     bigint;
begin
  -- Everything past here names the cron schema. PL/pgSQL hands an embedded SQL
  -- statement to the parse-analyzer the first time it EXECUTES it, never when
  -- the block is created — so on staging and local, where pg_cron does not
  -- exist, this return is what keeps `cron.*` from ever being resolved. Same
  -- reason the static cron.job references further down are safe.
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron not installed — skipping cron log prune';
    return;
  end if;

  -- Re-schedule idempotently, the shape 20260707000003 already uses on prod.
  perform cron.unschedule(jobid) from cron.job where jobname = v_job;
  perform cron.schedule(v_job, v_schedule, v_prune_sql);

  -- The backlog, through the very statement the job will run every night.
  execute v_prune_sql;
  get diagnostics v_deleted = row_count;
  raise notice 'cron log: deleted % rows past the 30-day window', v_deleted;

  -- ── Prove it, including the part that runs unattended ──
  select schedule, command into v_found, v_command from cron.job where jobname = v_job;
  if v_found is distinct from v_schedule then
    raise exception '% is scheduled "%", expected "%"', v_job, coalesce(v_found, '(missing)'), v_schedule;
  end if;
  if v_command is distinct from v_prune_sql then
    raise exception '% runs "%", expected "%"', v_job, coalesce(v_command, '(missing)'), v_prune_sql;
  end if;

  -- Confirms the backlog statement ran. Weak on its own — it shares this
  -- transaction's now() with the delete above — so it is a second opinion on
  -- the delete, not the proof; the command assertion is the proof.
  execute $q$select count(*) from cron.job_run_details where end_time < now() - interval '30 days'$q$
    into v_stale;
  if v_stale <> 0 then
    raise exception 'cron log still holds % rows older than 30 days', v_stale;
  end if;
end
$$;

commit;
