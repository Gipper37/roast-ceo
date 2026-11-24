-- A hand edit says so, a self-update stays in its own company, and a reopen
-- names its own reopener.
--
-- Three holes found by the 24-hour audit of everything pushed on 2026-11-23,
-- all of them in the hours module, all of them read straight out of
-- pg_policies on production rather than inferred from the migration text.
--
-- 1. time_clock_entry_self_update's WITH CHECK is three terms where its USING
--    is five. It omits the tenancy predicate and the permission, and a WITH
--    CHECK does NOT fall back to USING: the USING clause chooses the row, the
--    WITH CHECK judges the row that comes out. So the one write a worker is
--    allowed to make on their own shift -- clocking out -- could also move
--    that shift into another company, and the policy had nothing to say.
--
-- 2. Nothing pins the TIMES on that write. The worker's own policy admits an
--    UPDATE while approval_state is 'not_required' or 'pending', which is
--    every shift that has not been ruled on, and nothing stopped the same
--    request rewriting clock_in_at and leaving source 'self'. The hours then
--    read as clock-recorded, which is the one thing the source column exists
--    to say. The rule the actions already follow -- a time somebody typed is
--    'manual' and waits for a supervisor -- is enforced here now, so it holds
--    whatever sends the request.
--
--    An ordinary clock-out is NOT a hand edit: it closes an open shift with
--    the server's own now(). A clock-out carrying any other time was typed by
--    a person, which is exactly what closeForgottenShift does and exactly
--    what it already marks. Two minutes of slack for the round trip.
--
--    The same policy also admitted a write that moved NO time and simply set
--    approval_state back to 'not_required' with approved_by null, erasing a
--    supervisor's ruling and their name. A WITH CHECK cannot refuse that --
--    it never sees OLD -- so for anybody without time.approve the trigger now
--    decides source and all three approval columns outright, and whatever the
--    request sent for them is discarded.
--
-- 3. pay_period_write pins closed_by to the actor only while state = 'closed'.
--    Reopening a period is a write that leaves that state, so on the way out
--    both closed_by and reopened_by were unconstrained: a reopen could sign
--    somebody else's name as the reopener AND rewrite the name of whoever
--    closed it. Nobody can pin OLD from a policy, so these are stamped by a
--    trigger -- the same rule as f189f89, an approval names its approver and
--    the approver is the actor, applied to the other end of the same row.
--
-- No new permission key: every key these touch already ships in
-- 20261123000004 and 20261123000006.

begin;

-- ──────────────────────────────────────────────────────────────────────
-- 1. The self-update judges the row it produces, tenancy included.
-- ──────────────────────────────────────────────────────────────────────
drop policy if exists time_clock_entry_self_update on public.time_clock_entry;
create policy time_clock_entry_self_update
  on public.time_clock_entry
  for update to authenticated
  using (
    company_id in (select auth_company_ids())
    and auth_has_permission('time.clock', company_id)
    and team_member_id = (select team_member_id from public.actor_at(now()) limit 1)
  )
  with check (
    -- 🔴 THE SAME THREE TERMS AS THE USING, because a WITH CHECK that leaves
    -- one out is not a weaker rule about the same row -- it is no rule at all
    -- about the row being written. Without the first two a worker's own
    -- clock-out could carry company_id somewhere else entirely.
    company_id in (select auth_company_ids())
    and auth_has_permission('time.clock', company_id)
    and team_member_id = (select team_member_id from public.actor_at(now()) limit 1)
    and approval_state = any (array['not_required', 'pending'])
    and approved_by is null
  );

-- ──────────────────────────────────────────────────────────────────────
-- 2. A time somebody typed is 'manual', and waits for a supervisor.
-- ──────────────────────────────────────────────────────────────────────
create or replace function public.time_clock_entry_mark_hand_edit()
 returns trigger
 language plpgsql
as $function$
declare
  v_typed boolean := false;
begin
  -- Only a request carrying a person. A maintenance write, a backfill or
  -- anything running as the service role has no actor and no permission map,
  -- and relabelling those rows 'manual' would say a person edited hours that
  -- nobody touched.
  --
  -- current_user, not auth.role(): PostgREST switches the session's Postgres
  -- role from the token, so this IS the security context rather than a claim
  -- about it (a claim is what a JWT carries), and it asks nothing of the auth
  -- schema. A rehearsal caught the difference: this trigger fires on every
  -- clock-out, and a cross-schema dependency in that path is one grant away
  -- from taking the clock down.
  if current_user <> 'authenticated' then
    return new;
  end if;

  -- A start time that moved is always a hand edit. Nothing stamps clock_in_at
  -- after the fact except a person typing it.
  if new.clock_in_at is distinct from old.clock_in_at then
    v_typed := true;
  end if;

  if old.clock_out_at is null and new.clock_out_at is not null then
    -- Closing an open shift. The clock itself writes now(), so a finish time
    -- that is not now was typed -- which is what the forgotten-clock-out
    -- prompt collects, and what it already marks for itself.
    if new.clock_out_at < now() - interval '2 minutes'
       or new.clock_out_at > now() + interval '2 minutes' then
      v_typed := true;
    end if;
  elsif new.clock_out_at is distinct from old.clock_out_at then
    -- A finish time that was already recorded and has now moved, cleared
    -- included: reopening a closed shift is not something the clock does.
    v_typed := true;
  end if;

  -- Somebody who may approve hours is amending on the record, and the action
  -- stamps the approval in their name (amendEntry requires time.approve, so
  -- that is the only route to this branch).
  if auth_has_permission('time.approve', new.company_id) then
    return new;
  end if;

  -- 🔴 FOR ANYBODY ELSE, THESE FOUR COLUMNS ARE NOT FIELDS A BROWSER SENDS.
  -- Provenance and the ruling are facts about the row, so the trigger decides
  -- them on every self-update and the request's values are discarded.
  --
  -- A rehearsal is why this is a return-early and not an `if v_typed`. With
  -- the relabel alone, a worker could still PATCH approval_state back to
  -- 'not_required' with approved_by null and TOUCH NO TIME -- the WITH CHECK
  -- admits that row, and v_typed was false, so the supervisor's ruling and
  -- their name were erased with nothing marked. That is the second half of
  -- the same finding, and only OLD can refuse it.
  if v_typed then
    -- They changed the hours, so any earlier ruling is void -- but it is
    -- marked pending for review, never erased. 'pending' also keeps the row
    -- inside the worker's own policy, so marking it does not lock them out
    -- of the clock-out they still have to make.
    new.source         := 'manual';
    new.approval_state := 'pending';
    new.approved_by    := null;
    new.approved_at    := null;
  else
    -- No time moved: the ruling and the provenance stand exactly as they are.
    new.source         := old.source;
    new.approval_state := old.approval_state;
    new.approved_by    := old.approved_by;
    new.approved_at    := old.approved_at;
  end if;

  return new;
end;
$function$;

-- Before the other two BEFORE triggers by name, which is harmless: it writes
-- only source and the approval columns, and neither of those reads them.
drop trigger if exists time_clock_entry_mark_hand_edit on public.time_clock_entry;
create trigger time_clock_entry_mark_hand_edit
  before update on public.time_clock_entry
  for each row execute function public.time_clock_entry_mark_hand_edit();

-- ──────────────────────────────────────────────────────────────────────
-- 3. Who closed it, and who reopened it, are both facts about a person.
-- ──────────────────────────────────────────────────────────────────────
create or replace function public.pay_period_stamp_actor()
 returns trigger
 language plpgsql
as $function$
declare
  v_actor text;
begin
  -- See the note in time_clock_entry_mark_hand_edit: the security context,
  -- not a claim about it.
  if current_user <> 'authenticated' then
    return new;
  end if;

  select team_member_id into v_actor from public.actor_at(now()) limit 1;

  if tg_op = 'INSERT' then
    -- A period is created open. One created closed is signed by whoever
    -- created it, and never by a name sent from a browser.
    if new.state = 'closed' then
      new.closed_by := v_actor;
      new.closed_at := coalesce(new.closed_at, now());
    else
      new.closed_by := null;
      new.closed_at := null;
    end if;
    new.reopened_by := null;
    new.reopened_at := null;
    return new;
  end if;

  -- 🔴 HISTORY IS NOT REWRITTEN BY THE NEXT WRITE. Outside the transition
  -- that creates them, both pairs come back from the row as it stands: a
  -- reopen leaves the closer's name where it was, and a later close does not
  -- erase the reopen that preceded it.
  --
  -- closePayPeriod is an upsert, so a re-close arrives here as an UPDATE
  -- sending reopened_by => null. That null is overridden deliberately: the
  -- period was reopened, and the row should say so. PayPeriodTab prints the
  -- reopen clause only while the period is OPEN, so nothing stale reaches
  -- the screen -- and a closure row that outlived a reopen is exactly what
  -- the reopen dialog promises the closer.
  if new.state = 'closed' and old.state is distinct from 'closed' then
    new.closed_by := v_actor;
    new.closed_at := coalesce(new.closed_at, now());
  else
    new.closed_by := old.closed_by;
    new.closed_at := old.closed_at;
  end if;

  if old.state = 'closed' and new.state is distinct from 'closed' then
    new.reopened_by := v_actor;
    new.reopened_at := coalesce(new.reopened_at, now());
  else
    new.reopened_by := old.reopened_by;
    new.reopened_at := old.reopened_at;
  end if;

  return new;
end;
$function$;

drop trigger if exists pay_period_stamp_actor on public.pay_period;
create trigger pay_period_stamp_actor
  before insert or update on public.pay_period
  for each row execute function public.pay_period_stamp_actor();

-- ──────────────────────────────────────────────────────────────────────
-- What this leaves behind, asserted rather than assumed.
--
-- Both halves can fail: the first counts the terms of a policy that was three
-- and must now be five, the second counts two triggers that did not exist
-- before this file ran. Neither is a tautology, and neither can only pass.
-- ──────────────────────────────────────────────────────────────────────
do $verify$
declare
  v_check text;
  v_triggers int;
begin
  select with_check into v_check
    from pg_policies
   where tablename = 'time_clock_entry'
     and policyname = 'time_clock_entry_self_update';

  if v_check is null then
    raise exception 'time_clock_entry_self_update has no WITH CHECK';
  end if;
  if v_check not like '%auth_company_ids%' then
    raise exception 'time_clock_entry_self_update WITH CHECK is still missing the tenancy predicate: %', v_check;
  end if;
  if v_check not like '%time.clock%' then
    raise exception 'time_clock_entry_self_update WITH CHECK is still missing the permission: %', v_check;
  end if;

  select count(*) into v_triggers
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
   where not t.tgisinternal
     and ((c.relname = 'time_clock_entry' and t.tgname = 'time_clock_entry_mark_hand_edit')
       or (c.relname = 'pay_period' and t.tgname = 'pay_period_stamp_actor'));

  if v_triggers <> 2 then
    raise exception 'expected both stamping triggers, found %', v_triggers;
  end if;
end
$verify$;

commit;
