-- An assistant roaster may correct a roast.
--
-- One column, two gates, two different answers. roast_log.charge_weight is
-- writable from two surfaces:
--
--   Edit Roast modal -> updateRoast -> requirePermission('roast.edit_completed')
--   Green Weight card -> a direct PostgREST write, so the only check is the
--                        roast_log_update RLS policy, which resolves
--                        auth_roast_log_company_ids() -> auth_has_permission('roast.log')
--
-- assistant_roaster holds roast.log and did NOT hold roast.edit_completed. So
-- they could already change a charged roast's green weight from the Green
-- Weight card -- firing trg_lot_consumption_recompute and re-costing COGS for
-- the affected origins -- while the same change in the Edit modal was refused.
-- The stricter gate was decorative: the permissive path was one click away on
-- the same screen.
--
-- Owner's ruling, 2026-09-29: unify it, and they CAN update. So the key is
-- granted rather than the RLS predicate tightened. That is the direction that
-- matches what the role has been doing in practice since the Green Weight card
-- shipped, and it makes the modal agree with the database instead of pretending
-- to be stricter than it is.
--
-- NOT granting `roast.edit`. It is a legacy alias: lib/permissions/constants.ts
-- labels it "legacy alias -- keep for now until Phase B sweeps callsites", and
-- it is named by exactly zero call sites. Granting a dead key would be a second
-- key over one action, which is the failure 20260926000014 and 20260929000003
-- were both written to undo.

begin;

insert into public.role_permissions (role_id, permission_id, granted)
values ('assistant_roaster', 'roast.edit_completed', true)
on conflict (role_id, permission_id) do update set granted = true;

do $verify$
declare v_bad int;
begin
  -- The grant landed.
  if not exists (select 1 from public.role_permissions
                  where role_id = 'assistant_roaster'
                    and permission_id = 'roast.edit_completed' and granted) then
    raise exception 'assistant_roaster did not get roast.edit_completed';
  end if;

  -- THE POINT OF THE MIGRATION: every role that can write roast_log through RLS
  -- can also pass the modal's gate. Asserted as the RULE rather than as a list,
  -- so a role added later cannot quietly reopen the split.
  select count(*) into v_bad
    from public.role_permissions rl
   where rl.permission_id = 'roast.log' and rl.granted
     and not exists (select 1 from public.role_permissions re
                      where re.role_id = rl.role_id
                        and re.permission_id = 'roast.edit_completed' and re.granted);
  if v_bad > 0 then
    raise exception '% role(s) can write roast_log but cannot pass the Edit Roast gate', v_bad;
  end if;

  -- And nothing was widened beyond that: a role WITHOUT roast.log must not have
  -- picked up the edit key here.
  select count(*) into v_bad
    from public.role_permissions re
   where re.permission_id = 'roast.edit_completed' and re.granted
     and not exists (select 1 from public.role_permissions rl
                      where rl.role_id = re.role_id
                        and rl.permission_id = 'roast.log' and rl.granted);
  if v_bad > 0 then
    raise exception '% role(s) can edit a completed roast without being able to log one', v_bad;
  end if;
end;
$verify$;

commit;
