-- Logging a roast is a permission the database knows about.
--
-- The last of M11's first phase. Seven roast tables carried tenancy-only
-- policies, so `roast.view` was enough to write over PostgREST: a sales_person
-- or an equipment_tech could insert a roast, rewrite a finished one's charge
-- weight (which re-drives green attribution and COGS), or delete the first-crack
-- event off a curve. Two browser writers had no server-side gate at all — the
-- post-roast quality card and the profile rename, both of which write straight
-- from the client.
--
-- `roast.log` is the key throughout. It is the widest one the roast paths use:
-- everything else that writes these tables (recipe.create, recipe.archive,
-- config.connections, config.import_data) is held by roastmaster and above, and
-- all of those hold roast.log as well. Deliberately NOT split by whether the
-- roast is finished: gating completed rows on roast.edit_completed would refuse
-- an assistant_roaster their own grace-period Restart and their own post-drop
-- weight entry, which is work the app is built to let them do.
--
-- ── Why two set-returning helpers instead of a per-row check ──────────────
-- `company_id in (select public.auth_roast_log_company_ids())` is an InitPlan:
-- Postgres evaluates it ONCE per statement. Writing
-- `auth_has_permission('roast.log', company_id)` directly in the policy would
-- call it once per ROW, and a curve import writes thousands of temperature nodes
-- in one statement. Same rule, one evaluation.
--
-- Reads are untouched: roast.view still sees everything its tenant has.

begin;

create or replace function public.auth_roast_log_company_ids()
returns setof text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select t.company_id
    from public.team t
   where t.auth_user_id = auth.uid()
     and coalesce(t.is_active, true)
     and public.auth_has_permission('roast.log', t.company_id);
$$;

create or replace function public.auth_roast_log_facility_ids()
returns setof text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- A facility of a company the caller may log roasts for. Joined through
  -- facilities so a stale team.facility_id cannot widen it (20260910000011).
  select f.facility_id
    from public.team t
    join public.facilities f
      on f.company_id = t.company_id
   where t.auth_user_id = auth.uid()
     and coalesce(t.is_active, true)
     and public.auth_has_permission('roast.log', t.company_id);
$$;

revoke all on function public.auth_roast_log_company_ids()  from public, anon;
revoke all on function public.auth_roast_log_facility_ids() from public, anon;
grant execute on function public.auth_roast_log_company_ids()  to authenticated, service_role;
grant execute on function public.auth_roast_log_facility_ids() to authenticated, service_role;

comment on function public.auth_roast_log_company_ids() is
  'The caller''s companies in which they may log a roast. Used by the roast write policies as an InitPlan, so the permission is resolved once per statement rather than once per row.';

-- ── company-scoped roast tables ──────────────────────────────────────────
do $$
declare t text;
begin
  foreach t in array array['roast_log', 'roast_sessions', 'roast_smartroast_log'] loop
    execute format('drop policy if exists tenant_company_access on public.%I', t);
    execute format('drop policy if exists %I on public.%I', t || '_read',  t);
    execute format('drop policy if exists %I on public.%I', t || '_write', t);
    execute format(
      'create policy %I on public.%I for select to authenticated '
      'using (company_id in (select public.auth_company_ids()))', t || '_read', t);
    execute format(
      'create policy %I on public.%I for all to authenticated '
      'using (company_id in (select public.auth_roast_log_company_ids())) '
      'with check (company_id in (select public.auth_roast_log_company_ids()))', t || '_write', t);
  end loop;
end $$;

-- ── facility-scoped: the curve itself ────────────────────────────────────
do $$
declare t text;
begin
  foreach t in array array['roast_events', 'roast_temp_nodes'] loop
    execute format('drop policy if exists tenant_facility_access on public.%I', t);
    execute format('drop policy if exists %I on public.%I', t || '_read',  t);
    execute format('drop policy if exists %I on public.%I', t || '_write', t);
    execute format(
      'create policy %I on public.%I for select to authenticated '
      'using (facility_id in (select public.auth_facility_ids()))', t || '_read', t);
    execute format(
      'create policy %I on public.%I for all to authenticated '
      'using (facility_id in (select public.auth_roast_log_facility_ids())) '
      'with check (facility_id in (select public.auth_roast_log_facility_ids()))', t || '_write', t);
  end loop;
end $$;

-- ── scoped through the roast they belong to ──────────────────────────────
drop policy if exists tenant_via_roast_log on public.roast_log_recipes;
drop policy if exists roast_log_recipes_read  on public.roast_log_recipes;
drop policy if exists roast_log_recipes_write on public.roast_log_recipes;

create policy roast_log_recipes_read on public.roast_log_recipes
  for select to authenticated
  using (roast_log_id in (select rl.roast_log_id from public.roast_log rl
                           where rl.company_id in (select public.auth_company_ids())));

create policy roast_log_recipes_write on public.roast_log_recipes
  for all to authenticated
  using      (roast_log_id in (select rl.roast_log_id from public.roast_log rl
                                where rl.company_id in (select public.auth_roast_log_company_ids())))
  with check (roast_log_id in (select rl.roast_log_id from public.roast_log rl
                                where rl.company_id in (select public.auth_roast_log_company_ids())));

-- roast_log_lot_consumption has no writer outside the FIFO engine, and that
-- engine runs SECURITY INVOKER inside a roast_log write — so the person whose
-- roast it is must be allowed to log one.
drop policy if exists tenant_company_access             on public.roast_log_lot_consumption;
drop policy if exists roast_log_lot_consumption_read    on public.roast_log_lot_consumption;
drop policy if exists roast_log_lot_consumption_write   on public.roast_log_lot_consumption;

create policy roast_log_lot_consumption_read on public.roast_log_lot_consumption
  for select to authenticated
  using (exists (select 1 from public.roast_log rl
                  where rl.roast_log_id = roast_log_lot_consumption.roast_log_id
                    and rl.company_id in (select public.auth_company_ids())));

create policy roast_log_lot_consumption_write on public.roast_log_lot_consumption
  for all to authenticated
  using      (exists (select 1 from public.roast_log rl
                       where rl.roast_log_id = roast_log_lot_consumption.roast_log_id
                         and rl.company_id in (select public.auth_roast_log_company_ids())))
  with check (exists (select 1 from public.roast_log rl
                       where rl.roast_log_id = roast_log_lot_consumption.roast_log_id
                         and rl.company_id in (select public.auth_roast_log_company_ids())));

commit;
