-- A manager can say who is still here.
--
-- Owner, 2026-09-11, choosing between removing the key and widening the policy:
-- "2" — managers should be able to deactivate people.
--
-- team.archive, team.role_edit, team.invite and team.facility_assign are all
-- granted to company_admin, facility_admin AND manager. But the only write
-- policy on public.team was
--     team_admin_write  FOR ALL  USING auth_is_company_admin(company_id)
-- and auth_is_company_admin is true only for role in (company_admin,
-- facility_admin). So a manager held every team key, saw every control, and
-- every write matched ZERO rows — toggleTeamMemberActive turned that into
-- "Only a company admin can change whether a person is active." The key said
-- yes and the database said no.
--
-- The rank rules that actually protect people are already in
-- guard_team_privileged_columns and are untouched: never yourself, and only
-- somebody BELOW your own role (company admins are peers). Ranks are
-- company_admin 0, facility_admin 1, manager 2, roastmaster 3,
-- assistant_roaster 5, sales_person 6, staff 7 — so a manager reaches
-- roastmasters and below, and cannot touch another manager, a facility admin
-- or a company admin.
--
-- What the policy alone would NOT have protected is WHICH columns. The UPDATE
-- right on this table is column-level and grants are per-ROLE, not per-policy
-- (the 20260908000034 lesson), so a manager admitted by the policy would also
-- have been able to rewrite a subordinate's name, email or reports_to. The
-- guard now checks the changed columns against the actor's own keys.

begin;

-- ── The policy: a team key gets you in; the guard decides what you may change
create policy team_manage_write on public.team
  for update to authenticated
  using (
    company_id in (select public.auth_company_ids())
    and (
      public.auth_has_permission('team.archive', company_id)
      or public.auth_has_permission('team.role_edit', company_id)
      or public.auth_has_permission('team.facility_assign', company_id)
    )
  )
  with check (
    company_id in (select public.auth_company_ids())
    and (
      public.auth_has_permission('team.archive', company_id)
      or public.auth_has_permission('team.role_edit', company_id)
      or public.auth_has_permission('team.facility_assign', company_id)
    )
  );

-- ── The guard: column-by-column, against the actor's keys ─────────────────
create or replace function public.guard_team_privileged_columns()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_actor_rank  int;
  v_target_rank int;
  v_is_self     boolean;
  v_changed     text[];
  v_col         text;
begin
  -- Service role, cron and migrations have no JWT. They are already trusted:
  -- the accept route and signup create logins there.
  if auth.uid() is null then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  -- ── INSERT: floor staff and hand-added people, never a login ──────────
  if tg_op = 'INSERT' then
    if new.auth_user_id is not null then
      raise exception 'A login joins a team through an invitation, not by hand.'
        using errcode = 'insufficient_privilege';
    end if;
    v_actor_rank  := public.auth_role_rank(new.company_id);
    v_target_rank := public.role_rank(new.role);
    if not (v_actor_rank = 0 and v_target_rank = 0) and v_target_rank <= v_actor_rank then
      raise exception 'You can only add someone at a role below your own.'
        using errcode = 'insufficient_privilege';
    end if;
    if new.facility_id is not null and not exists (
      select 1 from public.facilities f
       where f.facility_id = new.facility_id and f.company_id = new.company_id) then
      raise exception 'That facility is not part of this company.'
        using errcode = 'insufficient_privilege';
    end if;
    return new;
  end if;

  -- ── DELETE: never yourself, and only below your own role ──────────────
  if tg_op = 'DELETE' then
    if old.auth_user_id is not null and old.auth_user_id = auth.uid() then
      raise exception 'You cannot remove your own account.'
        using errcode = 'insufficient_privilege';
    end if;
    v_actor_rank  := public.auth_role_rank(old.company_id);
    v_target_rank := public.role_rank(old.role);
    if not (v_actor_rank = 0 and v_target_rank = 0) and v_target_rank <= v_actor_rank then
      raise exception 'You can only remove someone below your own role.'
        using errcode = 'insufficient_privilege';
    end if;
    return old;
  end if;

  -- ── UPDATE ────────────────────────────────────────────────────────────
  v_is_self := (old.auth_user_id is not null and old.auth_user_id = auth.uid());

  -- ── A team manager, acting on somebody else ───────────────────────────
  -- team.archive, team.role_edit and team.facility_assign are held by
  -- company_admin, facility_admin AND manager — but the only write policy on
  -- this table was auth_is_company_admin, which is true for the first two
  -- only. So a manager saw the controls, the UPDATE matched zero rows, and
  -- toggleTeamMemberActive reported "only a company admin can do that". The
  -- policy is widened alongside this migration; here the actor's KEYS decide
  -- which columns they may touch, and the rank rules below still decide WHOM.
  --
  -- Column-by-column rather than blanket, because the UPDATE grant on this
  -- table is column-level and per-ROLE (the 20260908000034 lesson): widening
  -- the policy alone would have let a manager rewrite a subordinate's name,
  -- email or reports_to as a side effect of being allowed to deactivate them.
  if not v_is_self and not public.auth_is_company_admin(old.company_id) then
    select coalesce(array_agg(n.key), '{}')
      into v_changed
      from jsonb_each(to_jsonb(new)) n
      join jsonb_each(to_jsonb(old)) o on o.key = n.key
     where n.value is distinct from o.value
       and n.key not in ('updated_at', 'updated_by');

    foreach v_col in array v_changed loop
      if    v_col = 'is_active'
            and public.auth_has_permission('team.archive', old.company_id) then null;
      elsif v_col = 'role'
            and public.auth_has_permission('team.role_edit', old.company_id) then null;
      elsif v_col = 'facility_id'
            and public.auth_has_permission('team.facility_assign', old.company_id) then null;
      else
        raise exception 'You can change whether somebody is still here, their role and their facility — not %.', v_col
          using errcode = 'insufficient_privilege';
      end if;
    end loop;
  end if;

  -- 🔴 WHICH ROASTERY YOU BELONG TO. Never your own, and never one-ended.
  if new.company_id is distinct from old.company_id then
    if v_is_self then
      raise exception 'You cannot move your own account to another company.'
        using errcode = 'insufficient_privilege';
    end if;
    if not public.auth_is_company_admin(old.company_id) then
      raise exception 'Only an admin can move an account out of a company.'
        using errcode = 'insufficient_privilege';
    end if;
    if not public.auth_is_company_admin(new.company_id) then
      raise exception 'Only an admin of that company can move an account into it.'
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  -- Which facility: always one of the company's own, for yourself as for anyone.
  if new.facility_id is distinct from old.facility_id and new.facility_id is not null
     and not exists (
       select 1 from public.facilities f
        where f.facility_id = new.facility_id and f.company_id = new.company_id) then
    raise exception 'That facility is not part of this company.'
      using errcode = 'insufficient_privilege';
  end if;

  -- Identity and privilege columns: admins of that company only.
  if (new.is_terminal   is distinct from old.is_terminal)
  or (new.login_kind    is distinct from old.login_kind)
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

  -- Whether somebody is still here: never your own, and otherwise the rule
  -- role follows — below your own; company admins are peers.
  if new.is_active is distinct from old.is_active then
    if v_is_self then
      raise exception 'You cannot change your own active status.'
        using errcode = 'insufficient_privilege';
    end if;
    v_actor_rank  := public.auth_role_rank(old.company_id);
    v_target_rank := public.role_rank(old.role);
    if not (v_actor_rank = 0 and v_target_rank = 0) and v_target_rank <= v_actor_rank then
      raise exception 'You can only deactivate or reactivate someone below your own role.'
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  return new;
end;

$fn$;

commit;
