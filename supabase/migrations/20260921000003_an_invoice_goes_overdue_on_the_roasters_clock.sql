-- An invoice went overdue on a clock in Greenwich.
--
-- recompute_overdue_invoices(company) already does the right thing: it reads
-- the company's own facility time zone and compares the due date against
-- THAT calendar, because a due date is a calendar promise and belongs in the
-- calendar the roaster lives in. That part was never wrong.
--
-- The schedule was. It ran once a day at 12:30 UTC, so what a roaster saw
-- depended entirely on where they were:
--
--   Pacific/Honolulu   02:30 local   flips overnight, invisible, correct
--   America/Chicago    07:30 local   before the day starts
--   America/New_York   08:30 local   before the day starts
--   Europe/London      13:30 local   half the working day late
--
-- A UK roastery's invoice became overdue at midnight in its own calendar and
-- went on displaying as open until half past one the following afternoon.
-- Social Hour's Anglesey roastery is on Europe/London, so this was live.
--
-- Hourly instead. The work is already per company and already idempotent: it
-- moves invoices to overdue and back again from the same comparison, so a run
-- that finds nothing to do updates no rows. Every company now turns over
-- within an hour of its own midnight, wherever that falls, and no roaster
-- waits on a clock they have never heard of.
--
-- Deliberately not a config value. There is nothing here for an operator to
-- choose: the correct moment is their own midnight, and hourly is simply how
-- a single job serves every time zone at once.

begin;

-- Guarded on the extension, the shape 20260910000031 already uses. pg_cron is
-- not installed on staging, so this is a no-op there: the reschedule cannot be
-- rehearsed, only the fact that the migration applies cleanly either way.
do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron is not installed here, so there is no schedule to move.';
    return;
  end if;

  -- unschedule then schedule, rather than relying on an upsert, because that
  -- is the shape the other jobs on this database already use.
  perform cron.unschedule(jobid) from cron.job where jobname = 'recompute_overdue_invoices';
  perform cron.schedule(
    'recompute_overdue_invoices',
    '30 * * * *',
    'SELECT public.recompute_overdue_invoices_all()'
  );

  if (select schedule from cron.job where jobname = 'recompute_overdue_invoices') is distinct from '30 * * * *' then
    raise exception 'the overdue job did not move, so somebody in a positive offset still waits all morning';
  end if;
  -- One job, not two: a duplicate would mean two of these racing every hour.
  if (select count(*) from cron.job where jobname = 'recompute_overdue_invoices') <> 1 then
    raise exception 'there is more than one overdue job scheduled';
  end if;

  raise notice 'overdue invoices now recompute hourly, so every company turns over near its own midnight.';
end
$$;

commit;
