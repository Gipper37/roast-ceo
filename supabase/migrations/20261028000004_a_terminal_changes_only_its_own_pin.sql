-- A terminal may only change the PIN of the person standing at IT.
--
-- ── The incident ─────────────────────────────────────────────────────────
--
-- "ok we have a big issue. everyones pins are starting to fail one by one."
--
-- Measured on production before writing a line of this:
--
--   Spencer Troutman  pin set 21:26:26 by 'self at terminal', last used 20:31,
--                     4 failures since
--   Whitney           pin set 18:53:53 by 'self at terminal', last used 18:33,
--                     6 failures since, LOCKED
--   Jacob Lopez       signed in 21:26:17, still must_change = true
--   open sessions     2, on 2 devices, under ONE terminal login
--
-- Jacob set his PIN nine seconds after signing in and the row that changed was
-- Spencer's. Nobody mistyped anything: their PIN had been replaced underneath
-- them, and it happens again to a different person every time somebody sets
-- their own PIN. That is the "one by one".
--
-- ── Why ──────────────────────────────────────────────────────────────────
--
-- 20261026000024 let several machines share one terminal login, each holding
-- its own open session. 20261027000003 then taught actor_at and
-- auth_has_permission to ask WHICH DEVICE, and four functions were missed.
-- Every one of them resolves "who is standing here" and none of them asked:
--
--   terminal_set_own_pin       writes a credential     <- the incident
--   auth_role_rank             decides a role rank
--   current_terminal_actor     names the person
--   set_pack_run_best_before   signs a HACCP record
--
-- `select ... into` takes the first row of a multi-row result without
-- complaining, so this was silent until two people were signed in at once.
--
-- ── The one deliberate difference ────────────────────────────────────────
--
-- The three READS keep actor_at's tolerant shape: an unknown device, or a
-- session row predating device_id, falls back to the old whole-account
-- behaviour so nothing that worked yesterday starts returning nothing.
--
-- 🔴 THE WRITE DOES NOT. Picking the likeliest row is fine for a label and
-- unacceptable for destroying somebody's PIN, so terminal_set_own_pin refuses
-- when it cannot tell, in a sentence meant for a person mid-shift.
--
-- Bodies taken verbatim from pg_get_functiondef on production and patched;
-- nothing retyped. Production and staging were byte-identical on all four
-- before this ran.

begin;

CREATE OR REPLACE FUNCTION public.terminal_set_own_pin(p_pin text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_term   public.team;
  v_actor  text;
  v_open   int;
  v_policy public.company_terminal_policy;
begin
  v_term := public.current_terminal();
  if v_term.team_member_id is null then
    raise exception 'This login is not a shared terminal.' using errcode = 'insufficient_privilege';
  end if;

  -- 🔴 THIS DEVICE, AND REFUSE TO GUESS.
  --
  -- Several machines share one terminal login and each holds its OWN open
  -- session (20261026000024 keyed uq_terminal_open_session on
  -- (terminal_member_id, device_id) to allow exactly that). This lookup had no
  -- device predicate and no LIMIT, so `select ... into` took whichever open row
  -- Postgres handed back first and the update below rewrote THAT person's PIN.
  --
  -- Observed on production 2026-10-28: Jacob PIN'd in at 21:26:17 on device
  -- 69ef91e9 and set his PIN nine seconds later; the row that changed was
  -- SPENCER'S (set_at 21:26:26, set_by 'self at terminal'), and Jacob's own row
  -- still read must_change. Spencer then failed four times with the PIN he had
  -- always used. Whitney was hit the same way at 18:53 and locked out. The
  -- roaster's words: "everyones pins are starting to fail one by one."
  --
  -- 20261027000003 gave actor_at and auth_has_permission this predicate and
  -- missed this function, which is the one that WRITES a credential.
  --
  -- 🔴 NO FALLBACK TO "MOST RECENT" HERE, unlike actor_at. A read may pick the
  -- likeliest row; destroying somebody's PIN may not. If the device cannot be
  -- told apart and more than one person is signed in, this refuses and says so.
  select count(*), min(s.team_member_id)
    into v_open, v_actor
    from public.terminal_actor_session s
   where s.terminal_member_id = v_term.team_member_id
     and s.ended_at is null
     and s.expires_at > now()
     and (
       public.current_terminal_device() is null
       or s.device_id is null
       or s.device_id = public.current_terminal_device()
     );

  if v_open = 0 then
    raise exception 'Nobody is signed in at this terminal.' using errcode = 'insufficient_privilege';
  end if;

  if v_open > 1 then
    raise exception 'More than one person is signed in under this terminal login, so this screen cannot tell whose PIN to change. Sign out on the other screens, then set your PIN again.'
      using errcode = 'cardinality_violation';
  end if;

  v_policy := public.terminal_policy(v_term.company_id);

  -- Same rules as set_team_pin. Kept here rather than shared through a helper
  -- because the messages are read by somebody standing at a machine mid-shift,
  -- and they should say what to do next.
  if p_pin !~ ('^[0-9]{' || v_policy.pin_length || '}$') then
    raise exception 'Your PIN needs to be exactly % digits.', v_policy.pin_length using errcode = 'check_violation';
  end if;
  if p_pin ~ '^(.)\1*$' then
    raise exception 'Pick a PIN that is not all the same digit.' using errcode = 'check_violation';
  end if;
  if position(p_pin in '01234567890') > 0 or position(p_pin in '09876543210') > 0 then
    raise exception 'Pick a PIN that is not a run of digits in order.' using errcode = 'check_violation';
  end if;

  update public.team_pin
     set pin_hash     = extensions.crypt(p_pin, extensions.gen_salt('bf', 10)),
         set_at       = now(),
         set_by       = 'self at terminal',
         must_change  = false,   -- theirs now
         failed_count = 0,
         locked_until = null
   where team_member_id = v_actor;
end;
$function$;

CREATE OR REPLACE FUNCTION public.auth_role_rank(p_company_id text)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- Mirrors ROLE_HIERARCHY in S/lib/permissions/constants.ts. Lower is more
  -- senior. An unknown or absent role ranks below everything. A TERMINAL
  -- login's rank is the PIN'd-in person's, and never better than the login's
  -- own; a terminal with nobody PIN'd in outranks nobody.
  select coalesce(min(
    case when coalesce(t.is_terminal, false) then
      greatest(public.role_rank(t.role), coalesce((
        select public.role_rank(p.role)
          from public.terminal_actor_session ses
          join public.team p on p.team_member_id = ses.team_member_id
         where ses.terminal_member_id = t.team_member_id
           and ses.ended_at is null
           and ses.expires_at > now()
           and coalesce(p.is_active, true)
           -- 🔴 THIS DEVICE. `order by started_at desc limit 1` means the most
           -- recent PIN-in ANYWHERE on this login, so a supervisor signing in
           -- at one machine raised the rank of whoever was standing at another.
           -- Bounded by greatest() below, so it never exceeded the terminal's
           -- own role -- but it was still somebody else's rank. Same predicate
           -- and same null-tolerance as actor_at (20261027000003).
           and (
             public.current_terminal_device() is null
             or ses.device_id is null
             or ses.device_id = public.current_terminal_device()
           )
         order by ses.started_at desc
         limit 1), 99))
    else public.role_rank(t.role) end), 99)
    from public.team t
   where t.auth_user_id = auth.uid()
     and t.company_id = p_company_id
     and coalesce(t.is_active, true);
$function$;

CREATE OR REPLACE FUNCTION public.current_terminal_actor()
 RETURNS TABLE(team_member_id text, actor_name text, actor_title text, session_id text, expires_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_term public.team;
begin
  v_term := public.current_terminal();
  if v_term.team_member_id is null then return; end if;
  return query
    select s.team_member_id, s.actor_name, s.actor_title, s.session_id, s.expires_at
      from public.terminal_actor_session s
     where s.terminal_member_id = v_term.team_member_id
       and s.ended_at is null
       and s.expires_at > now()
       -- 🔴 THIS DEVICE. With two machines signed in this returned TWO rows
       -- from a function named for one person, and every caller took whichever
       -- came first. Ordered and capped as well, so the answer is stable even
       -- where the device is unknown.
       and (
         public.current_terminal_device() is null
         or s.device_id is null
         or s.device_id = public.current_terminal_device()
       )
     order by s.started_at desc
     limit 1;
end;
$function$;

CREATE OR REPLACE FUNCTION public.set_pack_run_best_before(p_pack_run_id text, p_best_before date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_company text; v_packed date; v_roasted date; v_days int;
        v_old date; v_voided timestamptz; v_actor text; v_actor_name text;
begin
  select pr.company_id, pr.packed_on,
         (select max(rl.roast_date)::date
            from public.pack_run_source s
            join public.roast_log rl on rl.roast_log_id = s.roast_log_id
           where s.pack_run_id = pr.pack_run_id),
         pr.best_before, pr.voided_at
    into v_company, v_packed, v_roasted, v_old, v_voided
    from public.pack_run pr
   where pr.pack_run_id = p_pack_run_id and pr.company_id in (select auth_company_ids());
  if v_company is null then raise exception 'No such pack run.' using errcode = 'no_data_found'; end if;
  if not public.auth_has_permission('pack.run', v_company) then
    raise exception 'You do not have permission to change this.' using errcode = 'insufficient_privilege';
  end if;
  -- A voided run is a closed record. correct_pack_run refuses one; this did not,
  -- so the label screen could still move a voided lot's date.
  if v_voided is not null then
    raise exception 'That pack run was voided. Its record cannot be changed.'
      using errcode = 'invalid_parameter_value';
  end if;
  if p_best_before is not null and p_best_before < v_packed then
    raise exception 'A best-before date cannot fall before the day the coffee was bagged.'
      using errcode = 'invalid_parameter_value';
  end if;

  update public.pack_run
     set best_before = p_best_before, updated_at = now()
   where pack_run_id = p_pack_run_id;

  -- 🔴 THE AMENDMENT. This function is reached from the LABEL screen, and the
  -- print button itself calls it — so a best-before printed on bags already in
  -- a customer's cafe could be rewritten with nothing recording that it had
  -- ever said anything else. pack_run_correction exists precisely to stop that
  -- (Costco 5.1.11, falsification, an automatic-failure critical) and this was
  -- the one shipped path that wrote to a closed record without using it.
  if p_best_before is distinct from v_old then
    select ses.team_member_id, pinned.name
      into v_actor, v_actor_name
      from public.terminal_actor_session ses
      join public.team pinned on pinned.team_member_id = ses.team_member_id
     where ses.ended_at is null and ses.expires_at > now()
       and ses.terminal_member_id = (select t.team_member_id from public.team t
                                      where t.auth_user_id = auth.uid() limit 1)
       -- 🔴 THIS DEVICE. `limit 1` with no device predicate and no order wrote
       -- an arbitrary signed-in person into pack_run_correction.corrected_by --
       -- a falsification record (Costco 5.1.11) naming somebody who did not
       -- make the change. Falls through to the login below when this device has
       -- nobody signed in, exactly as actor_at does.
       and (
         public.current_terminal_device() is null
         or ses.device_id is null
         or ses.device_id = public.current_terminal_device()
       )
     order by ses.started_at desc
     limit 1;
    if v_actor is null then
      select t.team_member_id, t.name into v_actor, v_actor_name
        from public.team t where t.auth_user_id = auth.uid() limit 1;
    end if;

    insert into public.pack_run_correction
      (pack_run_id, company_id, field, old_value, new_value, reason,
       corrected_by, corrected_by_name)
    values (p_pack_run_id, v_company, 'best_before',
            v_old::text, p_best_before::text,
            'Changed on the label screen',
            v_actor, v_actor_name);
  end if;

  -- Remember it, when it is a sane shelf life measured from the roast.
  if p_best_before is not null and coalesce(v_roasted, v_packed) is not null then
    v_days := p_best_before - coalesce(v_roasted, v_packed);
    if v_days between 1 and 3650 then
      insert into public.fs_settings (company_id, shelf_life_days)
      values (v_company, v_days)
      on conflict (company_id) do update
        set shelf_life_days = excluded.shelf_life_days, updated_at = now();
    else
      v_days := null;
    end if;
  end if;

  return jsonb_build_object('best_before', p_best_before, 'shelf_life_days', v_days);
end;
$function$;

do $$
declare
  n_blind int;
begin
  -- Every function that reads terminal_actor_session must now ask which
  -- device. The two that legitimately act on EVERY row are named and excluded:
  -- expire_terminal_sessions sweeps what has run out, set_terminal_enabled
  -- signs the whole login out on purpose.
  select count(*) into n_blind
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.prosrc ilike '%terminal_actor_session%'
     and p.prosrc not ilike '%device_id%'
     and p.proname not in ('expire_terminal_sessions', 'set_terminal_enabled');

  if n_blind > 0 then
    raise exception
      '% function(s) still resolve the terminal actor without asking which device', n_blind;
  end if;

  -- 🔴 Asserting a SHAPE, not this roastery's rows. Staging holds neither
  -- Spencer nor Whitney nor any terminal session, and an assertion only
  -- production can satisfy would roll the release back at the rehearsal.
  raise notice 'every terminal actor lookup is device-scoped';
end $$;

commit;
