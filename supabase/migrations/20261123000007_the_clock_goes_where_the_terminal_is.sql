-- ============================================================
-- The clock goes where the terminal is
-- ============================================================
-- The four time.* keys move from pro-and-up to enterprise_plus only,
-- joining terminal.manage and team.floor_staff.
--
-- 🔴 WHY. The owner asked whether staff can PIN in on pro. They cannot, and
-- the database says so plainly: terminal_pin_in raises
--
--     'This login is not a shared terminal.'
--
-- unless the calling login is itself a terminal, and marking a login as one
-- goes through terminal.manage (app/app/(app)/company/actions.ts:856, 1196,
-- 1221, 1256), which is enterprise_plus. The people who are supposed to
-- create non-login staff -- team.floor_staff, "packers, cleaners, seasonal
-- help... they hold no account" -- are enterprise_plus too. So a pro roastery
-- was sold a time clock that its hourly staff physically cannot reach: the
-- feature only worked for people who already hold a login, which is the set
-- of people least likely to punch a clock.
--
-- Selling the clock without the tablet and without the staff is the kind of
-- half-feature that reads as a bug to whoever bought it.
--
-- 🔴 NOTE THIS ALSO TAKES IT FROM `enterprise`, not just `pro`. That is the
-- point rather than an oversight: the question was where terminal login
-- lives, and it lives at enterprise_plus alone. If the clock should instead
-- stay at enterprise, the honest fix is to move terminal.manage and
-- team.floor_staff DOWN to meet it -- a different migration, and a different
-- decision about what enterprise_plus is for.
--
-- Measured on prod before writing this, so the blast radius is known: every
-- live tenant is already enterprise_plus (4 companies, plus 1 with no
-- subscription row), 5 staff have time_clock_enabled, 1 terminal exists.
-- Nobody is on pro or starter, so no live customer loses anything today.
-- This is packaging for the customers who come next.
--
-- Data only. No table, function, policy or grant changes, and the four keys
-- keep their roles, their labels and their sort order.

begin;

-- pro and enterprise lose all four. enterprise_plus already has them and is
-- left alone; starter already denied them and is left alone.
insert into public.plan_permissions (plan_id, permission_id, granted, updated_reason)
select p, k, false,
       'the clock needs a shared terminal and non-login staff, both enterprise_plus'
from unnest(array['pro','enterprise']) as p
cross join unnest(array[
  'time.clock','time.view_all','time.approve','time.close_period'
]) as k
on conflict (plan_id, permission_id) do update
  set granted = false,
      updated_reason = excluded.updated_reason,
      updated_at = now();


-- ============================================================
-- Verify
-- ============================================================
-- 🔴 The assertion is that the clock and its two preconditions now admit
-- EXACTLY the same plans. Checking the four keys alone would pass just as
-- happily if somebody later moved terminal.manage and left these behind,
-- which is the disagreement this migration exists to end.
do $verify$
declare
  clock_plans   text;
  gate_plans    text;
  n             integer;
begin
  select string_agg(distinct plan_id, ',' order by plan_id) into clock_plans
    from public.plan_permissions
   where permission_id in ('time.clock','time.view_all','time.approve','time.close_period')
     and granted;

  select string_agg(distinct plan_id, ',' order by plan_id) into gate_plans
    from public.plan_permissions
   where permission_id in ('terminal.manage','team.floor_staff')
     and granted;

  if clock_plans is distinct from gate_plans then
    raise exception
      'the clock admits % but its terminal/floor-staff gates admit %',
      coalesce(clock_plans, '(none)'), coalesce(gate_plans, '(none)');
  end if;

  -- All four moved, not three: a cross join that silently dropped one would
  -- otherwise pass the comparison above on the strength of the others.
  select count(*) into n
    from public.plan_permissions
   where permission_id in ('time.clock','time.view_all','time.approve','time.close_period')
     and plan_id in ('pro','enterprise')
     and not granted;
  if n <> 8 then
    raise exception 'expected 8 denials across pro+enterprise for the 4 time keys, found %', n;
  end if;

  -- The roles are untouched. This migration is about plans only, and a key
  -- that lost its roles would be a silent deny on every plan.
  select count(*) into n
    from public.role_permissions
   where permission_id = 'time.close_period' and granted;
  if n <> 3 then
    raise exception 'time.close_period should still name 3 roles, found %', n;
  end if;

  raise notice 'the clock now admits exactly: %', clock_plans;
end;
$verify$;

commit;
