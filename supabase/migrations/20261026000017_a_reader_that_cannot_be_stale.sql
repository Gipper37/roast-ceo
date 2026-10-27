-- A reader that cannot be stale.
--
-- The badge moved to the stored plan in bd4ecd52 and that was safe because a
-- badge may lag: "a badge that is a little wrong beats an app that will not
-- load" (lib/roast/badgeCount.ts). `blendRowsFor` is NOT that.
--
-- 🔴 LOAD FROM QUEUE DECIDES WHAT TO ROAST FROM THESE ROWS. It reads
-- roasts_remaining / roasted_left and inserts batches. Point it at a table
-- refreshed by a one-minute drain and a roast logged forty seconds ago is
-- invisible, so the operator is handed batches for coffee that is ALREADY
-- ROASTED. That is not a stale number on a screen; it is green coffee down the
-- chute and a shift's plan wrong. The view, whatever it costs, has never been
-- capable of that.
--
-- So this is not a swap. `roast_plan_fresh` returns the stored rows, but first
-- it asks whether anything has changed since they were computed, and recomputes
-- if so. Staleness is NOT "is there a row in roast_plan_dirty" -- the drain
-- deletes only up to a high-water id, so rows can legitimately sit there for a
-- facility whose plan is current. The real question is whether anything was
-- ENQUEUED AFTER the plan was last COMPUTED, which is exact and is
-- self-clearing: once the recompute lands, computed_at moves and the condition
-- is false.
--
-- CONCURRENCY. Without a lock, five concurrent renders of a dirty facility each
-- run their own 650ms recompute -- the same stampede shape that took the site
-- down through unstable_cache. So: take an advisory lock, then ASK AGAIN. The
-- session that waited finds the work already done and skips it. The lock is
-- transaction-scoped and the critical section is one recompute, so it cannot
-- outlive the statement.
--
-- 🔴 SECURITY INVOKER, DELIBERATELY. roast_plan carries an RLS policy scoped to
-- auth_company_ids(), and blendRowsFor passes a facilityId that arrives from
-- CLIENT COMPONENT PROPS with no server-side re-validation
-- (roast/LoadFromQueueButton.tsx). That is safe today for exactly one reason:
-- the relation it reads is INVOKER, so RLS does the filtering. Making this
-- DEFINER to "keep it simple" would turn a parameter the client controls into a
-- cross-tenant read. The staleness probe has to be DEFINER because
-- roast_plan_dirty is readable by nobody but the owner -- so it is split out as
-- its own narrow function that returns one boolean and leaks nothing.

begin;

-- The probe. Owner-privileged because roast_plan_dirty is deliberately
-- unreadable by `authenticated`; it returns a boolean about one facility and
-- discloses no rows.
create or replace function public.roast_plan_stale(p_facility_id text)
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
             (select max(p.computed_at) from public.roast_plan p
               where p.facility_id = p_facility_id),
             '-infinity'::timestamptz)
  );
$function$;

revoke all on function public.roast_plan_stale(text) from public, anon;
grant execute on function public.roast_plan_stale(text) to authenticated, service_role;

-- The reader. INVOKER so the RLS policy on roast_plan does the tenant filtering.
create or replace function public.roast_plan_fresh(p_facility_id text)
returns setof public.roast_plan
language plpgsql
security invoker
set search_path to 'public', 'pg_temp'
as $function$
begin
  if p_facility_id is null then
    return;
  end if;

  if public.roast_plan_stale(p_facility_id) then
    -- One recomputer per facility. hashtext over a prefixed key so this cannot
    -- collide with an advisory lock taken anywhere else for another purpose.
    perform pg_advisory_xact_lock(hashtext('roast_plan_fresh:' || p_facility_id));
    -- Ask again: whoever held the lock was doing precisely this work.
    if public.roast_plan_stale(p_facility_id) then
      perform public.roast_plan_recompute(p_facility_id);
    end if;
  end if;

  return query
    select p.* from public.roast_plan p where p.facility_id = p_facility_id;
end;
$function$;

revoke all on function public.roast_plan_fresh(text) from public, anon;
grant execute on function public.roast_plan_fresh(text) to authenticated, service_role;

do $$
declare
  v_fac   text;
  v_fresh int;
  v_live  int;
begin
  if to_regprocedure('public.roast_plan_fresh(text)') is null then
    raise exception 'roast_plan_fresh(text) is missing';
  end if;
  if to_regprocedure('public.roast_plan_stale(text)') is null then
    raise exception 'roast_plan_stale(text) is missing';
  end if;

  -- 🔴 The one property that makes this safe to put in front of Load From
  -- Queue. If this ever flips to DEFINER, a client-supplied facility id reads
  -- another tenant's plan.
  if (select p.prosecdef from pg_proc p where p.oid = 'public.roast_plan_fresh(text)'::regprocedure) then
    raise exception 'roast_plan_fresh must be SECURITY INVOKER; RLS is the only thing scoping it';
  end if;
  if not (select p.prosecdef from pg_proc p where p.oid = 'public.roast_plan_stale(text)'::regprocedure) then
    raise exception 'roast_plan_stale must be SECURITY DEFINER; roast_plan_dirty is not readable by authenticated';
  end if;

  if not has_function_privilege('authenticated', 'public.roast_plan_fresh(text)', 'execute') then
    raise exception 'authenticated cannot execute roast_plan_fresh';
  end if;

  -- It must agree with the live view, which is the whole point of serving it.
  select f.facility_id into v_fac
    from (select distinct facility_id from public.roast_plan) f limit 1;

  if v_fac is null then
    raise notice 'no stored plan to probe; agreement assertion skipped';
  else
    select count(*) into v_fresh from public.roast_plan_fresh(v_fac);
    select count(*) into v_live  from public.roast_detail_by_blend(v_fac);
    if v_fresh <> v_live then
      raise exception 'roast_plan_fresh returned % rows, the live view %, for facility %',
        v_fresh, v_live, v_fac;
    end if;
    raise notice 'roast_plan_fresh agrees with the live view: % rows', v_fresh;
  end if;
end $$;

commit;
