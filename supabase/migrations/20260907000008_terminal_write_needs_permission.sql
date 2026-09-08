-- Tighten two write policies I shipped too loosely an hour ago.
--
-- 20260907000006 and ...07 scoped company_terminal_policy and terminal_device
-- writes to "any member of the owning company", which is the codebase's usual
-- RLS shape. It is the wrong shape for these two tables, because the server
-- action's requirePermission is not the only way in: both are ordinary tables
-- over PostgREST, so any authenticated member could PATCH them directly.
--
-- What that let a staff account do: drop pin_length to 4 and lockout_threshold
-- to its floor, weakening every PIN in the company; or retire the roast bay
-- terminal mid-shift. Neither is something the RLS layer should have allowed
-- just because the UI does not offer it.
--
-- auth_has_permission() (added in ...06 for exactly this class of problem)
-- resolves role AND plan, so the policy now says the same thing the settings
-- page says. Reads stay open to the whole company: knowing your terminals are
-- called "Roast bay 1" and "Pack line" is not sensitive, and the lock screen
-- needs it.

begin;

drop policy if exists company_terminal_policy_write on public.company_terminal_policy;
create policy company_terminal_policy_write on public.company_terminal_policy
  for all
  using (
    company_id in (select auth_company_ids())
    and public.auth_has_permission('terminal.manage', company_id)
  )
  with check (
    company_id in (select auth_company_ids())
    and public.auth_has_permission('terminal.manage', company_id)
  );

drop policy if exists terminal_device_write on public.terminal_device;
create policy terminal_device_write on public.terminal_device
  for all
  using (
    company_id in (select auth_company_ids())
    and public.auth_has_permission('terminal.manage', company_id)
  )
  with check (
    company_id in (select auth_company_ids())
    and public.auth_has_permission('terminal.manage', company_id)
  );

commit;
