-- The stored plan keeps itself current.
--
-- 20261026000012 added `roast_plan` and proved it equals
-- roast_detail_by_blend() on production: 142 rows, zero disagreements across
-- six facilities. But nothing kept it current, so it was correct only as of its
-- backfill. This adds the invalidation.
--
-- 🔴 THE INPUT SET IS THE WHOLE CORRECTNESS ARGUMENT. A table missing from this
-- list is a table whose change leaves the plan wrong FOREVER, with nothing to
-- report it. Derived by walking every FROM/JOIN in the function body and then
-- classifying each name against pg_class, because the body is 445 lines of
-- nested subqueries where CTE names and table names read alike -- `calc`,
-- `recipe_anchor`, `recipe_facility` and `recipe_override` all look like tables
-- and are not. The thirteen that are real:
--
--   facility-scoped (11): company_parameters, facilities, order_details, orders,
--     pack_stock_count, products, recipe_components, recipe_weekly_targets,
--     roast_log, roast_recipes, roast_stock_log
--   indirect (1): roast_log_recipes -- has NO facility_id; resolved through
--     roast_log.roast_log_id. This is the table that feeds total_roasted and had
--     one writer across ten paths, so it must not be left out.
--   global (1): standard_parameters -- the fallback for every parameter the
--     facility has not overridden, so a change there moves EVERY facility.
--
-- `recipe_demand_source` is deliberately absent: it is a VIEW over
-- recipe_components and roast_recipes, both already listed. Putting a trigger on
-- a view would have failed, and assuming it was a table would have left the
-- parent/child demand mapping uninvalidated -- the exact class of error this
-- project has made repeatedly with that relation.
--
-- 🔴 ENQUEUE ONLY, NEVER RECOMPUTE, INSIDE A WRITE. The trigger performs one
-- `insert ... on conflict do nothing` into a table with one row per facility:
-- an index probe. roast_log already carries 12 triggers and charging a roast
-- already holds locks for ~17 seconds, so a 650ms recompute inside that write
-- would turn a slow write into an unavailable one. Reads are made fast by the
-- stored table; writes stay exactly as fast as they are today.
--
-- This still changes NO read path. Nothing selects from roast_plan yet.

begin;

-- ── the queue must be APPEND-ONLY ────────────────────────────────────────────
-- 🔴 A LOST-UPDATE RACE, FOUND BEFORE SHIPPING AND WORTH STATING PLAINLY.
-- 20261026000012 made facility_id the PRIMARY KEY and enqueued with
-- `on conflict do nothing`. The drain deletes that row while it recomputes, so
-- a write landing DURING a recompute sees the row still live in its snapshot,
-- does nothing, and then has its enqueue deleted along with the row it
-- collided with. That facility then stays stale until some unrelated write
-- happens to enqueue again -- the exact silent staleness this design exists to
-- prevent, and invisible because nothing reports it.
--
-- Append-only removes the race rather than narrowing it: an enqueue never
-- examines an existing row, so it can neither block nor be swallowed. The drain
-- claims a high-water id per facility and deletes only up to it, so anything
-- enqueued mid-recompute carries a larger id and survives to the next pass.
alter table public.roast_plan_dirty drop constraint if exists roast_plan_dirty_pkey;
alter table public.roast_plan_dirty add column if not exists id bigserial primary key;
create index if not exists idx_roast_plan_dirty_facility on public.roast_plan_dirty (facility_id, id);

-- Plain inserts now: no conflict target, nothing to wait on.
create or replace function public.roast_plan_mark_dirty(p_facility_id text, p_reason text default null)
returns void
language sql
security definer
set search_path to 'public', 'pg_temp'
as $function$
  insert into public.roast_plan_dirty (facility_id, reason)
  select p_facility_id, p_reason where p_facility_id is not null;
$function$;

-- The recompute no longer clears the queue -- the DRAIN owns that, because only
-- the drain knows which ids it actually covered.
create or replace function public.roast_plan_recompute(p_facility_id text)
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_rows   int;
  v_roast  date;
  v_orders date;
begin
  select w.roast_week_start, w.orders_week_start
    into v_roast, v_orders
    from public.facility_week_starts(p_facility_id) w;

  if v_roast is null then
    return 0;
  end if;

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
  return v_rows;
end;
$function$;

-- Claim by high-water id, recompute, then delete only what was claimed.
create or replace function public.roast_plan_drain(p_limit integer default 10)
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  r      record;
  v_done int := 0;
begin
  for r in
    select d.facility_id, max(d.id) as high_water
      from public.roast_plan_dirty d
     group by d.facility_id
     order by min(d.enqueued_at)
     limit p_limit
  loop
    perform public.roast_plan_recompute(r.facility_id);
    -- Only up to the id we had when we started. A write that enqueued while the
    -- recompute ran has a larger id and is still pending, so it is picked up
    -- next pass instead of being thrown away.
    delete from public.roast_plan_dirty
     where facility_id = r.facility_id and id <= r.high_water;
    v_done := v_done + 1;
  end loop;

  -- A rolled-over week makes every row for a facility stale with no write to
  -- notice it, so sweep those in the same pass. This replaces a per-timezone
  -- midnight job.
  for r in
    select p.facility_id
      from public.roast_plan p
      join public.facility_week_starts(p.facility_id) w
        on w.roast_week_start <> p.roast_week_start
        or w.orders_week_start <> p.orders_week_start
     group by p.facility_id
     limit p_limit
  loop
    perform public.roast_plan_recompute(r.facility_id);
    v_done := v_done + 1;
  end loop;

  return v_done;
end;
$function$;

grant execute on function public.roast_plan_drain(integer) to service_role;
grant execute on function public.roast_plan_recompute(text) to authenticated, service_role;
grant execute on function public.roast_plan_mark_dirty(text, text) to authenticated, service_role;

-- ── mark every facility of a company dirty ───────────────────────────────────
-- Needed because some inputs are company-scoped with a null facility_id (a
-- product variant, for instance), and because standard_parameters is global.
create or replace function public.roast_plan_mark_company_dirty(p_company_id text, p_reason text default null)
returns void
language sql
security definer
set search_path to 'public', 'pg_temp'
as $function$
  insert into public.roast_plan_dirty (facility_id, reason)
  select f.facility_id, p_reason
    from public.facilities f
   where p_company_id is not null
     and f.company_id = p_company_id;
$function$;

create or replace function public.roast_plan_mark_all_dirty(p_reason text default null)
returns void
language sql
security definer
set search_path to 'public', 'pg_temp'
as $function$
  insert into public.roast_plan_dirty (facility_id, reason)
  select f.facility_id, p_reason from public.facilities f;
$function$;

-- ── the generic trigger ──────────────────────────────────────────────────────
-- One function for all eleven facility-scoped tables. It reads facility_id and
-- company_id out of to_jsonb(NEW/OLD) rather than naming columns, so attaching
-- it to another input table later needs no new code and cannot be attached
-- half-right.
--
-- BOTH sides are marked on an UPDATE: a row that moves between facilities makes
-- the old facility's plan wrong too, and marking only NEW would leave it stale
-- forever. That is the same shape as the re-pointed-product bug that sent an
-- estimate to 2009 lbs.
create or replace function public.roast_plan_touch()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  j        jsonb;
  v_fac    text;
  v_co     text;
begin
  foreach j in array array[
    case when tg_op <> 'DELETE' then to_jsonb(new) end,
    case when tg_op <> 'INSERT' then to_jsonb(old) end
  ]
  loop
    if j is null then continue; end if;
    v_fac := j ->> 'facility_id';
    v_co  := j ->> 'company_id';
    if v_fac is not null then
      perform public.roast_plan_mark_dirty(v_fac, tg_table_name);
    elsif v_co is not null then
      -- No facility on the row: the change could touch any facility of that
      -- company, so mark them all rather than guess one.
      perform public.roast_plan_mark_company_dirty(v_co, tg_table_name);
    end if;
  end loop;
  return null;
end;
$function$;

-- roast_log_recipes carries neither column, so resolve the facility through the
-- roast it belongs to.
create or replace function public.roast_plan_touch_via_roast_log()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_fac text;
begin
  for v_fac in
    select distinct rl.facility_id
      from public.roast_log rl
     where rl.roast_log_id in (
             coalesce((case when tg_op <> 'DELETE' then new.roast_log_id end), null),
             coalesce((case when tg_op <> 'INSERT' then old.roast_log_id end), null)
           )
       and rl.facility_id is not null
  loop
    perform public.roast_plan_mark_dirty(v_fac, 'roast_log_recipes');
  end loop;
  return null;
end;
$function$;

create or replace function public.roast_plan_touch_all()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  perform public.roast_plan_mark_all_dirty(tg_table_name);
  return null;
end;
$function$;

revoke all on function public.roast_plan_mark_company_dirty(text, text) from public, anon;
revoke all on function public.roast_plan_mark_all_dirty(text) from public, anon;
grant execute on function public.roast_plan_mark_company_dirty(text, text) to authenticated, service_role;
grant execute on function public.roast_plan_mark_all_dirty(text) to authenticated, service_role;

-- ── attach them ──────────────────────────────────────────────────────────────
do $$
declare
  t    text;
  tbls text[] := array[
    'company_parameters','facilities','order_details','orders','pack_stock_count',
    'products','recipe_components','recipe_weekly_targets','roast_log',
    'roast_recipes','roast_stock_log'
  ];
begin
  foreach t in array tbls loop
    -- Fail loudly on a name that is not a real table: a silently skipped
    -- trigger is a permanently stale plan, which is the failure mode this whole
    -- migration exists to prevent.
    if to_regclass('public.' || t) is null then
      raise exception 'roast_plan input table % does not exist', t;
    end if;
    execute format('drop trigger if exists trg_%s_roast_plan_dirty on public.%I', t, t);
    execute format(
      'create trigger trg_%s_roast_plan_dirty after insert or update or delete on public.%I '
      'for each row execute function public.roast_plan_touch()', t, t);
  end loop;
end $$;

drop trigger if exists trg_roast_log_recipes_roast_plan_dirty on public.roast_log_recipes;
create trigger trg_roast_log_recipes_roast_plan_dirty
  after insert or update or delete on public.roast_log_recipes
  for each row execute function public.roast_plan_touch_via_roast_log();

drop trigger if exists trg_standard_parameters_roast_plan_dirty on public.standard_parameters;
create trigger trg_standard_parameters_roast_plan_dirty
  after insert or update or delete on public.standard_parameters
  for each row execute function public.roast_plan_touch_all();

-- ── drain it on a schedule ───────────────────────────────────────────────────
-- Every minute, matching the cadence lot_recompute_drain already runs at. The
-- plan is therefore at most ~60s behind a write, against a roast page that
-- polls every 5 minutes today -- so the stored plan is FRESHER than what the
-- operator currently sees, not staler.
--
-- 🔴 p_limit bounds the pass. An unbounded drain is how one slow recompute
-- becomes a stall, and lot_recompute_drain already shows that failure: 360 runs
-- in six hours, 17 over 5s, worst 64.2s. Six facilities exist, so 10 is the
-- whole fleet with room to spare.
-- 🔴 GUARDED, BECAUSE STAGING HAS NO pg_cron. `cron.job` does not exist there,
-- so a bare `select cron.schedule(...)` fails CI's db-push-staging -- the very
-- rehearsal that is supposed to catch problems before prod. Skipping the
-- schedule there costs nothing: staging has no traffic to keep a plan warm for,
-- and the assertion below only demands the job where the extension exists.
-- 🔴 AND IT HAS TO BE DYNAMIC SQL, not an `if` around a direct reference.
-- plpgsql PLANS a statement before it runs it, so `cron.job` in a condition
-- fails with "relation cron.job does not exist" on staging even when the guard
-- in front of it is false. EXECUTE defers the parse to the branch that is
-- actually taken. The first attempt at this guard failed exactly that way.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute $q$ select cron.unschedule('roast_plan_drain')
                 where exists (select 1 from cron.job where jobname = 'roast_plan_drain') $q$;
    execute $q$ select cron.schedule('roast_plan_drain', '* * * * *',
                                     'select public.roast_plan_drain(10)') $q$;
  else
    raise notice 'pg_cron absent (staging): roast_plan_drain not scheduled here';
  end if;
end $$;

do $$
declare
  n_trig      int;
  n_dirty     int;
  v_scheduled boolean;
begin
  select count(*) into n_trig
    from pg_trigger
   where tgname like '%_roast_plan_dirty'
     and not tgisinternal;
  -- 11 generic + roast_log_recipes + standard_parameters
  if n_trig <> 13 then
    raise exception 'expected 13 roast_plan invalidation triggers, found %', n_trig;
  end if;

  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute $q$ select exists (
      select 1 from cron.job where jobname = 'roast_plan_drain' and active) $q$
      into v_scheduled;
    if not v_scheduled then
      raise exception 'pg_cron is installed but roast_plan_drain is not scheduled';
    end if;
  end if;

  -- Prove the wiring works rather than assuming it: touch a parameter row and
  -- confirm something landed in the queue. Inside this transaction, so the
  -- write is undone with it.
  update public.standard_parameters set amount = amount where parameters_id = (
    select parameters_id from public.standard_parameters limit 1);
  select count(*) into n_dirty from public.roast_plan_dirty;
  if n_dirty = 0 then
    raise exception 'a write to an input table enqueued nothing; the triggers are not firing';
  end if;
  raise notice 'invalidation proven: a standard_parameters write enqueued % facility(ies)', n_dirty;

  -- Prove the append-only property, which is the whole point of the change: two
  -- enqueues of the SAME facility must both persist, so a drain that claims the
  -- first cannot discard the second.
  perform public.roast_plan_mark_dirty((select facility_id from public.facilities limit 1), 'race-probe');
  perform public.roast_plan_mark_dirty((select facility_id from public.facilities limit 1), 'race-probe');
  if (select count(*) from public.roast_plan_dirty where reason = 'race-probe') <> 2 then
    raise exception 'the queue collapsed two enqueues into one; an enqueue can still be swallowed';
  end if;

  delete from public.roast_plan_dirty;
end $$;

commit;
