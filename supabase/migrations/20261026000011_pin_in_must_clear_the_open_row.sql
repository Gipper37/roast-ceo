-- terminal_pin_in must clear the open row again: a unique index forbids two.
--
-- 20261026000010 narrowed pin_in to end only the row the calling DEVICE named,
-- so that several terminals on one terminal account could each hold their own
-- session. They cannot:
--
--   uq_terminal_open_session
--     UNIQUE (terminal_member_id) WHERE ended_at IS NULL
--
-- One open session per terminal ACCOUNT is an invariant of the schema. With
-- pin_in no longer ending the previous row, the insert that follows it violates
-- that index, so PIN-in FAILED for anyone whose prior session was still open --
-- which is exactly what happened on prod within minutes of the release: a
-- session opened at 19:56 stayed open, and that person could not PIN back in.
--
-- So the clearing step goes back to the whole account, which is the only thing
-- the index allows. p_replace_session stays in the signature -- the frontend
-- passes it and must keep working -- and is now only a hint about which row is
-- expected; the statement ends every open row regardless.
--
-- 🔴 THIS DOES NOT MAKE TERMINALS INDEPENDENT, AND NOTHING AT THIS LAYER CAN.
-- While three devices share one `team` row with is_terminal = true, PIN-in on
-- any of them necessarily signs the others out, because the schema permits
-- exactly one open session per terminal account. Dropping the index is not the
-- answer either: auth_has_permission's terminal clause admits ANY open session
-- at that account, so several concurrent sessions would let the role of
-- whoever else is PIN'd in satisfy a key for everybody.
--
-- The model is one terminal ACCOUNT PER DEVICE. Then this index is correct, the
-- resolver is correct, and auth_has_permission is correct, with nothing dropped
-- and no divergence between the app and the database. Owner, 2026-10-26:
-- "it wasnt the idle lock that was the problem. it was that you didn't set up
-- terminals right. they need to be treated independently."
--
-- terminal_pin_out keeps its p_session scoping from 000010. It is a no-op while
-- the index holds only one row open, it cannot resurrect this failure, and it
-- is already correct for the per-device model.

begin;

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

  -- Every open row for the account. uq_terminal_open_session leaves no choice:
  -- the insert below is unique on (terminal_member_id) where ended_at is null,
  -- so a row left open here makes PIN-in fail outright.
  update public.terminal_actor_session
     set ended_at = now(), ended_reason = 'replaced'
   where terminal_member_id = v_term.team_member_id
     and ended_at is null;

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

revoke all on function public.terminal_pin_in(text, text, uuid) from public;
grant execute on function public.terminal_pin_in(text, text, uuid) to authenticated, service_role;

do $$
declare v_term_count int;
begin
  if to_regprocedure('public.terminal_pin_in(text, text, uuid)') is null then
    raise exception 'terminal_pin_in(text, text, uuid) is missing';
  end if;
  if not has_function_privilege('authenticated', 'public.terminal_pin_in(text, text, uuid)', 'execute') then
    raise exception 'authenticated cannot execute terminal_pin_in(text, text, uuid)';
  end if;

  -- The invariant this release exists to respect. Asserted rather than assumed,
  -- because 000010 assumed the opposite and broke PIN-in on production.
  if not exists (
    select 1 from pg_indexes
     where schemaname = 'public'
       and tablename = 'terminal_actor_session'
       and indexname = 'uq_terminal_open_session'
  ) then
    raise exception 'uq_terminal_open_session is gone; revisit whether pin_in should clear the whole account';
  end if;

  -- Nothing may be left holding two open rows, or the next PIN-in at that
  -- terminal fails the same way.
  select count(*) into v_term_count from (
    select terminal_member_id
      from public.terminal_actor_session
     where ended_at is null
     group by terminal_member_id
    having count(*) > 1
  ) x;
  if v_term_count > 0 then
    raise exception '% terminal account(s) hold more than one open session', v_term_count;
  end if;
end $$;

commit;
