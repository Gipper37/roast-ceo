-- The origin plan has a fresh reader.
--
-- `roast_origin_plan` is correct, maintained and read by nothing. This is the
-- reader the roast page needs before it can leave the view.
--
-- 🔴 WHY NOT A PLAIN TABLE READ. The roast page renders BOTH grains side by
-- side: blendRows via `roast_plan_fresh`, and the origin rows beside them. A
-- plain read of roast_origin_plan is up to a drain cycle behind, so the page
-- would show a recipe panel that includes the roast just charged next to an
-- origin panel that does not. Two plans of different ages on one screen is
-- worse than one slow plan, because nothing on the page says which is which.
-- That is the exact hazard the drain comment in 000020 names, and it applies
-- to the read path too.
--
-- The stock-count sheet reads the plain table on purpose and is not a
-- counter-example: it shows an estimate a human is about to walk over and
-- count. This one is read while deciding what to roast next.
--
-- Same shape as roast_plan_fresh, deliberately: ask whether anything was
-- enqueued AFTER the plan was computed, recompute if so under an advisory lock
-- so concurrent renders collapse into one, then ask again because whoever held
-- the lock was doing precisely this work.
--
-- 🔴 SECURITY INVOKER on the reader, DEFINER on the probe, for the same reason
-- as the recipe-grain pair. roast_origin_plan carries an RLS policy scoped to
-- auth_company_ids(), and the facilityId reaching it comes from the page's own
-- resolved facility -- but making the reader DEFINER would make that parameter
-- a cross-tenant read if any caller ever passes something it did not resolve
-- itself. The probe has to be DEFINER because roast_plan_dirty is readable by
-- nobody but the owner; it returns one boolean and discloses no rows.

begin;

create or replace function public.roast_origin_plan_stale(p_facility_id text)
returns boolean
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  select exists (
    select 1
      from public.roast_plan_dirty d
     where d.facility_id = p_facility_id
       and d.enqueued_at > coalesce(
             (select max(p.computed_at) from public.roast_origin_plan p
               where p.facility_id = p_facility_id),
             '-infinity'::timestamptz)
  );
$function$;

revoke all on function public.roast_origin_plan_stale(text) from public, anon;
grant execute on function public.roast_origin_plan_stale(text) to authenticated, service_role;

create or replace function public.roast_origin_plan_fresh(p_facility_id text)
returns setof public.roast_origin_plan
language plpgsql
security invoker
set search_path to 'public', 'pg_temp'
as $function$
begin
  if p_facility_id is null then
    return;
  end if;

  if public.roast_origin_plan_stale(p_facility_id) then
    -- Prefixed key so this cannot collide with the recipe-grain lock, which a
    -- render of the same page takes at the same moment for the same facility.
    perform pg_advisory_xact_lock(hashtext('roast_origin_plan_fresh:' || p_facility_id));
    if public.roast_origin_plan_stale(p_facility_id) then
      perform public.roast_origin_plan_recompute(p_facility_id);
    end if;
  end if;

  return query
    select p.* from public.roast_origin_plan p where p.facility_id = p_facility_id;
end;
$function$;

revoke all on function public.roast_origin_plan_fresh(text) from public, anon;
grant execute on function public.roast_origin_plan_fresh(text) to authenticated, service_role;

do $$
declare
  r      record;
  v_f    int;
  v_l    int;
  v_fac  int := 0;
begin
  if to_regprocedure('public.roast_origin_plan_fresh(text)') is null then
    raise exception 'roast_origin_plan_fresh(text) is missing';
  end if;

  -- 🔴 The property that makes it safe in front of a client-supplied facility.
  if (select p.prosecdef from pg_proc p where p.oid = 'public.roast_origin_plan_fresh(text)'::regprocedure) then
    raise exception 'roast_origin_plan_fresh must be SECURITY INVOKER; RLS is the only thing scoping it';
  end if;
  if not (select p.prosecdef from pg_proc p where p.oid = 'public.roast_origin_plan_stale(text)'::regprocedure) then
    raise exception 'roast_origin_plan_stale must be SECURITY DEFINER; roast_plan_dirty is not readable by authenticated';
  end if;
  if not has_function_privilege('authenticated', 'public.roast_origin_plan_fresh(text)', 'execute') then
    raise exception 'authenticated cannot execute roast_origin_plan_fresh';
  end if;

  -- It must agree with the live view for every facility, which is the whole
  -- point of serving it instead.
  for r in select distinct facility_id from public.roast_detail where facility_id is not null
  loop
    v_fac := v_fac + 1;
    select count(*) into v_f from public.roast_origin_plan_fresh(r.facility_id);
    select count(*) into v_l from public.roast_detail where facility_id = r.facility_id;
    if v_f <> v_l then
      raise exception 'roast_origin_plan_fresh returned % rows, the view %, for facility %', v_f, v_l, r.facility_id;
    end if;
    if exists (select 1 from public.roast_origin_plan_verify(r.facility_id)) then
      raise exception 'roast_origin_plan_fresh left facility % disagreeing with the view', r.facility_id;
    end if;
  end loop;

  raise notice 'roast_origin_plan_fresh agrees with roast_detail across % facility(ies)', v_fac;
end $$;

commit;
