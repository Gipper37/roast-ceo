-- A caller with no device id may not sign out the roastery.
--
-- Three defects in the shared-terminal session table, found while tracing why
-- a roastmaster at MCR was told on 2026-11-02 that he could not turn on a
-- feature he has always been able to turn on. That symptom turned out to be a
-- client-side false reading (fixed in the frontend, lib/roast/
-- useSmartroastSession.ts), and NONE of the three below caused it. They were
-- underneath it, and they are worse:
--
-- 1. A DEVICE-LESS CALL SIGNS OUT THE WHOLE COMPANY. Both terminal_pin_in and
--    terminal_pin_out carried `p_device_id is null or device_id is not
--    distinct from p_device_id`, written as back-compat for rows minted before
--    device ids existed. So "no device id" means "every open session at this
--    company", and terminalPinOut() in lib/terminal/actions.ts passes
--    readDeviceId(), which is NULL whenever the device cookie is missing --
--    cleared storage, a reinstall, a fresh webview. MCR runs three terminals
--    on `wsorders`; the IDLE LOCK calls pin-out unattended. One terminal with
--    a lost cookie locking its own screen signs the roastmaster out mid-roast,
--    which is exactly the lockout migration 000010 was written to stop. 000010
--    scoped the app's call and left the function's null branch open, so its fix
--    held only as long as a cookie did. Device ids are now on 100% of sessions
--    (0 of 42 on 10-24/10-26, 27 of 33 on 10-27, 59 of 59 since 10-28) and ONE
--    legacy NULL-device row remains company-wide, so the branch was protecting
--    a single stale row.
--
-- 2. A STALE MARKER MADE PIN-OUT A NO-OP. pin_out ANDed the device filter with
--    `p_session is null or session_id = p_session`. When the cookie named a row
--    that had already ended, the AND matched nothing: the screen locked and the
--    session stayed open. Replaced by an explicit priority ladder -- device,
--    then marker, then no-device rows only -- which is the same precedence
--    lib/permissions/server.ts already applies when it decides who is standing
--    at a terminal.
--
-- 3. NOTHING EVER EXPIRED A SESSION. public.expire_terminal_sessions() has
--    existed since 20260907000007 and has NEVER RUN: no cron job, no DB caller,
--    no app caller (checked all three). Every read filters on
--    `expires_at > now()`, so this never locked anyone out -- it is the quiet
--    kind. `ended_reason` is never 'expired', so a session that timed out is
--    indistinguishable from one somebody signed out of, and prod is carrying
--    open rows from 10-27 and 10-28. One of them has device_id NULL, which is
--    the only thing defect 1's branch existed for.
--
-- Scheduled hourly at :20 (an unused minute) and run once here.

begin;

CREATE OR REPLACE FUNCTION public.terminal_pin_in(p_team_member_id text, p_pin text, p_replace_session text DEFAULT NULL::text, p_device_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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

  -- Clear the row that would COLLIDE, and only that row.
  -- uq_terminal_open_session_device is unique on (terminal_member_id,
  -- device_id) NULLS NOT DISTINCT where ended_at is null, so exactly one open
  -- row can block this insert: the one carrying this device's id, or -- for a
  -- caller that has no device id -- the one carrying no device id at all.
  -- `is not distinct from` covers both in one predicate, because NULL = NULL
  -- is precisely what that index treats as a duplicate.
  -- 🔴 A DEVICE-LESS CALLER MAY NOT REACH ANOTHER MACHINE'S ROW. This read
  -- `p_device_id is null or device_id is not distinct from p_device_id`, kept
  -- as back-compat for the legacy NULL-device rows -- which made "I do not
  -- know which machine I am" mean "end every open session at this company".
  -- MCR runs three terminals on `wsorders`. Device ids have been written on
  -- 100% of sessions since 2026-10-28 (0 of 42 on 10-24 and 10-26, 27 of 33 on
  -- 10-27, 59 of 59 since), and exactly ONE legacy NULL-device row survives
  -- company-wide -- so the branch protected a single stale row and left a
  -- company-wide sign-out reachable from any caller that lost its cookie.
  update public.terminal_actor_session
     set ended_at = now(), ended_reason = 'replaced'
   where terminal_member_id = v_term.team_member_id
     and ended_at is null
     and device_id is not distinct from p_device_id;

  insert into public.terminal_actor_session
    (company_id, terminal_member_id, team_member_id, actor_name, actor_title, expires_at, device_id)
  values (
    v_term.company_id, v_term.team_member_id, v_member.team_member_id,
    coalesce(v_member.name, 'Unnamed'), v_member.job_title,
    now() + make_interval(hours => v_policy.session_max_hours),
    p_device_id
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

CREATE OR REPLACE FUNCTION public.terminal_pin_out(p_session text DEFAULT NULL::text, p_device_id text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
     -- 🔴 THE DEVICE FIRST, THE MARKER SECOND, AND NOTHING WIDER. A priority
     -- ladder, not an AND of two optional filters:
     --
     --   a device id  -> that machine's row, whatever marker came with it
     --   a marker only -> the one row this caller can name
     --   neither       -> rows belonging to NO device. Never another machine's.
     --
     -- The old form, `(p_device_id is null or ...) and (p_session is null or
     -- ...)`, had two faults. A caller with no device id ended EVERY open
     -- session for the account -- and lib/terminal/actions.ts reaches this
     -- through readDeviceId(), which returns null whenever the device cookie
     -- is missing, so a cleared cookie plus the UNATTENDED idle lock signed
     -- out every terminal in the roastery. That is the same lockout 000010
     -- was written to fix: it scoped the app's call and left this function's
     -- null branch open, so the fix held only as long as the cookie did.
     -- Second, a stale marker naming an already-ended row made the AND match
     -- nothing, so the screen locked while the session stayed open.
     and case
           when p_device_id is not null then device_id is not distinct from p_device_id
           when p_session   is not null then session_id = p_session
           else device_id is null
         end;
end;
$function$;

-- ── Close what is already expired, and keep closing it ──────────────────
-- The function is unchanged; it has simply never been called.
select public.expire_terminal_sessions();

-- 🔴 GUARDED, BECAUSE STAGING HAS NO pg_cron, and it has to be DYNAMIC SQL:
-- plpgsql plans a statement before it runs, so a bare `cron.job` reference
-- inside a false branch still fails to parse on staging. Same shape as
-- 20261026000013.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute $q$ select cron.unschedule('expire_terminal_sessions')
                 where exists (select 1 from cron.job where jobname = 'expire_terminal_sessions') $q$;
    execute $q$ select cron.schedule('expire_terminal_sessions', '20 * * * *',
                                     'select public.expire_terminal_sessions()') $q$;
    raise notice 'scheduled expire_terminal_sessions hourly at :20';
  else
    raise notice 'pg_cron absent (staging): expire_terminal_sessions not scheduled here';
  end if;
end $$;

-- ── Verify ──────────────────────────────────────────────────────────────
-- Every assertion here CAN pass: each states something this migration has just
-- made true, not something the design forbids.
do $$
declare
  v_open_expired int;
  v_wide         int;
  v_ladder       int;
  v_narrow       int;
  v_scheduled    boolean := null;
begin
  -- 1. No open row is past its expiry any more.
  select count(*) into v_open_expired
    from public.terminal_actor_session
   where ended_at is null and expires_at <= now();
  if v_open_expired <> 0 then
    raise exception 'expire_terminal_sessions left % open expired row(s)', v_open_expired;
  end if;

  -- 2. Neither function can still widen to the account on a null device.
  -- 🔴 STRIP THE COMMENTS FIRST. prosrc is the whole source, prose included,
  -- and the comments above both clauses QUOTE the old predicate to explain what
  -- it did. The first version of this assertion matched its own explanation and
  -- failed the migration on staging with "2 function(s) still widen" while both
  -- functions were already correct. A check that reads commentary is not
  -- checking the code.
  select count(*) into v_wide
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('terminal_pin_in', 'terminal_pin_out')
     and regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') like '%p_device_id is null or%';
  if v_wide <> 0 then
    raise exception '% function(s) still widen on a null device id', v_wide;
  end if;

  -- 3. And the narrowing each one is supposed to have is actually there.
  select count(*) into v_ladder
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'terminal_pin_out'
     and regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g')
         like '%when p_device_id is not null then device_id is not distinct from p_device_id%';
  select count(*) into v_narrow
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'terminal_pin_in'
     and regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g')
         like '%and device_id is not distinct from p_device_id;%';
  if v_ladder <> 1 or v_narrow <> 1 then
    raise exception 'narrowing missing: pin_out ladder=%, pin_in device clause=%', v_ladder, v_narrow;
  end if;

  -- 4. The job exists wherever pg_cron does.
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute $q$ select exists (select 1 from cron.job
                                where jobname = 'expire_terminal_sessions' and active) $q$
      into v_scheduled;
    if not coalesce(v_scheduled, false) then
      raise exception 'expire_terminal_sessions is not scheduled';
    end if;
  end if;

  raise notice 'ok: 0 open-expired rows, 0 account-wide branches, narrowing present, cron=%',
    coalesce(v_scheduled::text, 'n/a (no pg_cron)');
end $$;

commit;
