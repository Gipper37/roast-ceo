-- The origin recompute reads the view once.
--
-- 000020 scoped the recompute to one facility, which was the point. It left a
-- second cost in place that scoping made visible:
--
--     bare scoped read of roast_detail, one facility     146 ms
--     roast_origin_plan_recompute for that facility      833 ms   (5.7x)
--
-- The body names `public.roast_detail` TWICE -- once in the `live` CTE that
-- feeds the upsert, and again in the DELETE's `not exists (...)`. Worse, that
-- second one is CORRELATED: it is evaluated per existing row of
-- roast_origin_plan, not once. So the view is re-planned and re-run for every
-- row the facility already had, which is why the gap is 5.7x and not 2x.
--
-- 🔴 THE POINT OF THE STORED TABLE IS THAT THE EXPENSIVE THING RUNS RARELY.
-- A maintenance path that reads the expensive relation several times per pass
-- is the same mistake as reading it on every page render, moved somewhere less
-- visible. 000020 fixed what it was proportional to; this fixes the constant.
--
-- One data-modifying statement, with the CTE reused by both arms. All CTEs in
-- such a statement see the SAME SNAPSHOT, and the DELETE does not observe the
-- INSERT's rows -- which is exactly right here, because the delete decides from
-- `live`, not from the table's new contents. There is no overlap to worry
-- about either way: the upsert writes rows that ARE in live, the delete removes
-- rows that are NOT.
--
-- Changes no read path and must change no data; the verify asserts that.

begin;

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
  gone as (
    -- Reads `live`, NOT roast_detail again. An origin that stopped existing
    -- must leave, and only within this facility.
    delete from public.roast_origin_plan p
     where p.facility_id = p_facility_id
       and not exists (
         select 1 from live l where l.origin is not distinct from p.origin
       )
    returning 1
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
  select (select count(*) from upserted) into v_rows;

  return v_rows;
end;
$function$;

revoke all on function public.roast_origin_plan_recompute(text) from public, anon;
grant execute on function public.roast_origin_plan_recompute(text) to authenticated, service_role;

do $$
declare
  r     record;
  v_bad int := 0;
  v_fac int := 0;
  v_n   int;
begin
  -- The view must now be named ONCE in the body. This is the assertion the
  -- whole migration exists for, so it is checked rather than assumed.
  v_n := (length(pg_get_functiondef('public.roast_origin_plan_recompute(text)'::regprocedure))
          - length(replace(pg_get_functiondef('public.roast_origin_plan_recompute(text)'::regprocedure), 'public.roast_detail', '')))
         / length('public.roast_detail');
  if v_n <> 1 then
    raise exception 'roast_origin_plan_recompute still reads roast_detail % times', v_n;
  end if;

  -- Run it for every facility through the new body, then assert the stored
  -- answer is UNCHANGED. A performance change that alters data is a bug.
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
    raise exception 'single-read recompute changed the answer: % disagreement(s) across % facility(ies)', v_bad, v_fac;
  end if;

  if (select count(*) from public.roast_detail where origin is null) <>
     (select count(*) from public.roast_origin_plan where origin is null) then
    raise exception 'the null-origin row did not survive the single-read recompute';
  end if;

  -- The delete arm must still work: a row for a facility that no longer has
  -- that origin has to go. Proven by planting one and checking it leaves.
  insert into public.roast_origin_plan (facility_id, origin, company_id)
  select r2.facility_id, '__verify_only_origin__', null
    from (select facility_id from public.facilities limit 1) r2;
  perform public.roast_origin_plan_recompute(
    (select facility_id from public.facilities limit 1));
  if exists (select 1 from public.roast_origin_plan where origin = '__verify_only_origin__') then
    raise exception 'the delete arm did not remove an origin that no longer exists';
  end if;

  raise notice 'origin recompute reads the view once; % facility(ies) agree', v_fac;
end $$;

commit;
