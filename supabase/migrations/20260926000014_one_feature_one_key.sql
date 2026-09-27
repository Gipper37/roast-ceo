-- Two tables configure the terminal lock. They must admit the same people.
--
-- 20260926000013 gated terminal_role_autolock on `config.parameters`, reasoning
-- that it is a settings table. Its sibling company_terminal_policy — which
-- holds the company-wide autolock the role rows override — is gated on
-- `terminal.manage`, and so is the server action that writes it
-- (updateTerminalPolicy, stratos app/app/(app)/company/actions.ts:1049).
--
-- The two keys do not resolve to the same people:
--
--     terminal.manage     company_admin, facility_admin
--     config.parameters   company_admin, facility_admin, manager, roastery_manager
--
-- So a manager could set a role's override and then be refused when editing the
-- default beneath it — half a screen that works. Worse, the UI for both lives
-- in one card gated on terminal.manage, so the extra grant was reachable only
-- through PostgREST: authority nobody could see and nobody asked for.
--
-- How long a terminal stays unlocked is a security setting, not a preference.
-- It goes to the narrower key, matching its sibling.

begin;

drop policy if exists terminal_role_autolock_write on public.terminal_role_autolock;
create policy terminal_role_autolock_write on public.terminal_role_autolock
  for all to authenticated
  using ((company_id in (select public.auth_company_ids()))
         and public.auth_has_permission('terminal.manage', company_id))
  with check ((company_id in (select public.auth_company_ids()))
              and public.auth_has_permission('terminal.manage', company_id));

do $verify$
declare v_bad int;
begin
  -- The two tables that configure one feature name one key.
  select count(*) into v_bad
    from pg_policies p
   where p.tablename in ('company_terminal_policy', 'terminal_role_autolock')
     and p.cmd in ('ALL', 'INSERT', 'UPDATE', 'DELETE')
     and coalesce(p.with_check, p.qual) not like '%terminal.manage%';
  if v_bad > 0 then
    raise exception '% terminal-config write policy(ies) demand a different key than their sibling', v_bad;
  end if;

  -- And the roles that key admits really exist, or the policy fences nobody.
  select count(*) into v_bad from public.role_permissions rp
   where rp.permission_id = 'terminal.manage' and rp.granted
     and not exists (select 1 from public.user_roles ur where ur.role_id = rp.role_id);
  if v_bad > 0 then raise exception '% grant(s) of terminal.manage name a role that does not exist', v_bad; end if;

  raise notice 'terminal lock configuration is one key: terminal.manage';
end $verify$;

commit;
