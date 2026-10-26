-- The stored plan reconciles itself.
--
-- 20261026000013 gave the plan two ways to notice it is stale:
--   1. a write fires one of 13 triggers, which enqueues the company; the drain recomputes it
--   2. the week rolls over, and the drain's week sweep catches it with no write at all
--
-- Both only look FORWARD. Neither repairs a plan that is ALREADY wrong, and today proved that
-- is not hypothetical. The table sat on production for 118 minutes between 000012 (which
-- created and backfilled it) and 000013 (which added the triggers). In that window real writes
-- landed with nothing watching, and the plan drifted:
--
--     facility cc844abb...   47 disagreements
--     facility 5cc581b9...   33 disagreements
--
-- After 000013 landed, those numbers DID NOT MOVE for three consecutive drain passes. The
-- queue was empty, so the drain had nothing to do; the week had not rolled, so the week sweep
-- did nothing. The rows were wrong, every mechanism reported itself healthy, and the only
-- thing that would ever have fixed them was an unrelated write to the same company -- which
-- might be days away, or never for a quiet facility. A hand-run recompute cleared all four to
-- zero, and that is exactly the repair this migration automates.
--
-- 🔴 The failure mode this closes is the dangerous one: not "the plan is slow" or "the plan
-- errors", but "the plan is confidently wrong and nothing says so". A trigger that is missing,
-- an input nobody thought of, a migration window like today's -- all of them look identical
-- from the outside, which is to say they look fine.
--
-- So: every hour, compare each facility's stored plan against the live computation and
-- recompute the ones that disagree. The comparison is roast_plan_verify(), already shipped in
-- 000012 and already the oracle used to prove the backfill.
--
-- Cost: verify runs the same 13-CTE body the view runs, ~650-830ms per facility. Four
-- facilities on production is under 4 seconds an hour, against the 147 HOURS A DAY the view
-- currently burns being read 680,000 times. This is not a cost worth optimising.
--
-- Drift is RECORDED, not just repaired. A repair that leaves no trace turns a missing trigger
-- into a permanent silent tax: the reconcile quietly fixes it every hour and nobody ever
-- learns the trigger is missing. roast_plan_drift is written ONLY when disagreements are
-- found, so an empty table is the healthy state and any row in it is a bug worth chasing.

begin;

create table if not exists public.roast_plan_drift (
  id             bigserial primary key,
  facility_id    text        not null,
  detected_at    timestamptz not null default now(),
  disagreements  int         not null,
  plan_age_s     int,
  repaired       boolean     not null default false
);

comment on table public.roast_plan_drift is
  'Written only when the hourly reconcile finds the stored roast_plan disagreeing with the live computation. An empty table is the healthy state; any row means an input changed the plan without firing an invalidation trigger.';

create index if not exists idx_roast_plan_drift_detected
  on public.roast_plan_drift (detected_at desc);

-- Nobody in the app needs this; it is an operator diagnostic.
revoke all on table public.roast_plan_drift from anon, authenticated;
revoke all on sequence public.roast_plan_drift_id_seq from anon, authenticated;

create or replace function public.roast_plan_reconcile()
returns int
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  r        record;
  v_bad    int;
  v_age    int;
  v_fixed  int := 0;
begin
  for r in select distinct facility_id from public.roast_plan
  loop
    select count(*) into v_bad from public.roast_plan_verify(r.facility_id);

    if v_bad > 0 then
      select round(extract(epoch from (now() - max(computed_at))))::int
        into v_age
        from public.roast_plan
       where facility_id = r.facility_id;

      insert into public.roast_plan_drift (facility_id, disagreements, plan_age_s, repaired)
      values (r.facility_id, v_bad, v_age, true);

      perform public.roast_plan_recompute(r.facility_id);
      v_fixed := v_fixed + 1;
    end if;
  end loop;

  return v_fixed;
end;
$function$;

revoke all on function public.roast_plan_reconcile() from public, anon, authenticated;
grant execute on function public.roast_plan_reconcile() to service_role;

-- Hourly, at :35 -- deliberately off the :00/:05/:10/:15 cluster where
-- refresh_weekly_coffee_stock, refresh_monthly_consumable_stock, apply_due_price_log and
-- equipment_usage_recompute already stack on the same minute.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    -- EXECUTE, not a bare statement: plpgsql plans the whole block before it branches, so a
    -- direct reference to cron.job fails to PARSE where pg_cron is absent (staging), even
    -- though the guard above is false. 000013 hit exactly this.
    execute $q$
      select cron.unschedule(jobid) from cron.job where jobname = 'roast_plan_reconcile';
    $q$;
    execute $q$
      select cron.schedule('roast_plan_reconcile', '35 * * * *',
                           $cron$SELECT public.roast_plan_reconcile()$cron$)
    $q$;
  else
    raise notice 'pg_cron not installed -- skipping roast_plan_reconcile schedule';
  end if;
end $$;

do $$
declare
  v_fixed int;
  v_bad   int;
begin
  if to_regprocedure('public.roast_plan_reconcile()') is null then
    raise exception 'roast_plan_reconcile() is missing';
  end if;

  -- Run it for real. It must leave every facility in agreement, whatever state it started in.
  v_fixed := public.roast_plan_reconcile();
  raise notice 'reconcile repaired % facility(ies)', v_fixed;

  select coalesce(sum(c), 0) into v_bad from (
    select (select count(*) from public.roast_plan_verify(f.facility_id)) as c
      from (select distinct facility_id from public.roast_plan) f
  ) x;
  if v_bad <> 0 then
    raise exception 'reconcile ran but % disagreement(s) remain', v_bad;
  end if;

  -- This block can both pass and fail: it asserts the END STATE (zero disagreements), which
  -- is true whether or not there was drift to repair. It does not assert that drift existed.
  raise notice 'every facility agrees with the live computation';
end $$;

commit;
