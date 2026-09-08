-- A shared machine knows which terminal it is, and who is standing at it.
--
-- The shape, and why. A terminal is not a person: it is a machine in the
-- roastery signed in permanently as a low-privilege account the tenant created
-- through the normal invite flow. The device row binds that ACCOUNT to a
-- labelled place ("Roast bay 1"), which means a terminal identifies itself by
-- who it is logged in as — auth.uid() — and cannot be spoofed by a client
-- passing an id it chose. That is the whole reason auth_user_id is unique here.
--
-- On top of the device sits the actor: the person who tapped their name and
-- entered their PIN. Every record written while that session is open is theirs.
-- Costco GMP 11.1.1 (critical) wants sanitation records showing tasks completed
-- "and by whom", 4.1.12 wants the performer on the record, and 21 CFR 117.305
-- requires the person. Owner, 2026-09-07: the roast logger is a terminal from
-- day one, "roasters sometimes rotate each day".
--
-- Two deliberate choices that will look strange later, so they are written down:
--
--   * `actor_name` is a SNAPSHOT, copied at pin-in. A record that says who did
--     the work must still say it after the person is renamed, and the FK is
--     ON DELETE RESTRICT so a member who has ever acted cannot be deleted out
--     from under their own history. Archiving (is_active = false) is unaffected
--     and remains the way to retire somebody.
--
--   * The session has a HARD expiry (`session_max_hours`, default 14) as well
--     as the client-side idle autolock. Idle timers die with a crashed browser;
--     a shift boundary does not. Nothing is ever attributed to a session that
--     has run past its cap.
--
-- Autolock during a live roast is a CLIENT rule, deliberately not enforced here:
-- the database cannot tell a roast is in progress without coupling identity to
-- roasting, and a session that outlives its cap must expire even mid-roast.

begin;

-- ── The machine ─────────────────────────────────────────────────────────────
create table public.terminal_device (
  device_id     text primary key default (gen_random_uuid())::text,
  company_id    text not null references public.companies(company_id) on delete cascade,
  facility_id   text references public.facilities(facility_id),
  label         text not null,
  -- The account this machine stays signed in as. Unique: one login is one
  -- terminal, which is what lets the RPCs below trust auth.uid() as the device.
  auth_user_id  uuid not null unique references auth.users(id) on delete cascade,
  is_active     boolean not null default true,
  registered_at timestamptz not null default now(),
  registered_by text,
  last_seen_at  timestamptz
);

create index idx_terminal_device_company on public.terminal_device (company_id) where is_active;

comment on table public.terminal_device is
  'A shared machine, bound to the low-privilege account it stays signed in as. A terminal identifies itself by auth.uid(), never by an id the client supplies.';

alter table public.terminal_device enable row level security;
create policy terminal_device_read on public.terminal_device
  for select using (company_id in (select auth_company_ids()));
create policy terminal_device_write on public.terminal_device
  for all using (company_id in (select auth_company_ids()))
  with check (company_id in (select auth_company_ids()));

-- ── Who is standing at it ───────────────────────────────────────────────────
create table public.terminal_actor_session (
  session_id     text primary key default (gen_random_uuid())::text,
  company_id     text not null references public.companies(company_id) on delete cascade,
  device_id      text not null references public.terminal_device(device_id) on delete cascade,
  team_member_id text not null references public.team(team_member_id) on delete restrict,
  actor_name     text not null,           -- snapshot; survives a rename
  actor_title    text,                    -- snapshot; the audit form wants name AND title
  started_at     timestamptz not null default now(),
  expires_at     timestamptz not null,
  ended_at       timestamptz,
  ended_reason   text check (ended_reason in ('signed_out', 'replaced', 'expired'))
);

-- One open session per device, enforced by the database rather than by hope.
create unique index uq_terminal_open_session
  on public.terminal_actor_session (device_id) where ended_at is null;
create index idx_terminal_session_member
  on public.terminal_actor_session (team_member_id, started_at desc);

comment on table public.terminal_actor_session is
  'Who was PIN''d in at a terminal, and when. actor_name/actor_title are snapshots so the record still names the person after a rename; the member FK is ON DELETE RESTRICT so acted-upon history cannot be deleted away.';

alter table public.terminal_actor_session enable row level security;
create policy terminal_actor_session_read on public.terminal_actor_session
  for select using (company_id in (select auth_company_ids()));
-- No write policies: sessions are opened and closed only by the functions below,
-- so a client cannot forge a session claiming to be somebody else.
revoke insert, update, delete on public.terminal_actor_session from anon, authenticated;

-- ── Registering a machine ───────────────────────────────────────────────────
create or replace function public.register_terminal_device(
  p_team_member_id text,   -- the account the machine will stay signed in as
  p_label          text,
  p_facility_id    text default null
)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_company text; v_auth uuid; v_id text;
begin
  select company_id, auth_user_id into v_company, v_auth
    from public.team where team_member_id = p_team_member_id and coalesce(is_active, true);

  if v_company is null then
    raise exception 'No such team member.' using errcode = 'no_data_found';
  end if;
  if v_auth is null then
    raise exception 'That person has no login, so a terminal cannot run as them. Create a login for the terminal first.'
      using errcode = 'check_violation';
  end if;
  if not public.auth_has_permission('terminal.manage', v_company) then
    raise exception 'You do not have permission to register a terminal.' using errcode = 'insufficient_privilege';
  end if;
  if coalesce(trim(p_label), '') = '' then
    raise exception 'Give the terminal a name people will recognise, like "Roast bay 1".' using errcode = 'check_violation';
  end if;

  insert into public.terminal_device (company_id, facility_id, label, auth_user_id, registered_by)
  values (v_company, p_facility_id, trim(p_label), v_auth,
          coalesce(nullif(auth.jwt() ->> 'email', ''), auth.uid()::text))
  on conflict (auth_user_id) do update
     set label = excluded.label, facility_id = excluded.facility_id, is_active = true
  returning device_id into v_id;

  return v_id;
end;
$$;

-- ── The device asks: which machine am I? ────────────────────────────────────
create or replace function public.current_terminal_device()
returns public.terminal_device
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select d.* from public.terminal_device d
   where d.auth_user_id = auth.uid() and d.is_active;
$$;

-- ── Who may be picked here ──────────────────────────────────────────────────
-- Names and titles of people who hold a PIN, for the lock screen. Only a
-- registered terminal may ask, so a stolen tenant login does not get a staff
-- list it could not already see.
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
     and t.company_id = (select d.company_id from public.terminal_device d
                          where d.auth_user_id = auth.uid() and d.is_active)
   order by t.name;
$$;

-- ── Tap a name, enter a PIN ─────────────────────────────────────────────────
create or replace function public.terminal_pin_in(p_team_member_id text, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_dev    public.terminal_device;
  v_policy public.company_terminal_policy;
  v_check  jsonb;
  v_member record;
  v_id     text;
begin
  v_dev := public.current_terminal_device();
  if v_dev.device_id is null then
    raise exception 'This machine is not registered as a terminal.' using errcode = 'insufficient_privilege';
  end if;

  select team_member_id, name, job_title, company_id into v_member
    from public.team
   where team_member_id = p_team_member_id
     and company_id = v_dev.company_id
     and coalesce(is_active, true);

  -- Verify BEFORE revealing whether the person exists: verify_team_pin already
  -- answers identically either way and burns a comparison, so lean on it.
  v_check := public.verify_team_pin(p_team_member_id, p_pin);
  if not (v_check ->> 'ok')::boolean or v_member.team_member_id is null then
    return coalesce(v_check, jsonb_build_object('ok', false, 'reason', 'invalid'));
  end if;

  v_policy := public.terminal_policy(v_dev.company_id);

  -- Whoever was here is done. 'replaced', not 'signed_out': the record should
  -- say the next person took over rather than implying the last one tidied up.
  update public.terminal_actor_session
     set ended_at = now(), ended_reason = 'replaced'
   where device_id = v_dev.device_id and ended_at is null;

  insert into public.terminal_actor_session
    (company_id, device_id, team_member_id, actor_name, actor_title, expires_at)
  values (
    v_dev.company_id, v_dev.device_id, v_member.team_member_id,
    coalesce(v_member.name, 'Unnamed'), v_member.job_title,
    now() + make_interval(hours => v_policy.session_max_hours)
  )
  returning session_id into v_id;

  update public.terminal_device set last_seen_at = now() where device_id = v_dev.device_id;

  return jsonb_build_object(
    'ok', true,
    'session_id', v_id,
    'team_member_id', v_member.team_member_id,
    'name', v_member.name,
    'job_title', v_member.job_title,
    'must_change', coalesce((v_check ->> 'must_change')::boolean, false),
    'autolock_seconds', v_policy.autolock_seconds
  );
end;
$$;

-- ── Step away ───────────────────────────────────────────────────────────────
create or replace function public.terminal_pin_out()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_dev public.terminal_device;
begin
  v_dev := public.current_terminal_device();
  if v_dev.device_id is null then return; end if;
  update public.terminal_actor_session
     set ended_at = now(), ended_reason = 'signed_out'
   where device_id = v_dev.device_id and ended_at is null;
end;
$$;

-- ── Who is acting right now ─────────────────────────────────────────────────
-- THE function every record-writing path will call to stamp an actor. Returns
-- null when nobody is PIN'd in or the session ran past its cap, and closes an
-- expired session on the way past so the state is self-healing.
create or replace function public.current_terminal_actor()
returns table (team_member_id text, actor_name text, actor_title text, session_id text, expires_at timestamptz)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare v_dev public.terminal_device;
begin
  v_dev := public.current_terminal_device();
  if v_dev.device_id is null then return; end if;

  return query
    select s.team_member_id, s.actor_name, s.actor_title, s.session_id, s.expires_at
      from public.terminal_actor_session s
     where s.device_id = v_dev.device_id
       and s.ended_at is null
       and s.expires_at > now();
end;
$$;

-- A separate, VOLATILE sweeper: `current_terminal_actor` is STABLE so it cannot
-- write. Call this from a cron or on pin-in; correctness never depends on it,
-- because every reader already filters on expires_at.
create or replace function public.expire_terminal_sessions()
returns integer
language sql
security definer
set search_path = public, pg_temp
as $$
  with done as (
    update public.terminal_actor_session
       set ended_at = expires_at, ended_reason = 'expired'
     where ended_at is null and expires_at <= now()
    returning 1
  )
  select count(*)::int from done;
$$;

-- ── Permission ──────────────────────────────────────────────────────────────
insert into public.permissions
  (permission_id, category, label, description, default_deny_message, is_plan_gated, sort_order)
values (
  'terminal.manage',
  'Team',
  'Manage shared terminals',
  'Register a machine as a shared terminal, name it, and retire it. People sign in to a terminal with a PIN so every record says who did the work.',
  'You don''t have permission to do that. Contact your administrator if you need access.',
  true,
  1
)
on conflict (permission_id) do nothing;

insert into public.plan_permissions (plan_id, permission_id, granted, updated_reason)
values
  ('starter',         'terminal.manage', false, 'Shared terminals are part of the enterprise_plus food-safety module'),
  ('pro',             'terminal.manage', false, 'Shared terminals are part of the enterprise_plus food-safety module'),
  ('enterprise',      'terminal.manage', false, 'Shared terminals are part of the enterprise_plus food-safety module'),
  ('enterprise_plus', 'terminal.manage', true,  'Shared terminals — enterprise_plus')
on conflict (plan_id, permission_id) do update
  set granted = excluded.granted, updated_reason = excluded.updated_reason;

insert into public.role_permissions (role_id, permission_id, granted)
values
  ('company_admin',  'terminal.manage', true),
  ('facility_admin', 'terminal.manage', true)
on conflict (role_id, permission_id) do update set granted = excluded.granted;

revoke all on function public.register_terminal_device(text, text, text) from public;
revoke all on function public.current_terminal_device()                  from public;
revoke all on function public.terminal_roster()                          from public;
revoke all on function public.terminal_pin_in(text, text)                from public;
revoke all on function public.terminal_pin_out()                         from public;
revoke all on function public.current_terminal_actor()                   from public;
revoke all on function public.expire_terminal_sessions()                 from public;
grant execute on function public.register_terminal_device(text, text, text) to authenticated;
grant execute on function public.current_terminal_device()                  to authenticated;
grant execute on function public.terminal_roster()                          to authenticated;
grant execute on function public.terminal_pin_in(text, text)                to authenticated;
grant execute on function public.terminal_pin_out()                         to authenticated;
grant execute on function public.current_terminal_actor()                   to authenticated;

commit;
