-- A roastery manager runs the floor, and a bagger can record what is on it.
--
-- Groundwork for the in-stock count prompt. Nothing in the frontend may name a
-- permission key before it exists — an unknown key resolves to denied for every
-- role, silently — so the role, the keys and the settings land here first.
--
-- ── THE NEW ROLE ───────────────────────────────────────────────────────
-- The brief was "roastery manager, probably a mix of roastmaster and manager".
-- Taken literally that is just `manager`: on prod, manager's 107 granted keys
-- are a strict SUPERSET of roastmaster's 50, and the roastmaster-only set is
-- EMPTY. A union produces a second copy of manager, including all 12 Payments
-- keys and team.role_edit.
--
-- So the role is defined by SUBTRACTION: everything roastmaster has, plus the
-- floor-operations slice of manager's delta. Deliberately NOT included —
--   Payments (12 keys)   charge card, refund, void invoice, late fees
--   Team admin (4)       invite, role_edit, archive, facility_assign
--   Accounting, shop configuration, customer merge, inventory.void
--
-- Two of the additions reverse an explicit granted=false on roastmaster, so
-- they are decisions rather than mechanical adds:
--   reports.view      INCLUDED. A floor leader who cannot see production
--                     reporting cannot do the job.
--   inventory.archive EXCLUDED. Destructive, and nothing about running a roast
--                     day needs it.
--
-- Two additions are inert today and included anyway, because they are correct
-- and will switch on with the module: team.floor_staff and recall.exercise both
-- carry feature_key='haccp', and no tenant has haccp enabled, so
-- auth_has_permission's module switch denies them to everybody right now.
--
-- ── WHY staff GETS roast_stock.edit ────────────────────────────────────
-- `staff` is the role a bagger or warehouse person actually holds, and it does
-- NOT hold roast_stock.edit. That is not a new problem: /app/roast gates on
-- roast.view, which staff HAS, and InStockTable has no permission gate at all —
-- so a staff user can already open the In Stock editor, type a count, and take
-- a 403 from requirePermission on save. A prompt asking them to count would
-- have nagged people who are powerless to satisfy it.
--
-- ── WHY roast_stock.delete IS SPLIT OUT ────────────────────────────────
-- roast_stock_log's INSERT, UPDATE and DELETE policies all resolve the SAME key.
-- Granting staff the ability to record a count would therefore also grant them
-- DELETE on the count ledger. Nothing in the app deletes a row, but the policy
-- is reachable through PostgREST. Deleting a count is a supervisor act.
--
-- ── THE SETTINGS ───────────────────────────────────────────────────────
-- Two facility-scoped parameters. `bin_card_surface` shipped with a NULL
-- data_type and renders wrong because of it; these carry data_type and, for the
-- text one, a text_value default, so Settings renders them as what they are.

begin;

-- ── 1. The role exists before anything references it ───────────────────
insert into public.user_roles (role_id, role_name, sort_order)
values ('roastery_manager', 'Roastery Manager', 4)
on conflict (role_id) do update set role_name = excluded.role_name;

-- Display order: slot it above roastmaster, push the rest down.
update public.user_roles set sort_order = sort_order + 1
 where role_id in ('roastmaster','assistant_roaster','staff','sales_person','accounting_admin','accounting_view')
   and sort_order >= 4;

-- ── 2. The seniority ladder ────────────────────────────────────────────
-- 🔴 role_rank is a hardcoded CASE ending `else 99`, and 99 is not merely
-- junior: guard_team_privileged_columns and guard_invitation_rank both raise
-- when target_rank <= actor_rank, so an unlisted role can act on NOBODY and
-- everybody can act on it. A new role that is not added here is silently inert.
-- Body reproduced from pg_get_functiondef with one row inserted and the tail
-- renumbered; the comparisons are all relative, so renumbering is safe.
-- 🔴 lib/permissions/constants.ts ROLE_HIERARCHY must be renumbered identically
-- in the same release.
create or replace function public.role_rank(p_role text)
 returns integer
 language sql
 immutable
as $function$
  select case p_role
    when 'company_admin'     then 0
    when 'facility_admin'    then 1
    when 'manager'           then 2
    when 'roastery_manager'  then 3
    when 'roastmaster'       then 4
    when 'equipment_tech'    then 5
    when 'assistant_roaster' then 6
    when 'sales_person'      then 7
    when 'staff'             then 8
    when 'accounting_admin'  then 9
    when 'accounting_view'   then 10
    else 99 end;
$function$;

-- ── 3. Two new keys ────────────────────────────────────────────────────
insert into public.permissions (permission_id, category, label, description, is_plan_gated, sort_order)
values
  ('roast_stock.delete', 'Roasting', 'Delete a recorded stock count',
   'Remove a count from the roasted-stock ledger. Recording a count is roast_stock.edit; erasing one is a supervisor act.',
   false, 61),
  ('roast_stock.prompt_dismiss', 'Roasting', 'Dismiss the stock count prompt',
   'Close the "record what is on the shelf" prompt without counting. Without this the prompt can only be satisfied by recording a count.',
   false, 62)
on conflict (permission_id) do update
  set category = excluded.category, label = excluded.label, description = excluded.description;

-- Neither is plan-gated, matching roast_stock.edit. Healthy stock data is not a
-- premium feature, and a plan-gated key that a policy still demands is a silent
-- denial for every role on the wrong plan.

-- ── 4. Who holds what ──────────────────────────────────────────────────
-- roastery_manager starts from roastmaster's granted set...
insert into public.role_permissions (role_id, permission_id, granted)
select 'roastery_manager', rp.permission_id, true
  from public.role_permissions rp
 where rp.role_id = 'roastmaster' and rp.granted
on conflict (role_id, permission_id) do update set granted = excluded.granted;

-- ...plus the floor-operations slice of manager's delta.
insert into public.role_permissions (role_id, permission_id, granted)
select 'roastery_manager', k, true
  from (values
    ('config.parameters'),            -- reaches the Settings toggle this feature ships
    ('config.restock_category'),
    ('config.roaster_unit.archive'),
    ('config.smartroast'),
    ('equipment.create'), ('equipment.edit'), ('equipment.archive'), ('equipment.admin'),
    ('delivery.view'),
    ('recall.exercise'),              -- inert until haccp is on
    ('team.floor_staff'),             -- inert until haccp is on; the reason the role exists
    ('reports.view')                  -- reverses roastmaster's explicit denial, deliberately
  ) as t(k)
 where exists (select 1 from public.permissions p where p.permission_id = t.k)
on conflict (role_id, permission_id) do update set granted = excluded.granted;

-- The new keys.
insert into public.role_permissions (role_id, permission_id, granted)
select r, k, true from (values
    ('company_admin','roast_stock.delete'), ('facility_admin','roast_stock.delete'),
    ('manager','roast_stock.delete'),       ('roastery_manager','roast_stock.delete'),
    ('company_admin','roast_stock.prompt_dismiss'), ('facility_admin','roast_stock.prompt_dismiss'),
    ('manager','roast_stock.prompt_dismiss'), ('roastery_manager','roast_stock.prompt_dismiss'),
    ('roastmaster','roast_stock.prompt_dismiss')
  ) as t(r,k)
on conflict (role_id, permission_id) do update set granted = excluded.granted;

-- A bagger can record what is on the shelf.
insert into public.role_permissions (role_id, permission_id, granted)
values ('staff', 'roast_stock.edit', true)
on conflict (role_id, permission_id) do update set granted = true;

-- ── 5. Erasing a count is no longer the same authority as recording one ─
drop policy if exists roast_stock_log_write_delete on public.roast_stock_log;
create policy roast_stock_log_write_delete on public.roast_stock_log
  for delete to authenticated
  using ((company_id in (select public.auth_company_ids()))
         and public.auth_has_permission('roast_stock.delete', company_id));

-- ── 6. The settings ────────────────────────────────────────────────────
insert into public.standard_parameters (parameters_id, parameter, amount, text_value, data_type)
values
  ('stock_count_prompt', 'Ask for a roasted-stock count', null, 'weekly', 'text'),
  ('stock_count_threshold_weeks', 'Stop believing the stock estimate above (weeks of roasting)', 2.0, null, 'number')
on conflict (parameters_id) do update
  set parameter = excluded.parameter, data_type = excluded.data_type;

-- 2.0 weeks is measured, not chosen. Across 30 healthy facility-weeks on prod
-- the highest credible reading was 1.5 weeks of shelf; the tenant whose
-- deliveries are half-unrecorded sits at 3.6-4.2 and never dropped below 1.31.
-- The effective threshold is GREATEST(this, 1 + backstock_buffer_pct/100), so a
-- roastery deliberately holding a week of backstock is not nagged for it.

do $verify$
declare v_bad int; v_rm int; v_rmaster int;
begin
  -- The role is registered everywhere the DATABASE can check.
  if not exists (select 1 from public.user_roles where role_id='roastery_manager') then
    raise exception 'roastery_manager is missing from user_roles';
  end if;
  if public.role_rank('roastery_manager') = 99 then
    raise exception 'roastery_manager is not in role_rank, so it can act on nobody';
  end if;
  if public.role_rank('roastery_manager') >= public.role_rank('roastmaster') then
    raise exception 'roastery_manager must outrank roastmaster';
  end if;
  if public.role_rank('roastery_manager') <= public.role_rank('manager') then
    raise exception 'roastery_manager must not outrank manager';
  end if;

  -- Every rank is distinct, or the guards compare two roles as equals.
  select count(*) into v_bad from (
    select public.role_rank(role_id) r from public.user_roles group by 1 having count(*) > 1) x;
  if v_bad > 0 then raise exception '% role rank(s) are shared by more than one role', v_bad; end if;

  -- It holds everything roastmaster holds. Stated as the rule, not as a count.
  select count(*) into v_bad
    from public.role_permissions rm
   where rm.role_id='roastmaster' and rm.granted
     and not exists (select 1 from public.role_permissions n
                      where n.role_id='roastery_manager' and n.permission_id=rm.permission_id and n.granted);
  if v_bad > 0 then raise exception 'roastery_manager is missing % key(s) that roastmaster holds', v_bad; end if;

  -- And it holds NOTHING that moves money or changes who people are.
  select count(*) into v_bad
    from public.role_permissions n join public.permissions p on p.permission_id = n.permission_id
   where n.role_id='roastery_manager' and n.granted
     and (p.category in ('Payments','Accounting')
          or n.permission_id in ('team.invite','team.role_edit','team.archive','team.facility_assign',
                                 'inventory.void','inventory.archive','shop.configure','customer.merge'));
  if v_bad > 0 then
    raise exception 'roastery_manager holds % key(s) it must never hold', v_bad;
  end if;

  -- A bagger can record a count but cannot erase one.
  if not exists (select 1 from public.role_permissions
                  where role_id='staff' and permission_id='roast_stock.edit' and granted) then
    raise exception 'staff cannot record a count, so the prompt would be a dead end for them';
  end if;
  if exists (select 1 from public.role_permissions
              where role_id='staff' and permission_id='roast_stock.delete' and granted) then
    raise exception 'staff must not be able to erase a count';
  end if;

  -- 🔴 A key and the policy that demands it must admit the same roles. The
  -- DELETE policy now names roast_stock.delete; every role granted it must
  -- exist, or the policy is enforced against nobody.
  select count(*) into v_bad
    from public.role_permissions rp
   where rp.permission_id in ('roast_stock.delete','roast_stock.prompt_dismiss')
     and not exists (select 1 from public.user_roles ur where ur.role_id = rp.role_id);
  if v_bad > 0 then raise exception '% grant(s) name a role that does not exist', v_bad; end if;

  select count(*) into v_rm from public.role_permissions where role_id='roastery_manager' and granted;
  select count(*) into v_rmaster from public.role_permissions where role_id='roastmaster' and granted;
  raise notice 'roastery_manager holds % key(s) (roastmaster holds %); staff can now record a count; erasing one is its own key',
    v_rm, v_rmaster;
end $verify$;

commit;
