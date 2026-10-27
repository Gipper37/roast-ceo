-- A terminal is a DEVICE, not an account.
--
-- Owner, 2026-10-26: *"todays state is unacceptable"*, and earlier: *"any
-- terminal signed in to a terminal user (wsorders) should be given an id. can
-- you tell from the app that they are different terminals. why wouldn't it just
-- be automatic"*. Both right. Every answer so far has been a workaround.
--
-- WHAT WENT WRONG TODAY, in order. A roastery runs several physical terminals
-- on ONE terminal login. `terminal_actor_session` was keyed on the ACCOUNT, so
-- the answer to "who is standing here" was "whoever PIN'd in last ANYWHERE". A
-- `staff` PIN-in at the bagging terminal made the ROASTING terminal resolve as
-- staff, which does not grant `roast.log`, so saving a roast came back denied
-- mid-shift while the chip still read the roastmaster's name.
--
-- 000010 tried to scope PIN-out to one session and broke PIN-in, because
-- `uq_terminal_open_session` is UNIQUE (terminal_member_id) WHERE ended_at IS
-- NULL -- one open session per ACCOUNT, an invariant nothing above the schema
-- could work around. 000011 reverted to clearing the whole account and said so:
-- "THIS DOES NOT MAKE TERMINALS INDEPENDENT, AND NOTHING AT THIS LAYER CAN."
-- It was right, and the layer it meant is this one.
--
-- 🔴 NOT IP, AND NOT USER-AGENT. Three terminals in one roastery sit behind one
-- NAT and share a public IP, and three identical machines share a user-agent.
-- Either would merge the devices it is supposed to tell apart. The thing that
-- is genuinely per-device is a COOKIE, which the browser keeps and nothing else
-- can see.
--
-- 🔴 THE DATABASE HAS TO KNOW, not just the app. auth_has_permission is called
-- from RLS policies, and policies take no arguments. Narrowing only in the app
-- and leaving this clause broad would give every device at an account the UNION
-- of everyone PIN'd in anywhere -- worse than today, not better.
--
-- The device id arrives as a request header. PostgREST exposes those to SQL,
-- and that was VERIFIED on this project before any of this was written, not
-- assumed: a custom header round-tripped through a real REST call, and a header
-- that was not sent read as absent. That absence is what makes the fallback
-- below safe.
--
-- NOTHING TO SET UP. A machine signing in as the terminal user gets a device id
-- on its first PIN-in and keeps it. No invitation, no second account, no admin
-- step.

begin;

alter table public.terminal_actor_session
  add column if not exists device_id text;

comment on column public.terminal_actor_session.device_id is
  'Which physical terminal owns this session. Set from an httpOnly cookie minted per machine. NULL on rows predating this column, which keeps the old whole-account behaviour for them.';

-- 🔴 THE INVARIANT MOVES FROM THE ACCOUNT TO THE DEVICE. This is the whole
-- change: three terminals on one login can now hold three sessions, and one
-- terminal still cannot hold two.
--
-- NULLS NOT DISTINCT so the legacy rows -- which all have a NULL device --
-- continue to behave exactly as they did: one open session between them.
drop index if exists public.uq_terminal_open_session;
create unique index if not exists uq_terminal_open_session_device
  on public.terminal_actor_session (terminal_member_id, device_id)
  nulls not distinct
  where ended_at is null;

-- The device asking, or NULL when the caller sent no header.
create or replace function public.current_terminal_device()
returns text
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  select nullif(
    coalesce(nullif(current_setting('request.headers', true), '')::json ->> 'x-terminal-device', ''),
    ''
  );
$function$;

revoke all on function public.current_terminal_device() from public, anon;
grant execute on function public.current_terminal_device() to authenticated, service_role;

-- ── auth_has_permission, taken verbatim from prod and narrowed ───────────
CREATE OR REPLACE FUNCTION public.auth_has_permission(p_permission_id text, p_company_id text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select exists (
    select 1
      from public.team t
      join public.role_permissions rp
        on rp.role_id = t.role and rp.permission_id = p_permission_id and rp.granted
      join public.permissions p
        on p.permission_id = p_permission_id
     where t.auth_user_id = auth.uid()
       and coalesce(t.is_active, true)
       and (p_company_id is null or t.company_id = p_company_id)
       and (
         not p.is_plan_gated
         or exists (
           select 1
             from public.company_subscription_status s
             join public.plan_permissions pp
               -- A trial IS the enterprise plan for as long as it lasts. The app
               -- has always resolved it that way (lib/permissions/server.ts);
               -- reading the raw plan_id here would have refused every plan-gated
               -- key to every tenant in their first 30 days — which is every new
               -- tenant company-signup creates.
               on pp.plan_id = (case when s.status = 'trialing' then 'enterprise' else s.plan_id end)
              and pp.permission_id = p_permission_id
              and pp.granted
            where s.company_id = t.company_id
         )
       )
       -- ── The module switch ────────────────────────────────────────────────
       -- A key that names a feature_key belongs to an OPTIONAL module, and a
       -- tenant chooses whether to use it (company_feature). The frontend has
       -- always honoured that — buildPermissionSnapshot computes
       -- `featureOk = !p.feature_key || enabledFeatures.has(p.feature_key)` —
       -- and this function never did. So the toggle was display-only: the nav
       -- item disappeared while all 17 RPCs behind it stayed callable over
       -- PostgREST.
       --
       -- It also made a migration lie. 20260924000005 proved "a Social Hour
       -- admin can now reach the feature" by calling THIS function, which
       -- returned true while the module was off and the app showed them
       -- nothing. A probe is only as good as the thing it asks.
       and (
         p.feature_key is null
         or exists (
           select 1
             from public.company_feature cf
            where cf.company_id = t.company_id
              and cf.feature_key = p.feature_key
              and cf.enabled
         )
       )
       -- ── The terminal narrowing ───────────────────────────────────────────
       -- An ordinary login is unaffected. A TERMINAL login must have somebody
       -- PIN'd in, and that person's own role has to grant the key too.
       and (
         not coalesce(t.is_terminal, false)
         or exists (
           select 1
             from public.terminal_actor_session ses
             join public.team pinned
               on pinned.team_member_id = ses.team_member_id
             join public.role_permissions rp2
               on rp2.role_id = pinned.role
              and rp2.permission_id = p_permission_id
              and rp2.granted
            where ses.terminal_member_id = t.team_member_id
              and ses.ended_at is null
              and ses.expires_at > now()
              and coalesce(pinned.is_active, true)
              -- 🔴 THIS DEVICE'S session, not any session at the account.
              --
              -- Several physical terminals share one terminal login. Without
              -- this line every one of them holds the UNION of whoever is
              -- PIN'd in anywhere: a staff PIN-in at the bagging terminal
              -- decided what the ROASTING terminal could do, which is the
              -- 2026-10-26 lockout.
              --
              -- The device id arrives as a request header, which PostgREST
              -- exposes to SQL. Verified on this project rather than assumed:
              -- a custom header round-tripped, and a header that was not sent
              -- reads as absent, which is what makes the fallback below
              -- detectable.
              --
              -- NULL device on the session, or no header on the request, falls
              -- back to the old whole-account behaviour. That is deliberate:
              -- rows predating this column, and any caller that does not send
              -- the header, must keep working exactly as they did rather than
              -- losing permissions mid-shift.
              and (
                ses.device_id is null
                or public.current_terminal_device() is null
                or ses.device_id = public.current_terminal_device()
              )
         )
       )
  );
$function$;

-- ── terminal_pin_in: records the device, clears only its own row ─────────
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

  -- Every open row for the account. uq_terminal_open_session leaves no choice:
  -- the insert below is unique on (terminal_member_id) where ended_at is null,
  -- so a row left open here makes PIN-in fail outright. See 000011.
  -- 🔴 ONLY THIS DEVICE'S open row. 000011 had to clear the whole account
  -- because uq_terminal_open_session allowed one open session per ACCOUNT;
  -- the index is now keyed on (terminal_member_id, device_id), so clearing
  -- the account would sign out the roastery's other terminals for no reason.
  -- A caller with no device id keeps the old whole-account behaviour, which
  -- is what the legacy NULL-device rows need.
  update public.terminal_actor_session
     set ended_at = now(), ended_reason = 'replaced'
   where terminal_member_id = v_term.team_member_id
     and ended_at is null
     and (p_device_id is null or device_id is not distinct from p_device_id);

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
revoke all on function public.terminal_pin_in(text, text, text, text) from public, anon;
grant execute on function public.terminal_pin_in(text, text, text, text) to authenticated, service_role;

-- ── terminal_pin_out: ends only this device's row ────────────────────────
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
     -- Scoped to the DEVICE first: a terminal locking its own screen must not
     -- sign out the roastery's other terminals. p_session stays as a narrower
     -- hint for a caller that knows exactly which row it holds.
     and (p_device_id is null or device_id is not distinct from p_device_id)
     and (p_session is null or session_id = p_session);
end;
$function$;
revoke all on function public.terminal_pin_out(text, text) from public, anon;
grant execute on function public.terminal_pin_out(text, text) to authenticated, service_role;

do $$
declare
  v_term   text;
  v_a      text;
  v_b      text;
  v_co     text;
  v_fac    text;
  v_actor  text;
  v_n      int;
begin
  -- The invariant moved, and both halves must be true.
  if exists (select 1 from pg_indexes where schemaname='public' and indexname='uq_terminal_open_session') then
    raise exception 'the account-wide unique index is still present';
  end if;
  if not exists (select 1 from pg_indexes where schemaname='public' and indexname='uq_terminal_open_session_device') then
    raise exception 'the per-device unique index was not created';
  end if;
  if to_regprocedure('public.current_terminal_device()') is null then
    raise exception 'current_terminal_device() is missing';
  end if;

  -- 🔴 PROVE THE POINT OF THE WHOLE MIGRATION: two devices on ONE terminal
  -- account can hold two open sessions, and one device still cannot hold two.
  -- 000010 shipped green by asserting a signature existed and was broken on
  -- every call; this asserts the BEHAVIOUR.
  select t.team_member_id, t.company_id, t.facility_id into v_term, v_co, v_fac
    from public.team t where coalesce(t.is_terminal,false) limit 1;

  -- 🔴 A REAL team member: team_member_id is NOT NULL on this table, and the
  -- first version of this block inserted NULL. Staging has no terminal account
  -- at all, so it took the skip branch below and the assertion never ran --
  -- green rehearsal, and production refused it on the not-null constraint.
  -- That is the rehearsal failing to rehearse, not the assertion being wrong.
  select t.team_member_id into v_actor
    from public.team t
   where t.company_id = v_co and coalesce(t.is_active, true)
     and not coalesce(t.is_terminal, false)
   limit 1;

  if v_term is null or v_actor is null then
    -- Loud, because a silent skip is how this shipped broken the first time.
    raise warning 'NO TERMINAL ACCOUNT OR NO ACTOR ON THIS DATABASE: the behaviour assertion did NOT run here. It runs where the data exists.';
  else
    insert into public.terminal_actor_session
      (company_id, terminal_member_id, team_member_id, actor_name, expires_at, device_id)
    values (v_co, v_term, v_actor, '__verify_a__', now() + interval '1 minute', '__verify_device_a__')
    returning session_id into v_a;

    -- A SECOND device on the SAME account. This is what the old index forbade.
    begin
      insert into public.terminal_actor_session
        (company_id, terminal_member_id, team_member_id, actor_name, expires_at, device_id)
      values (v_co, v_term, v_actor, '__verify_b__', now() + interval '1 minute', '__verify_device_b__')
      returning session_id into v_b;
    exception when unique_violation then
      raise exception 'two devices on one terminal account STILL cannot hold two sessions';
    end;

    -- The same device twice must still be refused.
    begin
      insert into public.terminal_actor_session
        (company_id, terminal_member_id, team_member_id, actor_name, expires_at, device_id)
      values (v_co, v_term, v_actor, '__verify_dup__', now() + interval '1 minute', '__verify_device_a__');
      raise exception 'one device was allowed two open sessions';
    exception when unique_violation then
      null;  -- correct
    end;

    delete from public.terminal_actor_session
     where session_id in (v_a, v_b) or actor_name like '__verify%';

    select count(*) into v_n from public.terminal_actor_session where actor_name like '__verify%';
    if v_n <> 0 then
      raise exception 'the probe rows were not cleaned up (% left)', v_n;
    end if;
  end if;

  -- The probe from 000023 has served its purpose.
  drop function if exists public.probe_request_header(text);

  raise notice 'a terminal is a device: two devices on one account can hold two sessions';
end $$;

commit;
