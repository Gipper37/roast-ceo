-- The origin plan is stored too.
--
-- `roast_plan` took the recipe-grain planner off the read path. This is the
-- other half: `roast_detail`, the ORIGIN-grain view, measured on production
-- today at 26.5 hours of database time across 221,974 calls -- 10.8% of
-- everything, and the largest remaining consumer now the blend view is gone.
--
-- 🔴 roast_plan DOES NOT COVER IT, which is why this exists at all. roast_plan
-- is keyed (facility_id, recipe_id); roast_detail's spine is one row per
-- green-coffee ORIGIN per facility. Its in_stock_roasted / total_roasted /
-- total_ordered are origin-grain numbers that cannot be split back out of
-- recipe-grain ones without redoing the recipe_components percentage fan-out
-- the view already does, and it carries final_roasted_weight and
-- green_to_roast, which roast_plan has no column for.
--
-- ── WHY ONE WHOLE-FLEET PASS, NOT PER FACILITY ────────────────────────────
--
-- Unlike roast_detail_by_blend there is NO facility-scoped function form, only
-- the view, and its CTEs are referenced more than once, so they are an
-- optimisation fence and `.eq('facility_id', X)` cannot reach inside. Every
-- read computes the WHOLE FLEET and discards the rest. Measured: a full
-- evaluation is 144ms, against a 135.5ms mean per existing call -- i.e. one
-- read already pays for all four facilities. So recompute takes no facility
-- argument and the drain calls it ONCE per pass.
--
-- ── NO NEW TRIGGERS ───────────────────────────────────────────────────────
--
-- roast_detail depends on nine tables (company_parameters, facilities,
-- order_details, orders, products, recipe_components, roast_log,
-- roast_recipes, roast_stock_log). Read off pg_depend, not guessed. All nine
-- are a strict SUBSET of the thirteen already carrying `_roast_plan_dirty`
-- triggers, so every input that can move this plan already marks its company
-- dirty. Adding a second set of triggers would be a second thing to keep in
-- step with the first.
--
-- ── THE KEY, AND A ROW THAT BREAKS THE OBVIOUS ONE ────────────────────────
--
-- 🔴 `roast_detail_id` LOOKS like the key and is not: one of production's 60
-- rows has it NULL. That same row has a NULL `origin` too (MCR's facility, all
-- figures zero -- an empty placeholder). So neither `roast_detail_id` nor a
-- plain `(facility_id, origin)` primary key can hold the real data.
-- Hence a surrogate key plus `unique nulls not distinct (facility_id, origin)`:
-- PG15+ treats the NULLs as equal, so the placeholder row is kept, upserts
-- cleanly, and cannot silently duplicate on every recompute. Server is 17.6.
--
-- Changes NO read path. Nothing selects from this table yet; the frontend
-- cutover is a separate change, after roast_origin_plan_verify reads zero.

begin;

create table if not exists public.roast_origin_plan (
  id                   bigserial primary key,
  facility_id          text not null,
  origin               text,
  roast_detail_id      text,
  company_id           text,
  in_stock_roasted     numeric,
  total_roasted        numeric,
  total_ordered        numeric,
  final_roasted_weight numeric,
  green_to_roast       numeric,
  roasts_remaining     numeric,
  computed_at          timestamptz not null default now()
);

comment on table public.roast_origin_plan is
  'Stored form of the roast_detail view (origin grain). Maintained by roast_plan_drain, which reuses the roast_plan_dirty queue because roast_detail''s inputs are a subset of that queue''s thirteen tables.';

-- NULLS NOT DISTINCT so the one real row with a null origin has a stable
-- identity instead of being re-inserted on every pass.
create unique index if not exists uq_roast_origin_plan_facility_origin
  on public.roast_origin_plan (facility_id, origin) nulls not distinct;

alter table public.roast_origin_plan enable row level security;

drop policy if exists roast_origin_plan_read on public.roast_origin_plan;
create policy roast_origin_plan_read on public.roast_origin_plan
  for select using (company_id in (select public.auth_company_ids()));

-- 🔴 REVOKE FROM `authenticated` TOO, NOT JUST `anon`. Supabase default
-- privileges grant ALL on every new public table to anon, authenticated and
-- service_role, so `grant select` NARROWS NOTHING on its own -- it restates one
-- privilege the role already holds beside INSERT/UPDATE/DELETE/TRUNCATE it also
-- holds. RLS does not save you: TRUNCATE is a table privilege row-level
-- security never consults. 20261026000012 made exactly this mistake on
-- roast_plan and 20261026000015 had to undo it.
revoke all on table public.roast_origin_plan from anon, authenticated;
grant select on table public.roast_origin_plan to authenticated;
revoke all on sequence public.roast_origin_plan_id_seq from anon, authenticated;

-- ── Recompute: the whole fleet, one pass ──────────────────────────────────
create or replace function public.roast_origin_plan_recompute()
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_rows int;
begin
  -- One statement: the view is evaluated once and every facility lands
  -- together, so there is no window where half the fleet is current.
  with live as (
    select d.facility_id, d.origin, d.roast_detail_id, d.company_id,
           d.in_stock_roasted, d.total_roasted, d.total_ordered,
           d.final_roasted_weight, d.green_to_roast, d.roasts_remaining
      from public.roast_detail d
     where d.facility_id is not null
  ),
  upserted as (
    insert into public.roast_origin_plan as p
      (facility_id, origin, roast_detail_id, company_id, in_stock_roasted,
       total_roasted, total_ordered, final_roasted_weight, green_to_roast,
       roasts_remaining, computed_at)
    select l.facility_id, l.origin, l.roast_detail_id, l.company_id,
           l.in_stock_roasted, l.total_roasted, l.total_ordered,
           l.final_roasted_weight, l.green_to_roast, l.roasts_remaining, now()
      from live l
    on conflict (facility_id, origin) do update
      set roast_detail_id      = excluded.roast_detail_id,
          company_id           = excluded.company_id,
          in_stock_roasted     = excluded.in_stock_roasted,
          total_roasted        = excluded.total_roasted,
          total_ordered        = excluded.total_ordered,
          final_roasted_weight = excluded.final_roasted_weight,
          green_to_roast       = excluded.green_to_roast,
          roasts_remaining     = excluded.roasts_remaining,
          computed_at          = now()
    returning p.facility_id, p.origin
  )
  select count(*) into v_rows from upserted;

  -- An origin that stopped existing -- a recipe component removed, a facility
  -- dropped -- must LEAVE. Without this the table only ever grows and a stale
  -- origin keeps showing demand nobody can satisfy.
  delete from public.roast_origin_plan p
   where not exists (
     select 1 from public.roast_detail d
      where d.facility_id is not distinct from p.facility_id
        and d.origin is not distinct from p.origin
   );

  return v_rows;
end;
$function$;

revoke all on function public.roast_origin_plan_recompute() from public, anon;
grant execute on function public.roast_origin_plan_recompute() to authenticated, service_role;

-- ── Verify: the oracle, same shape as roast_plan_verify ───────────────────
create or replace function public.roast_origin_plan_verify(p_facility_id text)
returns table (origin text, column_name text, stored numeric, live numeric)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with s as (select * from public.roast_origin_plan where facility_id = p_facility_id),
       l as (select * from public.roast_detail        where facility_id = p_facility_id)
  select coalesce(s.origin, l.origin), v.col, v.s_val, v.l_val
    from s full outer join l on l.origin is not distinct from s.origin
   cross join lateral (values
      ('in_stock_roasted',     s.in_stock_roasted,     l.in_stock_roasted),
      ('total_roasted',        s.total_roasted,        l.total_roasted),
      ('total_ordered',        s.total_ordered,        l.total_ordered),
      ('final_roasted_weight', s.final_roasted_weight, l.final_roasted_weight),
      ('green_to_roast',       s.green_to_roast,       l.green_to_roast),
      ('roasts_remaining',     s.roasts_remaining,     l.roasts_remaining)
   ) as v(col, s_val, l_val)
   where v.s_val is distinct from v.l_val;
$function$;

revoke all on function public.roast_origin_plan_verify(text) from public, anon;
grant execute on function public.roast_origin_plan_verify(text) to authenticated, service_role;

-- ── The drain keeps it current ────────────────────────────────────────────
-- Body taken verbatim from production (pg_get_functiondef) and extended, NOT
-- retyped: CREATE OR REPLACE rewrites the WHOLE body, so retyping one from
-- memory silently drops whatever it does not remember.
CREATE OR REPLACE FUNCTION public.roast_plan_drain(p_limit integer DEFAULT 10)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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

  -- ── The origin plan, once, for the whole fleet ───────────────────────────
  -- `roast_detail` takes no facility parameter and its CTEs are referenced
  -- more than once, so a facility predicate cannot push inside: ANY read of it
  -- computes every facility and throws the rest away. That makes per-facility
  -- recompute pure waste here -- a whole-fleet pass is 144ms, the same as one
  -- read -- so it runs ONCE per drain, not once per dirty facility.
  --
  -- No new triggers: roast_detail's nine input tables (company_parameters,
  -- facilities, order_details, orders, products, recipe_components, roast_log,
  -- roast_recipes, roast_stock_log) are a strict SUBSET of the thirteen
  -- already marking this queue dirty, so anything that moves the origin plan
  -- has already enqueued its company.
  if v_done > 0 then
    perform public.roast_origin_plan_recompute();
  end if;

  return v_done;
end;
$function$;

-- ── The hourly reconcile covers it too ───────────────────────────────────
-- Also taken verbatim from production and extended.
CREATE OR REPLACE FUNCTION public.roast_plan_reconcile()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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

  -- ── The origin plan, same hourly safety net ──────────────────────────────
  -- Iterates `facilities`, NOT roast_origin_plan: a facility whose rows have
  -- all gone is exactly the case a self-healing pass has to catch, and one
  -- that iterates its own output cannot see it. (The roast_plan loop above
  -- still has that blind spot; it is tracked separately rather than changed
  -- here, because widening it is a behaviour change this migration did not
  -- set out to make.)
  --
  -- One recompute covers every facility, so this counts disagreeing facilities
  -- but repairs once.
  v_bad := 0;
  for r in select facility_id from public.facilities
  loop
    if exists (select 1 from public.roast_origin_plan_verify(r.facility_id)) then
      v_bad := v_bad + 1;
      insert into public.roast_plan_drift (facility_id, disagreements, plan_age_s, repaired)
      select r.facility_id,
             (select count(*) from public.roast_origin_plan_verify(r.facility_id)),
             (select round(extract(epoch from (now() - max(computed_at))))::int
                from public.roast_origin_plan where facility_id = r.facility_id),
             true;
    end if;
  end loop;
  if v_bad > 0 then
    perform public.roast_origin_plan_recompute();
    v_fixed := v_fixed + v_bad;
  end if;

  return v_fixed;
end;
$function$;

-- ── Backfill, and prove it ────────────────────────────────────────────────
do $$
declare
  v_rows  int;
  v_bad   int;
  v_fac   int;
  r       record;
begin
  v_rows := public.roast_origin_plan_recompute();
  raise notice 'origin plan backfilled: % row(s)', v_rows;

  -- 🔴 Every facility must agree with the live view, not just the one that
  -- happened to be probed. 20261026000012's verify asserted a SIGNATURE
  -- existed and that is how a function broken on 100% of calls shipped green;
  -- this asserts the ANSWER.
  v_bad := 0; v_fac := 0;
  for r in select distinct facility_id from public.roast_detail where facility_id is not null
  loop
    v_fac := v_fac + 1;
    v_bad := v_bad + (select count(*) from public.roast_origin_plan_verify(r.facility_id));
  end loop;
  if v_bad <> 0 then
    raise exception 'stored origin plan disagrees with roast_detail in % place(s) across % facility(ies)', v_bad, v_fac;
  end if;
  raise notice 'origin plan agrees with roast_detail across % facility(ies)', v_fac;

  -- The null-origin row must have SURVIVED. If NULLS NOT DISTINCT were not
  -- doing its job the upsert would duplicate it on every pass instead.
  if (select count(*) from public.roast_detail where origin is null) <>
     (select count(*) from public.roast_origin_plan where origin is null) then
    raise exception 'the null-origin row did not round-trip; check NULLS NOT DISTINCT';
  end if;

  -- Idempotence: a second pass must change nothing and add nothing.
  v_rows := (select count(*) from public.roast_origin_plan);
  perform public.roast_origin_plan_recompute();
  if (select count(*) from public.roast_origin_plan) <> v_rows then
    raise exception 'recompute is not idempotent: row count moved on a second pass';
  end if;

  -- The grants that 000012 got wrong on the sibling table.
  if has_table_privilege('authenticated','public.roast_origin_plan','TRUNCATE')
     or has_table_privilege('authenticated','public.roast_origin_plan','INSERT') then
    raise exception 'authenticated still holds a write privilege on roast_origin_plan';
  end if;
  if not has_table_privilege('authenticated','public.roast_origin_plan','SELECT') then
    raise exception 'authenticated lost SELECT on roast_origin_plan; readers would 403';
  end if;
  if has_table_privilege('anon','public.roast_origin_plan','SELECT') then
    raise exception 'anon can read roast_origin_plan';
  end if;

  -- The drain must actually call it, or the table is a snapshot that rots.
  if pg_get_functiondef('public.roast_plan_drain(integer)'::regprocedure)
       not like '%roast_origin_plan_recompute%' then
    raise exception 'roast_plan_drain does not recompute the origin plan';
  end if;

  raise notice 'origin plan stored, maintained by the existing queue, and read by nothing yet';
end $$;

commit;
