-- actor_at asks THIS device who is standing there.
--
-- Owner, 2026-10-27: *"the last few times Steven has printed the bin cards its
-- showing roasted by ryan not him."* He is right, the record is wrong, and I
-- caused it last night.
--
-- `actor_at()` is the function every attribution stamp goes through. Its
-- terminal branch reads:
--
--     where s.terminal_member_id = v_term.team_member_id
--       and s.started_at <= p_when
--       and coalesce(s.ended_at, s.expires_at) > p_when
--     order by s.started_at desc
--     limit 1
--
-- No device predicate. It takes the most recently STARTED open session for the
-- ACCOUNT.
--
-- 🔴 THAT WAS CORRECT UNTIL 20261026000024, AND THAT MIGRATION IS MINE.
-- uq_terminal_open_session permitted exactly one open session per terminal
-- account, so "the most recent" and "this device's" were the same row and the
-- missing predicate could not be observed. Making terminals independent gave
-- one account three concurrent sessions and turned a harmless ORDER BY into a
-- lottery. I narrowed auth_has_permission by device in that migration and did
-- not narrow this.
--
-- Observed on production today:
--
--     Steven Marquez   device cf30434c   roasting terminal, PIN'd in 09:07
--     Ryan Hagler      device 47aac5b1   orders terminal,   PIN'd in 09:12
--
-- From 09:12 every roast Steven charged was stamped "Ryan Hagler", because
-- Ryan's session started later. The bin card prints roast_log.roasted_by_name,
-- so it printed Ryan.
--
-- 🔴 THIS IS THE HACCP RECORD. The owner's words: *"the whole reason for the
-- pin set up was to be able to track who did what for haccp audit purposes."*
-- A permission check that picks the wrong session denies somebody a button; an
-- attribution stamp that picks the wrong session writes a false name onto a
-- food-safety record and keeps it.
--
-- 🔴 NO BORROWING, which is the part that is not merely symmetry with
-- auth_has_permission. Where the device is known, ONLY this device's session
-- counts: if nobody is PIN'd in here the function falls through to the login
-- rather than naming someone standing at another machine. A wrong name is
-- worse than a generic one on a record an auditor reads.
--
-- Where the device is NOT known -- no header, or a session row predating
-- device_id -- the old whole-account behaviour stands, so nothing that
-- attributed correctly before now attributes to nobody.
--
-- Does not repair the rows already written. Those are listed for the owner
-- rather than rewritten: silently changing who a food-safety record says did
-- the work is not a thing to do without being asked.

begin;
CREATE OR REPLACE FUNCTION public.actor_at(p_when timestamp with time zone DEFAULT now())
 RETURNS TABLE(team_member_id text, actor_name text, actor_title text, via text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_term public.team;
begin
  v_term := public.current_terminal();

  -- 1. A terminal: whoever was PIN'd in at that instant.
  if v_term.team_member_id is not null then
    return query
      select s.team_member_id, s.actor_name, s.actor_title, 'terminal'::text
        from public.terminal_actor_session s
       where s.terminal_member_id = v_term.team_member_id
         -- 🔴 THIS DEVICE. Several terminals share one terminal login, and as
         -- of 20261026000024 they hold their own concurrent sessions. Without
         -- this predicate `order by started_at desc limit 1` returns whoever
         -- PIN'd in most recently ANYWHERE, so a roast charged at the roasting
         -- terminal was stamped with the name of whoever had just PIN'd in at
         -- the orders terminal. Observed on production 2026-10-27: Steven on
         -- device cf30434c, actor_at returning Ryan on device 47aac5b1.
         --
         -- It was harmless until per-device sessions existed, because the
         -- schema permitted exactly one open session and "most recent" and
         -- "this one" were the same row. Making terminals independent made
         -- this wrong, and it is the attribution the HACCP record rests on.
         --
         -- 🔴 NO BORROWING. When the device is known, only this device's
         -- session counts: if nobody is PIN'd in HERE the function falls
         -- through to the login below rather than naming a person standing at
         -- another machine. A wrong name on a food-safety record is worse than
         -- a generic one. When the device is NOT known (no header, or a row
         -- predating device_id) the old whole-account behaviour stands, so
         -- nothing that worked before starts returning nothing.
         and (
           public.current_terminal_device() is null
           or s.device_id is null
           or s.device_id = public.current_terminal_device()
         )
         -- Half-open on purpose: [started_at, ended_at). A handover writes the
         -- outgoing session's ended_at and the incoming session's started_at at
         -- the SAME instant, so an inclusive end would match both and the answer
         -- would depend on tie-breaking. The moment of handover belongs to the
         -- person taking over.
         and s.started_at <= p_when
         and coalesce(s.ended_at, s.expires_at) > p_when
       order by s.started_at desc
       limit 1;
    if found then return; end if;
  end if;

  -- 2. Anyone else, and a terminal with nobody PIN'd in then: the login itself.
  return query
    select t.team_member_id, t.name, t.job_title, 'login'::text
      from public.team t
     where t.auth_user_id = auth.uid()
       and coalesce(t.is_active, true)
     order by t.created_at
     limit 1;
end;
$function$;

do $$
declare
  v_def text;
  v_n   int;
begin
  v_def := pg_get_functiondef('public.actor_at(timestamptz)'::regprocedure);
  if v_def not like '%current_terminal_device%' then
    raise exception 'actor_at still does not narrow by device';
  end if;

  -- The login fallback must survive: an ordinary (non-terminal) login still
  -- has to attribute to itself, and that is the branch most of the app uses.
  if v_def not like '%t.auth_user_id = auth.uid()%' then
    raise exception 'actor_at lost its login fallback';
  end if;

  -- It must still return exactly one row per call, or every caller that reads
  -- .team_member_id off it starts seeing a set.
  if v_def not like '%limit 1%' then
    raise exception 'actor_at lost its limit';
  end if;

  -- How much is already wrong, reported rather than repaired.
  select count(*) into v_n
    from public.terminal_actor_session a
    join public.terminal_actor_session b
      on b.terminal_member_id = a.terminal_member_id
     and b.device_id is distinct from a.device_id
     and b.started_at > a.started_at
     and b.started_at < coalesce(a.ended_at, a.expires_at)
   where a.device_id is not null and b.device_id is not null;
  raise notice 'actor_at now asks this device; % overlapping session pair(s) exist, whose stamps may already be wrong', v_n;
end $$;

commit;
