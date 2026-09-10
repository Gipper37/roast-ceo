-- Four holes this release would otherwise open. All found by auditing it, none
-- of them reachable in a way that has happened — which is the point of fixing
-- them before the tag rather than after.

begin;

-- ── 1. pack_run_source: bagging is floor work, unwinding it is not ─────────
-- This is the ONE-UP record a recall walks: which roast batches went into a
-- bag. Its only policy was `for all` on pack.run, which the staff role holds —
-- so anyone who can bag could also UPDATE or DELETE the sourcing of a run
-- already recorded, straight over PostgREST, bypassing every validation
-- close_pack_run performs. Same rule the rest of the module already follows:
-- recording is pack.run, unwinding a signed record is pack.void.
drop policy if exists pack_run_source_write on public.pack_run_source;

create policy pack_run_source_insert on public.pack_run_source
  for insert with check (
    pack_run_id in (
      select pack_run_id from public.pack_run
       where public.auth_has_permission('pack.run', company_id)));

create policy pack_run_source_amend on public.pack_run_source
  for update using (
    pack_run_id in (
      select pack_run_id from public.pack_run
       where public.auth_has_permission('pack.void', company_id)))
  with check (
    pack_run_id in (
      select pack_run_id from public.pack_run
       where public.auth_has_permission('pack.void', company_id)));

create policy pack_run_source_remove on public.pack_run_source
  for delete using (
    pack_run_id in (
      select pack_run_id from public.pack_run
       where public.auth_has_permission('pack.void', company_id)));

-- ── 2. Two functions shipped with PUBLIC (anon) EXECUTE ───────────────────
-- Neither carries a revoke, so the default PUBLIC grant stands and an
-- unauthenticated caller can reach them.
revoke all on function public.terminal_policy(text) from public, anon;
grant execute on function public.terminal_policy(text) to authenticated;

revoke all on function public.next_recall_reference(text, text) from public, anon;
grant execute on function public.next_recall_reference(text, text) to authenticated;

-- ── 3. _record_lot_shortfall took a caller-supplied roast id ──────────────
-- SECURITY DEFINER with no ownership check, so any authenticated caller could
-- write the shortfall ledger for a roast in someone else's company. It is a
-- derived cache — recompute_lot_shortfall_all rebuilds it from first
-- principles — so the damage is limited and self-healing, which is why this is
-- a tightening and not an incident.
--
-- 🔴 The check must NOT be a bare auth_company_ids() test: this runs inside
-- _deduct_origin_fifo, which the drain cron reaches with no auth context at
-- all. So it applies only when there IS a caller to check. And it returns
-- rather than raising — aborting a legitimate roast save to protect a cache
-- would be the worse failure.
create or replace function public._record_lot_shortfall(
  p_roast_log_id text,
  p_origin_id    text,
  p_facility_id  text,
  p_needed       numeric,
  p_allocated    numeric
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_unmet   numeric := coalesce(p_needed, 0) - coalesce(p_allocated, 0);
  v_company text;
begin
  if p_roast_log_id is null or p_origin_id is null or p_facility_id is null then
    return;
  end if;

  select company_id into v_company from public.roast_log where roast_log_id = p_roast_log_id;
  if v_company is null then return; end if;

  -- A real caller may only speak for their own company. No caller (the drain
  -- cron, a replay) is trusted, because it never took an id from a request.
  if auth.uid() is not null and v_company not in (select auth_company_ids()) then
    return;
  end if;

  if v_unmet <= 0.01 then
    delete from public.roast_lot_shortfall
     where roast_log_id = p_roast_log_id
       and origin_id    = p_origin_id
       and facility_id  = p_facility_id;
    return;
  end if;

  insert into public.roast_lot_shortfall as s
    (roast_log_id, origin_id, facility_id, company_id, lbs_unmet, lbs_needed, as_of)
  values (p_roast_log_id, p_origin_id, p_facility_id, v_company,
          round(v_unmet, 4), round(coalesce(p_needed, 0), 4), now())
  on conflict (roast_log_id, origin_id, facility_id) do update
    set lbs_unmet  = excluded.lbs_unmet,
        lbs_needed = excluded.lbs_needed,
        company_id = excluded.company_id,
        as_of      = excluded.as_of;
end;
$$;

-- ── 4. label_data() is SECURITY DEFINER with no permission check ──────────
-- The label SCREEN gates on pack.run; the function behind it did not, so the
-- gate was a UI convention rather than a rule. Company scoping was already
-- there — this adds the permission so the two agree.
-- Clone the DEPLOYED body rather than retyping ~60 lines of jsonb_build_object
-- that four surfaces depend on; pg_get_functiondef guarantees it is identical.
do $mig$
declare v_def text;
begin
  if to_regprocedure('public._label_data_core(text)') is null then
    select pg_get_functiondef(oid) into v_def
      from pg_proc where proname = 'label_data' and pronamespace = 'public'::regnamespace;
    if v_def is null then
      raise exception 'label_data is missing — refusing to wrap nothing.';
    end if;
    v_def := replace(v_def, 'FUNCTION public.label_data(', 'FUNCTION public._label_data_core(');
    if v_def not like '%_label_data_core(%' then
      raise exception 'Could not rename label_data — refusing to guess.';
    end if;
    execute v_def;
  end if;
end
$mig$;

revoke all on function public._label_data_core(text) from public, anon;

create or replace function public.label_data(p_pack_run_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_company text;
  v_out     jsonb;
begin
  select company_id into v_company from public.pack_run where pack_run_id = p_pack_run_id;
  if v_company is null or v_company not in (select auth_company_ids()) then
    return null;
  end if;
  if not public.auth_has_permission('pack.run', v_company) then
    raise exception 'You do not have permission to print labels.' using errcode = 'insufficient_privilege';
  end if;
  select public._label_data_core(p_pack_run_id) into v_out;
  return v_out;
end;
$$;

commit;
