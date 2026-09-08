-- Nobody promotes themselves, and nobody promotes anyone above themselves.
--
-- Two separate holes, found by an adversarial review of today's work and
-- verified against prod's catalog and reproduced on staging.
--
-- 1. `team_self_update` (shipped 2026-05-13, four months live) is
--    `FOR UPDATE USING (auth_user_id = auth.uid())` with table-wide UPDATE
--    granted to `authenticated`. It restricts WHICH ROW, not WHICH COLUMNS. So
--    one PATCH of your own row sets `role` to company_admin, and every
--    permission check then reads the row you just rewrote and agrees. Proved on
--    staging as role `authenticated`: "PATCH team SET role=company_admin on my
--    own row -> 1 row updated".
--
-- 2. `updateTeamMemberRole` requires `team.role_edit` and nothing else.
--    ROLE_HIERARCHY exists but lives in the browser: it only filters the
--    dropdown. `team.role_edit` is held by manager as well as the two admin
--    roles, so a manager could set anyone — including themselves — to
--    company_admin through the ordinary server action, no trick required.
--    (Owner, 2026-09-07: "i thought we made it so that admins could only change
--    team member roles that are below them.") The intent was real; it was never
--    enforced anywhere the database could see.
--
-- The rule, enforced here so it holds no matter which path is used — the server
-- action, a direct PostgREST PATCH, or a future surface nobody has written yet:
--
--   * You may never change your OWN role. Not to a higher one, not to a lower
--     one. A promotion is something somebody else does to you, and that is what
--     makes it evidence.
--   * You may only set a role strictly BELOW your own rank, and only on somebody
--     whose current role is also strictly below yours. So a manager cannot touch
--     another manager, and cannot mint an admin.
--   * The columns that decide identity or privilege — is_terminal, login_kind,
--     company_id, auth_user_id — are admin-only. is_terminal is on this list
--     because today's work put it here: without it, one PATCH makes your own
--     login a terminal and every record made there names whoever you PIN in.
--
-- Deliberately NOT covered: is_active and facility_id. Managers legitimately
-- archive and reassign people today (team.archive / team.facility_assign are
-- granted to manager), and quietly taking that away would be a different change
-- wearing a security fix's clothes. Neither is an escalation vector: archiving
-- yourself removes access, it does not add any.
--
-- Service-role and migration writes are untouched: auth.uid() is null for them,
-- and the guard returns immediately.

begin;

create or replace function public.auth_role_rank(p_company_id text)
returns int
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- Mirrors ROLE_HIERARCHY in S/lib/permissions/constants.ts. Lower is more
  -- senior. An unknown or absent role ranks below everything, so it can never
  -- clear the "strictly below me" test.
  select coalesce(min(case t.role
    when 'company_admin'     then 0
    when 'facility_admin'    then 1
    when 'manager'           then 2
    when 'roastmaster'       then 3
    when 'equipment_tech'    then 4
    when 'assistant_roaster' then 5
    when 'sales_person'      then 6
    when 'staff'             then 7
    when 'accounting_admin'  then 8
    when 'accounting_view'   then 9
    else 99 end), 99)
    from public.team t
   where t.auth_user_id = auth.uid()
     and t.company_id = p_company_id
     and coalesce(t.is_active, true);
$$;

create or replace function public.role_rank(p_role text)
returns int
language sql
immutable
as $$
  select case p_role
    when 'company_admin'     then 0
    when 'facility_admin'    then 1
    when 'manager'           then 2
    when 'roastmaster'       then 3
    when 'equipment_tech'    then 4
    when 'assistant_roaster' then 5
    when 'sales_person'      then 6
    when 'staff'             then 7
    when 'accounting_admin'  then 8
    when 'accounting_view'   then 9
    else 99 end;
$$;

create or replace function public.guard_team_privileged_columns()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor_rank int;
  v_is_self    boolean;
begin
  -- Service role, cron and migrations have no JWT. They are already trusted.
  if auth.uid() is null then return new; end if;

  v_is_self := (old.auth_user_id is not null and old.auth_user_id = auth.uid());

  -- Identity and privilege columns: admins of that company only.
  if (new.is_terminal   is distinct from old.is_terminal)
  or (new.login_kind    is distinct from old.login_kind)
  or (new.company_id    is distinct from old.company_id)
  or (new.auth_user_id  is distinct from old.auth_user_id) then
    if not public.auth_is_company_admin(old.company_id) then
      raise exception 'Only an admin can change that about an account.'
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  if new.role is distinct from old.role then
    if v_is_self then
      raise exception 'You cannot change your own role. Ask an admin.'
        using errcode = 'insufficient_privilege';
    end if;
    v_actor_rank := public.auth_role_rank(old.company_id);
    if public.role_rank(new.role) <= v_actor_rank
    or public.role_rank(old.role) <= v_actor_rank then
      raise exception 'You can only change someone to a role below your own.'
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  return new;
end;
$$;

-- Named to run after the existing audit/stamp triggers, which only touch
-- timestamps and have no opinion about any of this.
drop trigger if exists trg_guard_team_privileged on public.team;
create trigger trg_guard_team_privileged
  before update on public.team
  for each row execute function public.guard_team_privileged_columns();

comment on function public.guard_team_privileged_columns() is
  'Nobody changes their own role, and nobody grants a role at or above their own. Enforced here because team_self_update restricts the row, not the columns, so the server action was never the only way in.';

revoke all on function public.auth_role_rank(text) from public;
revoke all on function public.role_rank(text)      from public;
grant execute on function public.auth_role_rank(text) to authenticated;
grant execute on function public.role_rank(text)      to authenticated;

commit;
