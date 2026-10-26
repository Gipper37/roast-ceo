-- A terminal session belongs to ONE device, not to the terminal account.
--
-- MCR runs three physical terminals on a single `team` row with is_terminal =
-- true (Wholesale Orders, roastery_manager). `terminal_actor_session` is keyed
-- only on `terminal_member_id`, so those three devices shared one notion of
-- "who is standing here". Two consequences, both measured on prod 2026-10-26
-- during a roasting shift:
--
--   1. terminal_pin_out() ended EVERY open row for the account. An idle lock on
--      an unattended packing terminal signed the roastmaster out of the roaster.
--      19 sessions in 2.5 hours, all ended, none open while he was working.
--
--   2. terminal_pin_in() ended every open row as 'replaced', so whoever PIN'd in
--      last anywhere became the only PIN'd person. The app resolves the most
--      recent open session (lib/permissions/server.ts), so a `staff` PIN-in on
--      the bagging terminal made the ROASTING terminal resolve as staff, which
--      does not grant roast.log -- while the chip still read "Steven Marquez".
--      Every action came back PERM_DENIED: the DROP that saves a roast, and
--      updateRoastSortOrders, which gates on the same key.
--
-- Both symptoms are one bug, and it is NOT the role model: roastery_manager and
-- roastmaster both grant roast.log. Widening roles would have fixed nothing.
--
-- The device is identified by the session it already owns. terminal_pin_in has
-- always returned session_id; the caller now keeps it in an httpOnly cookie and
-- hands it back, so each device names its own row and touches no other. No new
-- column: the identifier already existed, it was just thrown away.
--
-- Both functions take the id as an OPTIONAL argument and keep their old
-- whole-account behaviour when it is absent, so a client still running the
-- previous build behaves exactly as it does today rather than failing.

begin;

-- A 2-arg and a 3-arg-with-default overload cannot coexist: calling with two
-- arguments would be ambiguous ("function is not unique"). Drop, recreate,
-- re-grant. Nothing stores a reference to these, so there is nothing to update.
drop function if exists public.terminal_pin_in(text, text);
drop function if exists public.terminal_pin_out();

create or replace function public.terminal_pin_in(
  p_team_member_id   text,
  p_pin              text,
  p_replace_session  uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
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

  -- Hand this DEVICE over: close the row this device was holding, and only that
  -- row. With no id we cannot tell the devices apart, so the old behaviour
  -- stands -- that is the pre-fix build, and it must keep working.
  update public.terminal_actor_session
     set ended_at = now(), ended_reason = 'replaced'
   where terminal_member_id = v_term.team_member_id
     and ended_at is null
     and (p_replace_session is null or session_id = p_replace_session);

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
    'autolock_seconds', public.terminal_autolock_seconds(v_term.company_id, v_member.team_member_id)
  );
end;
$function$;

create or replace function public.terminal_pin_out(
  p_session uuid default null
)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_term public.team;
begin
  v_term := public.current_terminal();
  if v_term.team_member_id is null then return; end if;

  -- `terminal_member_id` stays in the predicate even when a session is named, so
  -- a caller cannot end a session belonging to another company's terminal by
  -- guessing its id.
  update public.terminal_actor_session
     set ended_at = now(), ended_reason = 'signed_out'
   where terminal_member_id = v_term.team_member_id
     and ended_at is null
     and (p_session is null or session_id = p_session);
end;
$function$;

revoke all on function public.terminal_pin_in(text, text, uuid) from public;
revoke all on function public.terminal_pin_out(uuid) from public;
grant execute on function public.terminal_pin_in(text, text, uuid) to authenticated, service_role;
grant execute on function public.terminal_pin_out(uuid) to authenticated, service_role;

-- Finding a device's own open row is now a per-request lookup on every terminal
-- page load, so give it an index instead of a scan of the tenant's history.
create index if not exists idx_terminal_actor_session_open
  on public.terminal_actor_session (terminal_member_id, session_id)
  where ended_at is null;

do $$
begin
  -- Assert what the release is FOR, and only that: both functions exist at the
  -- new signature and are still callable by the app's role. A block that
  -- asserts behaviour the design forbids can only ever raise, and a failed
  -- verify rolls the whole release back.
  --
  -- Resolved by TYPE signature via to_regprocedure, not by comparing
  -- pg_get_function_identity_arguments to a string: that function includes the
  -- parameter NAMES ("p_pin text", not "text"), so the string compare this
  -- replaces failed against two functions that were in fact correct.
  if to_regprocedure('public.terminal_pin_in(text, text, uuid)') is null then
    raise exception 'terminal_pin_in(text, text, uuid) is missing';
  end if;
  if to_regprocedure('public.terminal_pin_out(uuid)') is null then
    raise exception 'terminal_pin_out(uuid) is missing';
  end if;

  -- The old no-argument form must be GONE, or `rpc('terminal_pin_out')` is
  -- ambiguous and every lock screen throws instead of locking.
  if to_regprocedure('public.terminal_pin_out()') is not null then
    raise exception 'the no-argument terminal_pin_out() still exists; the call would be ambiguous';
  end if;

  if not has_function_privilege('authenticated', 'public.terminal_pin_out(uuid)', 'execute') then
    raise exception 'authenticated cannot execute terminal_pin_out(uuid)';
  end if;
  if not has_function_privilege('authenticated', 'public.terminal_pin_in(text, text, uuid)', 'execute') then
    raise exception 'authenticated cannot execute terminal_pin_in(text, text, uuid)';
  end if;
end $$;

commit;
