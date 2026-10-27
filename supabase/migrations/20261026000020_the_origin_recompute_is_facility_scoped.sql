-- The origin recompute is facility scoped.
--
-- Owner, 2026-10-26: *"why is it not facility scoped. shouldn't that be
-- changed. we don't want it running on 100 facilities when we have more
-- users"*. He is right, and 000019's reasoning for the fleet-wide pass was
-- wrong twice over.
--
-- 🔴 WHAT I CLAIMED, AND WHY IT WAS FALSE. 000019 says roast_detail's CTEs are
-- "referenced more than once, so they are an optimisation fence" and therefore
-- a facility predicate "cannot push inside". That is true of
-- roast_detail_by_blend, whose CTEs are referenced 2-5 times, and it is why
-- 20260910000036 gave THAT view a function form. It is NOT true here: every
-- CTE in roast_detail is referenced exactly once, and a singly-referenced CTE
-- is INLINED from PG12 on. I carried the sibling's diagnosis across without
-- checking whether its premise held.
--
-- Measured on production, EXPLAIN (ANALYZE, BUFFERS), the view with a facility
-- predicate versus the scoped body with the predicate written inside the two
-- CTEs rooted in `facilities`:
--
--     identical plans, identical 218,696 buffers, identical md5 of the
--     sorted result set
--
-- The planner was already scoping it. No function form is needed.
--
-- 🔴 THE REAL DEFECT WAS MINE, NOT THE PLANNER'S. roast_origin_plan_recompute()
-- took NO argument and read the whole view, so it recomputed every facility on
-- every drain pass no matter which one was dirty. That is O(tenants) by
-- construction. Measured:
--
--     scoped, per facility     218,696 + 233,764 + 65,221 + 234,854 buffers
--     unscoped, one pass       752,493 buffers
--
-- The fleet-wide cost IS the sum of the facilities. So refreshing ONE roastery
-- cost all four: 3.4x waste today, ~100x at a hundred roasteries, paid every
-- minute forever. Exactly the shape the stored plan exists to remove,
-- reintroduced in the thing that maintains it.
--
-- 🔴 AND IT IS THE RULE I HAVE BEEN GIVEN: derive behaviour from the SCHEMA,
-- never from one tenant's current values. "144ms at four facilities" is a
-- measurement of MCR, not a property of the design.
--
-- Changes no read path. roast_origin_plan's contents are identical either way;
-- only the cost of maintaining them changes.

begin;

-- Scoped. The zero-argument form is DROPPED, not left beside it: an overload
-- that still scans the fleet is one a future caller can pick by accident.
drop function if exists public.roast_origin_plan_recompute();

create or replace function public.roast_origin_plan_recompute(p_facility_id text)
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_rows int;
begin
  if p_facility_id is null then
    return 0;
  end if;

  with live as (
    select d.facility_id, d.origin, d.roast_detail_id, d.company_id,
           d.in_stock_roasted, d.total_roasted, d.total_ordered,
           d.final_roasted_weight, d.green_to_roast, d.roasts_remaining
      from public.roast_detail d
     where d.facility_id = p_facility_id
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
    returning p.facility_id
  )
  select count(*) into v_rows from upserted;

  -- An origin that stopped existing must LEAVE, but only within THIS facility.
  -- The unscoped version compared against the whole view, which is the same
  -- fleet-wide read again by another name.
  delete from public.roast_origin_plan p
   where p.facility_id = p_facility_id
     and not exists (
       select 1 from public.roast_detail d
        where d.facility_id = p_facility_id
          and d.origin is not distinct from p.origin
     );

  return v_rows;
end;
$function$;

revoke all on function public.roast_origin_plan_recompute(text) from public, anon;
grant execute on function public.roast_origin_plan_recompute(text) to authenticated, service_role;

-- ── The drain, taken verbatim from production and re-pointed ─────────────
-- Origins now refresh beside the recipe plan for the SAME facility, inside
-- the existing loops, instead of once fleet-wide at the end.
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
    -- The origin plan for the SAME facility, in the same pass. Both grains are
    -- invalidated by the same queue, so refreshing one without the other would
    -- leave the roast page reading two plans of different ages.
    perform public.roast_origin_plan_recompute(r.facility_id);
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
    -- The origin plan for the SAME facility, in the same pass. Both grains are
    -- invalidated by the same queue, so refreshing one without the other would
    -- leave the roast page reading two plans of different ages.
    perform public.roast_origin_plan_recompute(r.facility_id);
    v_done := v_done + 1;
  end loop;

  return v_done;
end;
$function$;

-- ── The reconcile, likewise ───────────────────────────────────────────────
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
      v_fixed := v_fixed + 1;
      insert into public.roast_plan_drift (facility_id, disagreements, plan_age_s, repaired)
      select r.facility_id,
             (select count(*) from public.roast_origin_plan_verify(r.facility_id)),
             (select round(extract(epoch from (now() - max(computed_at))))::int
                from public.roast_origin_plan where facility_id = r.facility_id),
             true;
      perform public.roast_origin_plan_recompute(r.facility_id);
    end if;
  end loop;
  -- Repaired per facility, not fleet-wide: the whole point of scoping the
  -- recompute is that refreshing one roastery does not pay for the others.

  return v_fixed;
end;
$function$;

do $$
declare
  r      record;
  v_bad  int := 0;
  v_fac  int := 0;
begin
  if to_regprocedure('public.roast_origin_plan_recompute()') is not null then
    raise exception 'the fleet-wide overload of roast_origin_plan_recompute still exists';
  end if;
  if to_regprocedure('public.roast_origin_plan_recompute(text)') is null then
    raise exception 'roast_origin_plan_recompute(text) is missing';
  end if;

  -- The drain must call the SCOPED form, and must not have kept the other.
  if pg_get_functiondef('public.roast_plan_drain(integer)'::regprocedure)
       not like '%roast_origin_plan_recompute(r.facility_id)%' then
    raise exception 'roast_plan_drain does not call the facility-scoped recompute';
  end if;

  -- Recompute every facility through the new path, then assert the stored
  -- answer is UNCHANGED: scoping is a cost change, never a data change.
  for r in select facility_id from public.facilities
  loop
    perform public.roast_origin_plan_recompute(r.facility_id);
  end loop;

  for r in select distinct facility_id from public.roast_detail where facility_id is not null
  loop
    v_fac := v_fac + 1;
    v_bad := v_bad + (select count(*) from public.roast_origin_plan_verify(r.facility_id));
  end loop;
  if v_bad <> 0 then
    raise exception 'scoped recompute changed the answer: % disagreement(s) across % facility(ies)', v_bad, v_fac;
  end if;

  -- The null-origin row must still round-trip through the scoped path.
  if (select count(*) from public.roast_detail where origin is null) <>
     (select count(*) from public.roast_origin_plan where origin is null) then
    raise exception 'the null-origin row did not survive the scoped recompute';
  end if;

  raise notice 'origin recompute is facility scoped; % facility(ies) agree', v_fac;
end $$;

commit;
