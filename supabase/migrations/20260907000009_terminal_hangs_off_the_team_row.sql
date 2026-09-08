-- A terminal is a flag on a login the tenant already has, not a machine account.
--
-- I had this backwards. 20260907000007 bound terminal_device to auth_user_id and
-- made registering a terminal its own act in its own section, on the assumption
-- that a tenant would create a purpose-made machine account. Owner, 2026-09-07:
-- "orders@socialhour and wsorders@mcr would be the terminal enabled account …
-- on the team section you could toggle to a terminal enabled login. or on
-- creating you could do the same."
--
-- That is the real shape. These roasteries already run shared mailbox-style
-- logins that sit on a machine all day, and the useful act is not "create a
-- terminal", it is "this existing login is a shared terminal". Which also
-- settles the seat question the owner answered in the same breath — yes, it
-- goes against their seats, because it IS one of their logins. Nothing to
-- change there: a terminal row is login_kind 'account' and already counted.
-- (Floor staff stay exempt; they hold no login at all.)
--
-- So the device hangs off the TEAM ROW, not the auth account:
--
--   * A terminal can be set up before the invite is accepted, which auth_user_id
--     made impossible — it is NOT NULL and does not exist until acceptance. With
--     team_member_id the flag can be flipped on the row the moment it is created,
--     which is what "or on creating you could do the same" needs.
--   * The identity guarantee is unchanged. current_terminal_device() still
--     resolves through auth.uid() — now via team.auth_user_id — so a terminal
--     still proves what it is by who it is signed in as, and a client still
--     cannot claim to be one by passing an id it chose.
--   * A team row whose invite is unaccepted simply resolves to no device until
--     somebody signs in as it. Nothing to reconcile.
--
-- Safe to restructure rather than migrate carefully: terminal_device has never
-- been on prod and staging holds one test row.

begin;

-- Sessions reference the device, so they go with the restructure.
delete from public.terminal_actor_session;
delete from public.terminal_device;

alter table public.terminal_device
  drop column auth_user_id;

alter table public.terminal_device
  add column team_member_id text not null
    references public.team(team_member_id) on delete cascade;

create unique index uq_terminal_device_member on public.terminal_device (team_member_id);

comment on column public.terminal_device.team_member_id is
  'The login this machine stays signed in as, as a team row rather than an auth account — so a terminal can be flagged before the invite is accepted. Resolution still runs through auth.uid() via team.auth_user_id.';

comment on table public.terminal_device is
  'A login marked as a shared terminal. Not a separate kind of account: these are the tenant''s own logins (an orders@ or wsorders@ that lives on a machine), so they count against the seat cap like any other. Identity still proven by auth.uid(), never by a client-supplied id.';

-- ── Which machine am I ──────────────────────────────────────────────────────
create or replace function public.current_terminal_device()
returns public.terminal_device
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select d.*
    from public.terminal_device d
    join public.team t on t.team_member_id = d.team_member_id
   where t.auth_user_id = auth.uid()
     and coalesce(t.is_active, true)
     and d.is_active;
$$;

-- ── Turn a login into a terminal, or turn it back ───────────────────────────
-- One call for both directions, because it is one toggle in the UI. Enabling
-- twice just renames; disabling keeps the row so the history of what happened
-- at that machine survives being switched off.
create or replace function public.set_terminal_enabled(
  p_team_member_id text,
  p_enabled        boolean,
  p_label          text default null,
  p_facility_id    text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_company text; v_name text; v_kind text; v_facility text;
begin
  select company_id, name, login_kind, facility_id
    into v_company, v_name, v_kind, v_facility
    from public.team
   where team_member_id = p_team_member_id and coalesce(is_active, true);

  if v_company is null then
    raise exception 'No such team member.' using errcode = 'no_data_found';
  end if;
  if not public.auth_has_permission('terminal.manage', v_company) then
    raise exception 'You do not have permission to change terminals.' using errcode = 'insufficient_privilege';
  end if;
  -- Floor staff have no login, so there is nothing for a machine to sign in as.
  if v_kind = 'pin_only' then
    raise exception 'Floor staff have no login, so they cannot be a terminal. Use a login your team already signs in with.'
      using errcode = 'check_violation';
  end if;

  if not p_enabled then
    update public.terminal_device set is_active = false where team_member_id = p_team_member_id;
    -- Whoever was PIN'd in there is done; the machine is no longer a terminal.
    update public.terminal_actor_session
       set ended_at = now(), ended_reason = 'signed_out'
     where team_member_id in (select team_member_id from public.team where company_id = v_company)
       and device_id in (select device_id from public.terminal_device where team_member_id = p_team_member_id)
       and ended_at is null;
    return;
  end if;

  insert into public.terminal_device
    (company_id, facility_id, label, team_member_id, is_active, registered_by)
  values (
    v_company,
    coalesce(p_facility_id, v_facility),
    coalesce(nullif(trim(p_label), ''), v_name, 'Terminal'),
    p_team_member_id,
    true,
    coalesce(nullif(auth.jwt() ->> 'email', ''), auth.uid()::text)
  )
  on conflict (team_member_id) do update
     set is_active   = true,
         label       = coalesce(nullif(trim(p_label), ''), public.terminal_device.label),
         facility_id = coalesce(p_facility_id, public.terminal_device.facility_id);
end;
$$;

-- register_terminal_device is superseded by the toggle: same act, one concept
-- fewer. Removed rather than left as a second way to do the same thing.
drop function if exists public.register_terminal_device(text, text, text);

revoke all on function public.set_terminal_enabled(text, boolean, text, text) from public;
grant execute on function public.set_terminal_enabled(text, boolean, text, text) to authenticated;

commit;
