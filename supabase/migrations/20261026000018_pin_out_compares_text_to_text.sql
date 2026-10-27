-- terminal_pin_out compared TEXT to UUID, so PIN-out has been dead since 10:15.
--
-- 🔴 I SHIPPED THIS THIS MORNING, in 20261026000010, and it took all day to find.
--
--     terminal_actor_session.session_id  is  text     default (gen_random_uuid())::text
--     terminal_pin_out(p_session         uuid)
--
--     ... and (p_session is null or session_id = p_session);
--
-- The column HOLDS a uuid and is TYPED text. I read the values, assumed the
-- type, and declared the parameter uuid. There is no implicit cast between
-- text and uuid (pg_cast has zero rows for either direction), and no
-- =(text,uuid) operator, so that predicate cannot be resolved.
--
-- 🔴 WHY `p_session is null or` DOES NOT SAVE IT. Operator resolution happens
-- at PARSE ANALYSIS. OR short-circuiting is a runtime property of an already
-- planned expression, so the whole WHERE clause is analysed before any value
-- is looked at. Proven read-only on production:
--     explain (costs off) select 1 from public.terminal_actor_session
--      where (null::uuid is null or session_id = null::uuid);
--     ERROR:  operator does not exist: text = uuid
--
-- 🔴 WHY NOTHING CAUGHT IT. plpgsql only SYNTAX-checks a body at CREATE; it
-- never type-checks the SQL inside. The migration applied clean, its own verify
-- block passed (it asserted the signature EXISTS, which it did), CI was green,
-- and the function was broken on 100% of calls from the moment it shipped.
-- A function that is never called is indistinguishable from one that works.
--
-- 🔴 WHAT IT COST, AND WHY NOBODY REPORTED IT. terminal_pin_out is called when
-- a terminal hands the machine back: the idle autolock and the lock chip
-- (components/terminal/TerminalProvider.tsx:208), and the stale-session sweep
-- on mount (:242). BOTH call sites wrap it in `.catch(() => {})`, because
-- locking the screen must never fail visibly. So the screen locked, the
-- operator saw exactly what they expected, and the DATABASE ROW STAYED OPEN.
--
--     ended_reason = 'signed_out'   36 rows, last at 2026-10-26 10:15:06 HST
--     ended_reason = 'replaced'     still being written
--
-- Sign-outs stop DEAD two minutes after the first logged error. 'replaced'
-- kept working because terminal_pin_in ends rows by terminal_member_id alone --
-- its own p_replace_session uuid parameter is declared and never compared,
-- which is the same mistake sitting one statement away from firing.
--
-- An open row is not cosmetic: resolveIdentity and auth_has_permission both
-- answer "who is standing here" from open sessions, so a terminal that locked
-- still resolved as whoever had PIN'd in. That is the shape of the failure
-- already documented at TerminalProvider.tsx:226-234 -- "the chip said Ryan
-- Hagler while the database had nobody pinned in, and every permission
-- resolved denied".
--
-- THE FIX: the parameter takes the column's type. Both of them, because the
-- unused one in pin_in is a loaded gun.
--
-- 🔴 A parameter TYPE cannot be changed by CREATE OR REPLACE -- that creates an
-- OVERLOAD and leaves the broken one in place, which PostgREST could still
-- resolve. Each must be dropped and recreated, in one transaction.

begin;

drop function if exists public.terminal_pin_out(uuid);

create or replace function public.terminal_pin_out(p_session text default null)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_term public.team;
begin
  v_term := public.current_terminal();
  if v_term.team_member_id is null then
    raise exception 'This login is not a shared terminal.' using errcode = 'insufficient_privilege';
  end if;

  -- Scoped to the device's own row when it names one, as 000010 intended. The
  -- terminal_member_id predicate stays either way, so naming another tenant's
  -- session ends nothing.
  update public.terminal_actor_session
     set ended_at = now(), ended_reason = 'signed_out'
   where terminal_member_id = v_term.team_member_id
     and ended_at is null
     and (p_session is null or session_id = p_session);
end;
$function$;

revoke all on function public.terminal_pin_out(text) from public, anon;
grant execute on function public.terminal_pin_out(text) to authenticated, service_role;

-- The same mistake, one statement from firing: declared uuid, never compared.
-- 000011 reverted pin_in to clearing by terminal_member_id alone (the unique
-- index forbids two open rows), so p_session is only a hint today -- but it is
-- in the signature the frontend calls, and the next person to use it in a
-- predicate inherits this bug.
drop function if exists public.terminal_pin_in(text, text, uuid);

create or replace function public.terminal_pin_in(
  p_team_member_id   text,
  p_pin              text,
  p_replace_session  text default null
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
  -- so a row left open here makes PIN-in fail outright. See 000011.
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

revoke all on function public.terminal_pin_in(text, text, text) from public, anon;
grant execute on function public.terminal_pin_in(text, text, text) to authenticated, service_role;

do $$
declare
  v_bad int;
begin
  -- The uuid-parameter versions must be GONE, not merely shadowed: an overload
  -- left behind is one PostgREST could still resolve.
  if to_regprocedure('public.terminal_pin_out(uuid)') is not null then
    raise exception 'the uuid overload of terminal_pin_out still exists';
  end if;
  if to_regprocedure('public.terminal_pin_in(text, text, uuid)') is not null then
    raise exception 'the uuid overload of terminal_pin_in still exists';
  end if;
  if to_regprocedure('public.terminal_pin_out(text)') is null then
    raise exception 'terminal_pin_out(text) is missing';
  end if;
  if to_regprocedure('public.terminal_pin_in(text, text, text)') is null then
    raise exception 'terminal_pin_in(text, text, text) is missing';
  end if;
  if not has_function_privilege('authenticated', 'public.terminal_pin_out(text)', 'execute') then
    raise exception 'authenticated cannot execute terminal_pin_out(text)';
  end if;

  -- 🔴 THE ASSERTION 000010 SHOULD HAVE HAD. Asserting the signature exists is
  -- what let a function broken on every call ship green. This PLANS the actual
  -- predicate, which is the step plpgsql skips at CREATE time.
  begin
    perform 1 from public.terminal_actor_session
     where terminal_member_id = '__verify_only__'
       and ended_at is null
       and (null::text is null or session_id = null::text);
  exception when undefined_function then
    raise exception 'pin_out predicate still cannot be planned: session_id does not compare to the parameter type';
  end;

  -- Nothing may be left holding two open rows, or the next PIN-in at that
  -- terminal fails on the unique index.
  select count(*) into v_bad from (
    select terminal_member_id from public.terminal_actor_session
     where ended_at is null group by terminal_member_id having count(*) > 1) x;
  if v_bad > 0 then
    raise exception '% terminal account(s) hold more than one open session', v_bad;
  end if;

  raise notice 'pin in/out compare text to text';
end $$;

commit;
