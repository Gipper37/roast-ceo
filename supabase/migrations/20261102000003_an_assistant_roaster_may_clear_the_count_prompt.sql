-- An assistant roaster may clear the shelf-count prompt.
--
-- `roast_stock.prompt_dismiss` was granted to company_admin, facility_admin,
-- manager, roastery_manager and roastmaster. `roast.log` -- who may actually
-- work a roast -- is those five PLUS assistant_roaster. So exactly one role
-- could roast and could not make the prompt go away.
--
-- Why that is worse than it sounds. StockCountPromptHost asks the three roasting
-- roles (roastmaster, assistant_roaster, roastery_manager) after a PLANNING
-- action rather than on arrival -- staging a roast, loading from the queue --
-- which is a thing people do WHILE a roast is in the drum. The prompt is a
-- `fixed inset-0` modal at z-50: while it is open nothing behind it is
-- clickable, DROP included. Measured 2026-11-02: a visible nav link with a real
-- bounding box could not be clicked for 8 seconds, and elementFromPoint
-- returned the overlay.
--
-- With the key, "Not now" writes a `stock_count_dismissal` row for the facility
-- and period and `stock_count_status.due` respects it, so one press clears it
-- for everybody at that facility for the week. Without it, StockCountPrompt
-- renders ModalCancelButton instead: a plain close that is client state only
-- (`setOpen(false)`, no row), so the prompt returns on the next full page load.
--
-- 🔴 LATENT, NOT LIVE: 0 active assistant_roasters on prod today (8
-- company_admin, 3 roastmaster, 3 staff, 2 manager, 1 each roastery_manager /
-- sales_person / facility_admin / accounting_admin). This is the first
-- assistant roaster hired walking into it, not a report from the floor.
--
-- 🔴 NO PLAN ROW IS ADDED, DELIBERATELY. `roast_stock.prompt_dismiss` has no
-- `plan_permissions` rows at all, and `planIncludes` FAILS OPEN for a key that
-- is not plan-gated -- so it is currently available on every plan. Adding rows
-- for some plans would newly DENY the others, which is a behaviour change
-- nobody asked for. The display gate is `currentUserCan`, a role question
-- (layout.tsx:100), so the role grant is the whole fix.

begin;

insert into public.role_permissions (role_id, permission_id, granted, updated_by)
values ('assistant_roaster', 'roast_stock.prompt_dismiss', true, 'migration:20261102000003')
on conflict (role_id, permission_id) do update
  set granted      = true,
      deny_message = null,
      updated_at   = now(),
      updated_by   = 'migration:20261102000003';

-- ── Verify ──────────────────────────────────────────────────────────────
-- 🔴 DERIVED, NOT HARDCODED, so it states the invariant rather than a list I
-- typed: every role that may work a roast may also clear the prompt that
-- blocks the screen it works on. Run against prod's rows before this
-- migration it returns `assistant_roaster` and raises; after, it is empty.
-- A block that could only pass would prove nothing.
do $$
declare
  gap text;
  n_roles int;
begin
  select string_agg(r.role_id, ', ' order by r.role_id) into gap
    from public.role_permissions r
   where r.permission_id = 'roast.log' and r.granted
     and not exists (
       select 1 from public.role_permissions d
        where d.role_id = r.role_id
          and d.permission_id = 'roast_stock.prompt_dismiss'
          and d.granted
     );

  if gap is not null then
    raise exception 'may roast but may not dismiss the count prompt: %', gap;
  end if;

  select count(*) into n_roles
    from public.role_permissions
   where permission_id = 'roast_stock.prompt_dismiss' and granted;

  raise notice 'ok: every role that may roast.log may clear the count prompt (% roles hold the key)', n_roles;
end $$;

commit;
