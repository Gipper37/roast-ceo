-- A terminal may be told never to lock.
--
-- Owner, 2026-09-26: *"a roastmaster should never be interrupted so a lock
-- screen should only happen when no cards are up and no roasts are going. and
-- to be honest we'll probably deactivate it for roastmaster anyway but we can
-- leave it as an option in settings."*
--
-- The app side now holds the lock off while a roast is live or a dialog is
-- open. This is the other half: letting a roastery switch it off for a role
-- outright, for the machine that lives beside one roaster and is never shared.
--
-- `terminal_role_autolock.autolock_seconds` was bounded 30..3600, mirroring
-- company_terminal_policy, so "never" could not be said. 0 now means never —
-- a value the company-wide column still refuses, because the default that
-- applies to every shared terminal should not be switchable off by accident.
-- Absence of a row still means "use the company default"; 0 is a deliberate
-- statement, and the two are different answers.
--
-- 🔴 The resolver returns 0 unchanged. The client treats a non-positive
-- autolock as "do not run the idle timer at all" rather than "lock instantly",
-- which is the failure mode a naive 0 would produce.

begin;

alter table public.terminal_role_autolock
  drop constraint if exists terminal_role_autolock_seconds_check;

alter table public.terminal_role_autolock
  add constraint terminal_role_autolock_seconds_check
  check (autolock_seconds = 0 or (autolock_seconds >= 30 and autolock_seconds <= 3600));

comment on column public.terminal_role_autolock.autolock_seconds is
  'Seconds a person in this role may leave the terminal idle before it locks '
  'and PINs them out. 0 = never lock, for a machine that belongs to one person. '
  'No row at all = use company_terminal_policy.autolock_seconds.';

do $verify$
declare v_bad int;
begin
  -- 0 is now sayable for a role...
  begin
    insert into public.terminal_role_autolock (company_id, role_id, autolock_seconds)
    select c.company_id, 'roastmaster', 0 from public.companies c limit 1
    on conflict (company_id, role_id) do update set autolock_seconds = 0;
    raise exception 'probe_ok';
  exception
    when check_violation then raise exception 'a role still cannot be told never to lock';
    when others then if sqlerrm <> 'probe_ok' then raise; end if;
  end;

  -- ...and anything between 1 and 29 is still refused, so a typo cannot make a
  -- terminal lock every few seconds.
  begin
    insert into public.terminal_role_autolock (company_id, role_id, autolock_seconds)
    select c.company_id, 'roastmaster', 5 from public.companies c limit 1
    on conflict (company_id, role_id) do update set autolock_seconds = 5;
    raise exception 'a 5-second lock was accepted';
  exception
    when check_violation then null;
  end;

  -- The company-wide default is NOT switchable off — it is what every shared
  -- terminal falls back to.
  select count(*) into v_bad from pg_constraint
   where conname = 'company_terminal_policy_autolock_seconds_check'
     and pg_get_constraintdef(oid) like '%>= 30%';
  if v_bad <> 1 then
    raise exception 'the company-wide autolock floor is no longer 30 seconds';
  end if;

  raise notice 'a role may now be set to 0 = never lock; the company default still cannot be';
end $verify$;

commit;
