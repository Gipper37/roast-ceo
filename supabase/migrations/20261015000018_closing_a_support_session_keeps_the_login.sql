-- Stepping out of a roastery does not sign the developer out of STRATA.
--
-- `end_sessions_when_access_ends` fires on `team` DELETE, and on the UPDATE
-- that sets `is_active` false. If the user has no OTHER active team row it
-- deletes every `auth.sessions` row for them, which is exactly right when a
-- real membership is revoked: access ends, the login ends with it.
--
-- `20261015000007` then gave a STRATA developer a time-boxed `team` row to work
-- inside a roastery with (`login_kind = 'dev_session'`). That row is BORROWED.
-- It never granted the developer's own login, which comes from
-- `developer_users`.
--
-- 🔴 AND IT IS THEIR ONLY TEAM ROW. Measured on prod: the one developer has
-- ZERO team rows of their own. So during a support session the borrowed row is
-- the only one they have, and closing it -- which is what Exit does, and what
-- switching roasters does twice in a row -- found no other active membership
-- and deleted every session they had. **A developer was signed out of STRATA
-- for stepping back out of a roastery**, and again for moving between two.
--
-- Fixed in BOTH directions, which is the half worth stating: a dev_session row
-- neither ends a login nor keeps one alive. Without the second half, a real
-- membership being revoked while a support session happened to be open would
-- have left the login standing, because the borrowed row would have counted as
-- "active somewhere else".
--
-- The expiry is unaffected and is the right mechanism: `auth_company_ids()`
-- already stops honouring an expired support row (20261015000008), so the
-- roaster's data goes out of reach on time whatever happens to the login.
--
-- Body patched from `pg_get_functiondef`, not retyped: it carries the
-- is_active transition test and the still-active-elsewhere check, and the two
-- dev_session conditions are the only lines that differ.

begin;

CREATE OR REPLACE FUNCTION public.end_sessions_when_access_ends()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_uid    uuid;
  v_member text;
begin
  -- 🔴 A SUPPORT SESSION ENDING IS NOT A LOSS OF ACCESS.
  --
  -- `login_kind = 'dev_session'` is the time-boxed `team` row a STRATA
  -- developer gets while inside a roastery (20261015000007). It is BORROWED:
  -- it never granted the developer's own login, which comes from
  -- `developer_users`. This trigger exists to end a session when a REAL
  -- membership is revoked, and a dev_session row is not one.
  --
  -- Measured on prod: the one developer has ZERO team rows of their own. So
  -- during a support session the borrowed row is their ONLY team row, and
  -- closing it -- which is what Exit does, and what switching roasters does
  -- twice -- found no other active membership and deleted every
  -- `auth.sessions` row for them. The developer was signed out of STRATA for
  -- stepping back out of a roastery.
  --
  -- Ignored in BOTH directions, which is the part worth saying: it is also
  -- not counted as "active somewhere else" below, so a real membership being
  -- revoked still ends the login even if a support session happens to be open
  -- at the time. A borrowed row must neither end a login nor keep one alive.
  if coalesce(
       case when tg_op = 'DELETE' then old.login_kind else new.login_kind end,
       '') = 'dev_session' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

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
       -- A borrowed support row is not a membership that can keep a login
       -- alive. See the note at the top.
       and coalesce(t.login_kind, '') <> 'dev_session'
  ) then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  delete from auth.sessions s where s.user_id = v_uid;
  return case when tg_op = 'DELETE' then old else new end;
end;
$function$;

do $verify$
DECLARE
  v_src text;
BEGIN
  select prosrc into v_src from pg_proc
   where oid = 'public.end_sessions_when_access_ends'::regproc;

  -- Both conditions, named separately, because they are opposite halves and
  -- dropping either one is a different bug.
  if v_src not like '%= ''dev_session'' then%' then
    raise exception 'the trigger does not ignore a closing support session; Exit will sign the developer out';
  end if;
  if v_src not like '%<> ''dev_session''%' then
    raise exception 'a borrowed support row can still keep a revoked login alive';
  end if;

  -- And the work that is not this change's survived the replace.
  if v_src not like '%delete from auth.sessions%' then
    raise exception 'the trigger no longer ends sessions at all';
  end if;
  if v_src not like '%coalesce(old.is_active, true) and new.is_active = false%' then
    raise exception 'the is_active transition test is gone; every team UPDATE would end a session';
  end if;

  -- 🔴 Exercised, not just grepped. A dev_session row is inserted and deleted,
  -- and the user's sessions must survive it. Rolled back by the surrounding
  -- transaction regardless, and auth.sessions is only READ.
  DECLARE
    v_company text;
    v_fac     text;
    v_uid     uuid := '00000000-0000-4000-8000-00000000dead';
    v_before  int;
    v_after   int;
  BEGIN
    select company_id into v_company from public.companies limit 1;
    if v_company is null then
      raise notice 'no company here, skipping the row-level check';
    else
      select facility_id into v_fac from public.facilities where company_id = v_company limit 1;
      select count(*) into v_before from auth.sessions where user_id = v_uid;
      insert into public.team (team_member_id, auth_user_id, company_id, facility_id,
                               name, email, role, is_active, login_kind, session_expires_at)
      values ('zzverify-dev-session', v_uid, v_company, v_fac,
              'zzverify', 'zzverify@example.com', 'company_admin', true,
              'dev_session', now() + interval '1 hour');
      delete from public.team where team_member_id = 'zzverify-dev-session';
      select count(*) into v_after from auth.sessions where user_id = v_uid;
      if v_after is distinct from v_before then
        raise exception 'closing a support session changed the session count: % -> %', v_before, v_after;
      end if;
    end if;
  END;

  raise notice 'a support session can be closed without ending the developer''s login';
END;
$verify$;

commit;
