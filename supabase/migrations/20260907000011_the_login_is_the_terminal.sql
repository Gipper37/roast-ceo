-- Drop the device table. A terminal is a flag on a login, full stop.
--
-- Owner, 2026-09-07: "there's no need to verify the device where they are logged
-- in. the user logging in from a device is verification enough. why add an extra
-- step". Correct, and it invalidates the table rather than just its UI.
--
-- terminal_device was carrying: a label, a facility, is_active, last_seen_at,
-- keyed one-to-one on the team row. Every one of those is either already on the
-- team row (facility), a restatement of the toggle (is_active), derivable
-- (last_seen = the newest session), or a second name for something that already
-- has one (label — the login is called "WS Orders"; that IS the terminal's name).
-- Nothing was left that a boolean could not say, so the table was a registry
-- whose only job was to agree with the row next to it.
--
-- Note what does NOT change: the identity guarantee. It never came from the
-- device row — it came from resolving auth.uid() to a team row. That is exactly
-- what it still does, now with one lookup instead of two. A machine proves what
-- it is by which login is signed in on it, which was the owner's point.
--
-- Two physical machines signed in as the same login were already one row before
-- this, so no distinction is lost. If a tenant ever needs to tell two stations
-- apart, the answer is two logins, not a device registry.

begin;

alter table public.team
  add column if not exists is_terminal boolean not null default false;

comment on column public.team.is_terminal is
  'This login is a shared terminal: the machine signed in as it asks for a PIN, and whoever PINs in is the actor on records made there. Still an ordinary login and still counts against the seat cap.';

-- Carry over whatever the device table was asserting.
update public.team t
   set is_terminal = true
  from public.terminal_device d
 where d.team_member_id = t.team_member_id and d.is_active;

-- Sessions hang off the terminal LOGIN now, not a device id.
alter table public.terminal_actor_session
  add column terminal_member_id text references public.team(team_member_id) on delete restrict;

update public.terminal_actor_session s
   set terminal_member_id = d.team_member_id
  from public.terminal_device d
 where d.device_id = s.device_id;

delete from public.terminal_actor_session where terminal_member_id is null;

alter table public.terminal_actor_session
  alter column terminal_member_id set not null;

drop index if exists uq_terminal_open_session;
alter table public.terminal_actor_session drop column device_id;

-- Still one person at a time per terminal login.
create unique index uq_terminal_open_session
  on public.terminal_actor_session (terminal_member_id) where ended_at is null;

comment on column public.terminal_actor_session.terminal_member_id is
  'The terminal LOGIN this session belongs to. ON DELETE RESTRICT: the machine''s history outlives someone deciding it is no longer a terminal.';

drop function if exists public.current_terminal_device();
drop table if exists public.terminal_device;

-- ── Which terminal login am I signed in as ──────────────────────────────────
-- Returns the team row when this login is a terminal, nothing when it is not.
-- One lookup, and the answer is the login itself.
create or replace function public.current_terminal()
returns public.team
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select t.* from public.team t
   where t.auth_user_id = auth.uid()
     and coalesce(t.is_active, true)
     and t.is_terminal;
$$;

-- ── The toggle ──────────────────────────────────────────────────────────────
create or replace function public.set_terminal_enabled(p_team_member_id text, p_enabled boolean)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_company text; v_kind text;
begin
  select company_id, login_kind into v_company, v_kind
    from public.team where team_member_id = p_team_member_id and coalesce(is_active, true);

  if v_company is null then
    raise exception 'No such team member.' using errcode = 'no_data_found';
  end if;
  if not public.auth_has_permission('terminal.manage', v_company) then
    raise exception 'You do not have permission to change terminals.' using errcode = 'insufficient_privilege';
  end if;
  if p_enabled and v_kind = 'pin_only' then
    raise exception 'Floor staff have no login, so they cannot be a terminal. Use a login your team already signs in with.'
      using errcode = 'check_violation';
  end if;

  update public.team set is_terminal = p_enabled where team_member_id = p_team_member_id;

  -- Switching it off ends whoever is PIN'd in there. The past sessions stay.
  if not p_enabled then
    update public.terminal_actor_session
       set ended_at = now(), ended_reason = 'signed_out'
     where terminal_member_id = p_team_member_id and ended_at is null;
  end if;
end;
$$;

drop function if exists public.set_terminal_enabled(text, boolean, text, text);

-- ── Roster, pin in, pin out, current actor — all keyed on the login ─────────
create or replace function public.terminal_roster()
returns table (team_member_id text, name text, job_title text, department text)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select t.team_member_id, t.name, t.job_title, t.department
    from public.team t
    join public.team_pin p on p.team_member_id = t.team_member_id
   where coalesce(t.is_active, true)
     and t.company_id = (public.current_terminal()).company_id
   order by t.name;
$$;

create or replace function public.terminal_pin_in(p_team_member_id text, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_term   public.team;
  v_policy public.company_terminal_policy;
  v_check  jsonb;
  v_member record;
  v_id     text;
begin
  v_term := public.current_terminal();
  if v_term.team_member_id is null then
    raise exception 'This login is not a shared terminal.' using errcode = 'insufficient_privilege';
  end if;

  select team_member_id, name, job_title into v_member
    from public.team
   where team_member_id = p_team_member_id
     and company_id = v_term.company_id
     and coalesce(is_active, true);

  v_check := public.verify_team_pin(p_team_member_id, p_pin);
  if not (v_check ->> 'ok')::boolean or v_member.team_member_id is null then
    return coalesce(v_check, jsonb_build_object('ok', false, 'reason', 'invalid'));
  end if;

  v_policy := public.terminal_policy(v_term.company_id);

  update public.terminal_actor_session
     set ended_at = now(), ended_reason = 'replaced'
   where terminal_member_id = v_term.team_member_id and ended_at is null;

  insert into public.terminal_actor_session
    (company_id, terminal_member_id, team_member_id, actor_name, actor_title, expires_at)
  values (
    v_term.company_id, v_term.team_member_id, v_member.team_member_id,
    coalesce(v_member.name, 'Unnamed'), v_member.job_title,
    now() + make_interval(hours => v_policy.session_max_hours)
  )
  returning session_id into v_id;

  return jsonb_build_object(
    'ok', true, 'session_id', v_id,
    'team_member_id', v_member.team_member_id,
    'name', v_member.name, 'job_title', v_member.job_title,
    'must_change', coalesce((v_check ->> 'must_change')::boolean, false),
    'autolock_seconds', v_policy.autolock_seconds
  );
end;
$$;

create or replace function public.terminal_pin_out()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_term public.team;
begin
  v_term := public.current_terminal();
  if v_term.team_member_id is null then return; end if;
  update public.terminal_actor_session
     set ended_at = now(), ended_reason = 'signed_out'
   where terminal_member_id = v_term.team_member_id and ended_at is null;
end;
$$;

create or replace function public.current_terminal_actor()
returns table (team_member_id text, actor_name text, actor_title text, session_id text, expires_at timestamptz)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare v_term public.team;
begin
  v_term := public.current_terminal();
  if v_term.team_member_id is null then return; end if;
  return query
    select s.team_member_id, s.actor_name, s.actor_title, s.session_id, s.expires_at
      from public.terminal_actor_session s
     where s.terminal_member_id = v_term.team_member_id
       and s.ended_at is null
       and s.expires_at > now();
end;
$$;

revoke all on function public.current_terminal()                     from public;
revoke all on function public.set_terminal_enabled(text, boolean)    from public;
grant execute on function public.current_terminal()                  to authenticated;
grant execute on function public.set_terminal_enabled(text, boolean) to authenticated;

commit;
