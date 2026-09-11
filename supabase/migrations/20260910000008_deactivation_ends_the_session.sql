-- Deactivating a person ends their session — and an admin can deactivate again.
--
-- 20260908000034 narrowed the UPDATE grant on team to the nine columns a
-- person edits about themselves. Right for the self-service hole it closed;
-- wrong by omission for everyone else: a company admin changing a role, a
-- facility, a job title or is_active now gets "permission denied for table
-- team" (reproduced on staging as the owner's own login). The pending release
-- would have shipped that. Postgres grants are per role, not per policy —
-- `authenticated` is the admin and the person alike — so the grant must be
-- the union of what either may touch, and the trigger plus the policies
-- decide who may touch which. The two columns that stay revoked are the ones
-- no application path writes from a user client: company_id and auth_user_id
-- (the dev portal and the accept route move those, on the service role).
--
-- Two things the audit found about deactivation, closed here:
--   * is_active was not on the guard's list, so an archived person could
--     PATCH themselves back to active through team_self_update. Now nobody
--     changes their own is_active.
--   * Flipping is_active revoked nothing. The person kept a full app for the
--     rest of their 30-day (web) / 90-day (desktop) sliding session. Deleting
--     their auth.sessions rows makes GoTrue refuse the token on the very next
--     request (proved on staging: /auth/v1/user → 403 session_not_found).
--     Done by trigger, so every path — the action, a PATCH, the dev portal —
--     ends the session; skipped while the person is still active somewhere
--     else, because that membership then decides.
--
-- Prod today: 0 inactive members with a login, 0 people with two team rows.

begin;

-- ── 1. the grant an admin needs ───────────────────────────────────────────
grant update (role, is_active, job_title, department, shift, started_on, reports_to)
  on public.team to authenticated;

-- ── 2. nobody flips their own is_active ───────────────────────────────────
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

  -- Whether you are still here is not yours to decide.
  if new.is_active is distinct from old.is_active and v_is_self then
    raise exception 'You cannot change your own active status.'
      using errcode = 'insufficient_privilege';
  end if;

  return new;
end;
$$;

comment on function public.guard_team_privileged_columns() is
  'Nobody moves themselves between companies; moving somebody else needs admin of both ends. Nobody changes their own role or their own is_active, and nobody grants a role at or above their own. Enforced here because team_self_update restricts the row, not the columns.';

-- ── 3. the session ends when access ends ──────────────────────────────────
-- Owned by postgres, which holds DELETE on auth.sessions; refresh tokens go
-- with the session (ON DELETE CASCADE). GoTrue checks the session_id claim of
-- every access token against this table, so the very next request is refused.
create or replace function public.end_sessions_when_access_ends()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid    uuid;
  v_member text;
begin
  if tg_op = 'DELETE' then
    v_uid := old.auth_user_id; v_member := old.team_member_id;
  else
    if not (coalesce(old.is_active, true) and new.is_active = false) then
      return new;
    end if;
    v_uid := new.auth_user_id; v_member := new.team_member_id;
  end if;

  if v_uid is null then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  -- Still active somewhere else? The login stays; that membership decides.
  if exists (
    select 1 from public.team t
     where t.auth_user_id = v_uid
       and coalesce(t.is_active, true)
       and t.team_member_id <> v_member
  ) then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  delete from auth.sessions s where s.user_id = v_uid;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function public.end_sessions_when_access_ends() from public, anon, authenticated;

drop trigger if exists zz_end_sessions_when_access_ends on public.team;
create trigger zz_end_sessions_when_access_ends
  after update of is_active or delete on public.team
  for each row execute function public.end_sessions_when_access_ends();

comment on function public.end_sessions_when_access_ends() is
  'When a person''s last active membership is deactivated or deleted, their auth sessions are deleted, so the next request is refused instead of the next 30 to 90 days being honoured.';

commit;
