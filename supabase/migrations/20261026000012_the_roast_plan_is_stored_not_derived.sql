-- The roast plan is STORED, not derived on every read.
--
-- Measured on prod 2026-10-26: `roast_detail_by_blend` is 60.6% OF ALL DATABASE
-- TIME -- 147.6 hours over 680,082 calls -- to produce 142 rows across 4
-- facilities. Its inputs change roughly 200 times a day, so the same answer was
-- recomputed about 680 times per actual change, at ~1,058ms each, on an instance
-- with max_parallel_workers = 2. Nothing was I/O bound (cache hit 99.99%, the
-- whole database is 840MB); it was pure CPU deriving a tiny answer over and over.
-- That is what saturated production during a roasting shift.
--
-- This migration adds the storage, the recompute, the dirty queue, the drain and
-- the comparison gate. IT CHANGES NO READ PATH: nothing selects from the new
-- table yet, and `roast_detail_by_blend` is untouched. Cutover is a later,
-- separate change, gated on roast_plan_verify() reporting zero mismatches.
--
-- 🔴 THE RECOMPUTE CALLS THE EXISTING FUNCTION. The table caches the output of
-- roast_detail_by_blend(facility); it does not reimplement those 445 lines.
-- There is still exactly one copy of the logic, so the stored answer cannot
-- drift from the derived one, and the comparison below is honest rather than two
-- implementations agreeing by luck.
--
-- 🔴 INVALIDATION IS PER FACILITY, NOT PER RECIPE. A facility holds ~35 recipes
-- and one call refreshes all of them, so there is no grain to get wrong. The
-- failure this avoids is the one this project keeps hitting: demand reaches a
-- recipe through recipe_demand_source (parent/child at a share, containers at
-- share 0), so "which recipes does this change touch" has repeatedly been
-- answered wrongly. Refreshing the whole facility makes the question moot.
--
-- 🔴 STALENESS IS SELF-DETECTING. Every time-dependent term in the function is
-- relative to roast_week_start / orders_week_start / anchor_date, and those are
-- derived from CURRENT_TIMESTAMP at the facility's timezone (function body line
-- 51). They are CONSTANT between week boundaries. Each row therefore stores the
-- week it was computed under, and a row whose stored week is not the current
-- week is stale by definition -- no clock job to forget.

begin;

-- ── the stored plan ──────────────────────────────────────────────────────────
create table if not exists public.roast_plan (
  facility_id            text    not null,
  recipe_id              text    not null,
  roast_blend_id         text,
  company_id             text    not null,
  in_stock_roasted       numeric,
  total_ordered          double precision,
  total_roasted          numeric,
  roasted_left           double precision,
  roasts_remaining       double precision,
  avg_weekly_lbs         numeric,
  backstock_buffer_pct   numeric,
  buffer_target          numeric,
  effective_target       double precision,
  buffer_left            double precision,
  weekly_target_override numeric,
  -- The week this row was computed under. Not decoration: it is the staleness
  -- test, because the plan's windows move only when these move.
  roast_week_start       date    not null,
  orders_week_start      date    not null,
  computed_at            timestamptz not null default now(),
  primary key (facility_id, recipe_id)
);

comment on table public.roast_plan is
  'Stored output of roast_detail_by_blend(facility). Maintained by '
  'roast_plan_recompute via the roast_plan_dirty queue; never hand-edited. '
  'Verify against the function with roast_plan_verify().';

-- company_id leads the index because every read is tenant-scoped by RLS first.
create index if not exists idx_roast_plan_company on public.roast_plan (company_id);
-- Finds rows whose stored week has rolled over, without a scan per facility.
create index if not exists idx_roast_plan_week on public.roast_plan (facility_id, roast_week_start, orders_week_start);

alter table public.roast_plan enable row level security;

-- Read follows the same rule as roast_log_read, the table this plan is computed
-- from, so the plan can never be visible where its inputs are not.
drop policy if exists roast_plan_read on public.roast_plan;
create policy roast_plan_read on public.roast_plan
  for select using (company_id in (select public.auth_company_ids()));

-- No write policy on purpose: every write goes through roast_plan_recompute,
-- which is SECURITY DEFINER. A client with a session cannot insert a plan row,
-- so a forged plan is not reachable over PostgREST.
revoke all on table public.roast_plan from anon;
grant select on table public.roast_plan to authenticated;

-- ── the dirty queue ──────────────────────────────────────────────────────────
-- facility_id is the PRIMARY KEY, so `on conflict do nothing` collapses a burst
-- of writes during a roasting shift into one pending recompute. The enqueue a
-- trigger performs must stay in microseconds: roast_log already carries 12
-- triggers and charging a roast already holds locks for ~17 seconds, so nothing
-- expensive may join that write.
create table if not exists public.roast_plan_dirty (
  facility_id text primary key,
  enqueued_at timestamptz not null default now(),
  reason      text
);

comment on table public.roast_plan_dirty is
  'Facilities whose stored roast_plan needs recomputing. One row per facility; '
  'enqueue with on conflict do nothing. Drained by roast_plan_drain().';

alter table public.roast_plan_dirty enable row level security;
revoke all on table public.roast_plan_dirty from anon, authenticated;

-- ── the week starts, as a conservative staleness probe ───────────────────────
-- The same expression the function uses at its line 51. It is duplicated here
-- deliberately and it is NOT the source of truth: it only decides whether to
-- recompute, so any disagreement with the function costs one extra recompute
-- and can never serve a stale answer. The alternative was rewriting the
-- function body to call this, and retyping a 445-line body to save two lines is
-- how bodies get silently truncated.
create or replace function public.facility_week_starts(p_facility_id text)
returns table (roast_week_start date, orders_week_start date)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with fp as (
    select
      coalesce(nullif(f.time_zone, ''::text), 'Pacific/Honolulu'::text) as timezone,
      coalesce((select cp.value_number::integer from company_parameters cp
                 where cp.parameter_id = 'RF1iFWjOh7' and cp.facility_id = f.facility_id
                 limit 1), 4) as roast_reset_day,
      coalesce((select cp.value_number::integer from company_parameters cp
                 where cp.parameter_id = 'orders_reset_day' and cp.facility_id = f.facility_id
                 limit 1),
               (select sp.amount::integer from standard_parameters sp
                 where sp.parameters_id = 'orders_reset_day' limit 1), 6) as orders_reset_day
    from facilities f
    where f.facility_id = p_facility_id
  )
  select
    (current_timestamp at time zone fp.timezone)::date
      - (extract(dow from (current_timestamp at time zone fp.timezone)::date)::integer - fp.roast_reset_day + 7) % 7,
    (current_timestamp at time zone fp.timezone)::date
      - (extract(dow from (current_timestamp at time zone fp.timezone)::date)::integer - fp.orders_reset_day + 7) % 7
  from fp;
$function$;

-- ── the recompute ────────────────────────────────────────────────────────────
create or replace function public.roast_plan_recompute(p_facility_id text)
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_rows int;
  v_roast  date;
  v_orders date;
begin
  select w.roast_week_start, w.orders_week_start
    into v_roast, v_orders
    from public.facility_week_starts(p_facility_id) w;

  if v_roast is null then
    -- No such facility, or it has no timezone row. Leave whatever is stored
    -- rather than emptying the plan on a lookup miss.
    return 0;
  end if;

  -- Delete-then-insert, not an upsert: a recipe that has been archived or
  -- re-pointed must LEAVE the plan, and an upsert would strand its old row
  -- forever. Readers inside this transaction still see the previous rows until
  -- it commits, so the plan is never briefly empty for anyone.
  delete from public.roast_plan where facility_id = p_facility_id;

  insert into public.roast_plan (
    facility_id, recipe_id, roast_blend_id, company_id,
    in_stock_roasted, total_ordered, total_roasted, roasted_left,
    roasts_remaining, avg_weekly_lbs, backstock_buffer_pct, buffer_target,
    effective_target, buffer_left, weekly_target_override,
    roast_week_start, orders_week_start, computed_at
  )
  select
    r.facility_id, r.recipe_id, r.roast_blend_id, r.company_id,
    r.in_stock_roasted, r.total_ordered, r.total_roasted, r.roasted_left,
    r.roasts_remaining, r.avg_weekly_lbs, r.backstock_buffer_pct, r.buffer_target,
    r.effective_target, r.buffer_left, r.weekly_target_override,
    v_roast, v_orders, now()
  from public.roast_detail_by_blend(p_facility_id) r
  where r.company_id is not null;

  get diagnostics v_rows = row_count;

  delete from public.roast_plan_dirty where facility_id = p_facility_id;

  return v_rows;
end;
$function$;

comment on function public.roast_plan_recompute(text) is
  'Refresh one facility''s stored plan from roast_detail_by_blend(). Returns the '
  'row count. Clears that facility from roast_plan_dirty.';

-- ── the enqueue, for triggers to call ────────────────────────────────────────
create or replace function public.roast_plan_mark_dirty(p_facility_id text, p_reason text default null)
returns void
language sql
security definer
set search_path to 'public', 'pg_temp'
as $function$
  insert into public.roast_plan_dirty (facility_id, reason)
  select p_facility_id, p_reason
  where p_facility_id is not null
  on conflict (facility_id) do nothing;
$function$;

-- ── the drain ────────────────────────────────────────────────────────────────
create or replace function public.roast_plan_drain(p_limit integer default 10)
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_fac  text;
  v_done int := 0;
begin
  -- FOR UPDATE SKIP LOCKED so two drains never recompute the same facility and
  -- neither waits on the other. p_limit bounds the work per invocation: an
  -- unbounded drain is how a queue turns one slow pass into a stall.
  for v_fac in
    select d.facility_id
      from public.roast_plan_dirty d
     order by d.enqueued_at
     limit p_limit
     for update skip locked
  loop
    perform public.roast_plan_recompute(v_fac);
    v_done := v_done + 1;
  end loop;

  -- A week that has rolled over makes every row for that facility stale with no
  -- write to notice, so sweep those in the same pass. This is what replaces a
  -- separate per-timezone midnight job.
  for v_fac in
    select p.facility_id
      from public.roast_plan p
      join public.facility_week_starts(p.facility_id) w
        on w.roast_week_start <> p.roast_week_start
        or w.orders_week_start <> p.orders_week_start
     group by p.facility_id
     limit p_limit
  loop
    perform public.roast_plan_recompute(v_fac);
    v_done := v_done + 1;
  end loop;

  return v_done;
end;
$function$;

-- ── the comparison gate ──────────────────────────────────────────────────────
-- This is what the cutover is allowed to depend on, instead of my confidence.
-- Returns one row per disagreement between what is stored and what the function
-- says right now. Zero rows for every facility is the only acceptable result.
create or replace function public.roast_plan_verify(p_facility_id text)
returns table (
  recipe_id text,
  column_name text,
  stored text,
  live text
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  return query
  with live as (select * from public.roast_detail_by_blend(p_facility_id)),
       stored as (select * from public.roast_plan where facility_id = p_facility_id),
       pairs as (
         select
           coalesce(l.recipe_id, s.recipe_id) as rid,
           l.recipe_id is null  as missing_live,
           s.recipe_id is null  as missing_stored,
           l, s
         from live l
         full outer join stored s on s.recipe_id = l.recipe_id
       )
  select p.rid, c.col, c.s_val, c.l_val
    from pairs p
    cross join lateral (
      values
        ('presence',             case when p.missing_stored then 'ABSENT' else 'present' end,
                                 case when p.missing_live   then 'ABSENT' else 'present' end),
        ('in_stock_roasted',     (p.s).in_stock_roasted::text,     (p.l).in_stock_roasted::text),
        ('total_ordered',        (p.s).total_ordered::text,        (p.l).total_ordered::text),
        ('total_roasted',        (p.s).total_roasted::text,        (p.l).total_roasted::text),
        ('roasted_left',         (p.s).roasted_left::text,         (p.l).roasted_left::text),
        ('roasts_remaining',     (p.s).roasts_remaining::text,     (p.l).roasts_remaining::text),
        ('avg_weekly_lbs',       (p.s).avg_weekly_lbs::text,       (p.l).avg_weekly_lbs::text),
        ('backstock_buffer_pct', (p.s).backstock_buffer_pct::text, (p.l).backstock_buffer_pct::text),
        ('buffer_target',        (p.s).buffer_target::text,        (p.l).buffer_target::text),
        ('effective_target',     (p.s).effective_target::text,     (p.l).effective_target::text),
        ('buffer_left',          (p.s).buffer_left::text,          (p.l).buffer_left::text),
        ('weekly_target_override', (p.s).weekly_target_override::text, (p.l).weekly_target_override::text)
    ) as c(col, s_val, l_val)
   where c.s_val is distinct from c.l_val;
end;
$function$;

comment on function public.roast_plan_verify(text) is
  'One row per disagreement between roast_plan and roast_detail_by_blend() for '
  'a facility. Zero rows everywhere is the gate for moving any reader onto the '
  'stored plan.';

revoke all on function public.roast_plan_recompute(text)   from public, anon;
revoke all on function public.roast_plan_drain(integer)    from public, anon;
revoke all on function public.roast_plan_mark_dirty(text, text) from public, anon;
revoke all on function public.roast_plan_verify(text)      from public, anon;
revoke all on function public.facility_week_starts(text)   from public, anon;
grant execute on function public.roast_plan_recompute(text)   to authenticated, service_role;
grant execute on function public.roast_plan_drain(integer)    to service_role;
grant execute on function public.roast_plan_mark_dirty(text, text) to authenticated, service_role;
grant execute on function public.roast_plan_verify(text)      to authenticated, service_role;
grant execute on function public.facility_week_starts(text)   to authenticated, service_role;

-- ── backfill, and prove it on the way in ─────────────────────────────────────
do $$
declare
  v_fac       record;
  v_rows      int;
  v_total     int := 0;
  v_bad       int;
  v_bad_total int := 0;
  v_sample    text := '';
begin
  for v_fac in select facility_id from public.facilities loop
    v_rows  := public.roast_plan_recompute(v_fac.facility_id);
    v_total := v_total + v_rows;

    select count(*) into v_bad
      from public.roast_plan_verify(v_fac.facility_id);

    if v_bad > 0 then
      v_bad_total := v_bad_total + v_bad;
      select v_sample || format(' [%s: %s/%s %s=%s vs %s]',
               v_fac.facility_id, d.recipe_id, d.column_name, '', d.stored, d.live)
        into v_sample
        from public.roast_plan_verify(v_fac.facility_id) d
       limit 1;
    end if;
  end loop;

  raise notice 'roast_plan backfilled: % rows across % facilities',
    v_total, (select count(*) from public.facilities);

  -- The whole point. A stored plan that does not match the function it caches is
  -- worse than no stored plan, because every reader would believe it.
  if v_bad_total > 0 then
    raise exception 'roast_plan disagrees with roast_detail_by_blend in % place(s).%',
      v_bad_total, v_sample;
  end if;

  -- The table is only useful if it is complete: a facility that produced no row
  -- while the function returns some would read as "nothing to roast".
  if exists (
    select 1 from public.facilities f
     where (select count(*) from public.roast_detail_by_blend(f.facility_id)) > 0
       and not exists (select 1 from public.roast_plan p where p.facility_id = f.facility_id)
  ) then
    raise exception 'a facility with a live plan has no stored rows';
  end if;
end $$;

commit;
