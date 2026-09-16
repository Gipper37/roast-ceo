-- The lot-recompute drainer wakes four times a minute. It does not need to.
--
-- Owner: *"does the pg cron need to be every 15 seconds. isn't that expensive
-- for such a small benefit... seems to me the interval could be much higher"*
--
-- He is right, and prod says so out loud. cron.job_run_details for this job,
-- 2026-07-08 → 2026-09-16 (70 days):
--
--     403,674 runs        avg 3.0 ms      0 failures
--     399,911 under 10 ms   (an empty-queue poll and nothing else)
--       3,730 10–100 ms
--          34 over 100 ms   (the only runs that plausibly drained anything —
--                            about one every other day, worst 2.3 s)
--
-- So 99.99% of the runs exist to discover that the queue is empty. The CPU is
-- not the cost; the cost is a background worker launched every 15 seconds
-- forever, and 5,760 rows a day into cron.job_run_details — which nothing
-- prunes, and which is now 71 MB / 427,724 rows, 94% of it this one job.
--
-- Nothing is lost by waiting a minute. A queue row only appears when a save
-- would have had to replay more than 400 post-count roasts inline, and the
-- work it defers is a background correction of historical allocation, not a
-- number anybody is watching a spinner for. Worst-case staleness goes from
-- 15 s to 60 s on an event that happens roughly every other day.
--
-- The 400 threshold stays. It is a cost switch (don't make a save wait on a
-- long replay), not a health check, and no real tenant is near it: the deepest
-- facility on prod today is 221 post-count roasts (Social Hour Waikapu, last
-- count 2026-08-23); Maui Coffee Roasters sits at 23.
--
-- The drain procedure itself is unchanged — same advisory lock, same per-row
-- COMMIT, same 10 s lock_timeout, same p_max of 10 per run. At one run a
-- minute a burst of queued origins still clears at 10/minute, and the enqueue
-- path is idempotent, so nothing can pile up unnoticed.

begin;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'lot_recompute_drain';
    perform cron.schedule(
      'lot_recompute_drain',
      '* * * * *',
      $cron$CALL public.drain_lot_recompute_queue()$cron$
    );
  else
    raise notice 'pg_cron not installed — skipping lot_recompute_drain schedule';
  end if;
end
$$;

-- Prove it landed on the schedule we asked for, not the one we replaced.
do $probe$
declare v_schedule text;
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron absent — nothing to verify';
    return;
  end if;
  select schedule into v_schedule from cron.job where jobname = 'lot_recompute_drain';
  if v_schedule is distinct from '* * * * *' then
    raise exception 'lot_recompute_drain is scheduled "%", expected "* * * * *"', coalesce(v_schedule, '(missing)');
  end if;
end
$probe$;

commit;
