-- Pay periods, and the report accounting runs off them.
--
-- The owner, 2026-11-24: "did you add a reports mechanism for
-- accounting/admins to access the data. set pay periods and generate reports
-- from that etc". None of it existed: the timesheet reads a rolling 34-day
-- window (WINDOW_DAYS in app/app/(app)/time/page.tsx) and a current-week
-- grid, which is a view of recent activity and not a payroll document.
--
-- 🔴 A PERIOD IS DEFINED BY THE CALENDAR AND CLOSED BY A PERSON. Asked
-- whether closing is automatic by date or instigated by an admin, the owner
-- said: "if admin then yes lock is fine. if that's industry standard." It
-- is. Gusto, ADP and QuickBooks Time all generate the period from the
-- calendar and freeze the numbers only when somebody runs payroll. A
-- midnight job cannot know whether the hours are right yet.
--
-- 🔴 SO THERE IS NO PERIOD GENERATOR, AND NO CRON. The calendar is a pure
-- function of the cadence (lib/time/payPeriod.ts), so every period that has
-- ever existed can be computed. A row in `pay_period` records a CLOSURE --
-- who froze which dates and when. No row means open, which is also what an
-- unvisited past period means, so there is no backfill to get wrong and
-- nothing to go stale if a tenant changes cadence. The one risk that buys:
-- the table cannot be used to enumerate periods. It is not asked to.
--
-- 🔴 THE PERIOD CARRIES ITS OWN ABSOLUTE BOUNDS. starts_on/ends_on are the
-- labels a human reads (2026-11-01 .. 2026-11-15); starts_at/ends_at are the
-- half-open timestamptz window that those dates meant IN THE COMPANY'S OWN
-- TIME ZONE when the period was closed. The lock trigger then compares two
-- timestamptz values and does no time-zone arithmetic at all. The zone lives
-- on `facilities.time_zone` and companyTimeZone() falls back to UTC, so a
-- trigger resolving it per row could silently shift every boundary by the
-- hours between Honolulu and UTC. Freezing the instants at closing time is
-- also the honest record: it is the window that was actually paid.
--
-- 🔴 THE LOCK IS ON THE TABLE, NOT ON THE NINE CALLERS. app/app/(app)/time/
-- actions.ts already has nine writers of time_clock_entry and will get more;
-- a check in each is a check in whichever one somebody forgets. This is the
-- same mistake as the roast delete-then-insert that locked in one caller of
-- three and 500'd the roast page.
--
-- 🔴 AND THE TRIGGER IS SECURITY DEFINER FOR A REASON. It reads `pay_period`,
-- which has RLS. A trigger function runs as the invoking user, so under RLS
-- its SELECT would return no rows for anybody the read policy does not
-- admit -- and a guard that cannot see what it guards FAILS OPEN, silently,
-- which is worse than no guard because the UI will say the period is closed.
--
-- 🔴 HOURS ONLY. No wage, no rate, no dollars: asked, the owner chose hours
-- only, so there is nothing here to protect beyond the hours themselves and
-- no new class of sensitive column. `company_labor_rate.hourly_rate` already
-- exists and is NOT this -- it prices equipment service labour on an
-- invoice. Nothing in this migration reads it, and payroll must not.

begin;

-- ============================================================
-- 1. The cadence, per company
-- ============================================================
-- One row per company. Semi-monthly is the default because it is what the
-- first roastery on this runs, and because it needs no anchor: the 1st and
-- the 16th are the same every month for ever. Weekly and biweekly DO need an
-- anchor, and the CHECK below refuses a row that claims one of those without
-- saying where the cycle starts -- a biweekly period with no anchor has no
-- defined boundary, and defaulting it would invent one.
create table if not exists public.company_pay_period_policy (
  company_id              text primary key
                            references public.companies(company_id) on delete cascade,
  cadence                 text not null default 'semi_monthly',
  anchor_on               date,
  -- 40 hours, as the FLSA and Hawai‘i both read it. Hawai‘i has no DAILY
  -- overtime rule (unlike California), so this is a weekly threshold and
  -- there is deliberately no daily one to get wrong. Stored in minutes
  -- because every other duration in this schema is.
  overtime_weekly_minutes integer not null default 2400,
  week_starts_on          smallint not null default 1,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  created_by              text,
  updated_by              text,
  constraint company_pay_period_policy_cadence_check
    check (cadence in ('weekly', 'biweekly', 'semi_monthly', 'monthly')),
  constraint company_pay_period_policy_anchor_when_needed
    check (cadence not in ('weekly', 'biweekly') or anchor_on is not null),
  constraint company_pay_period_policy_overtime_sane
    check (overtime_weekly_minutes between 0 and 10080),
  constraint company_pay_period_policy_week_start_check
    check (week_starts_on between 0 and 6)
);

grant select, insert, update on public.company_pay_period_policy to authenticated;

alter table public.company_pay_period_policy enable row level security;

-- Everybody in the company reads the cadence: the timesheet needs it to know
-- which period today falls in, and that is not privileged information.
drop policy if exists company_pay_period_policy_read on public.company_pay_period_policy;
create policy company_pay_period_policy_read
  on public.company_pay_period_policy
  for select to authenticated
  using (company_id in (select auth_company_ids()));

-- Changing when payroll runs is a payroll act, so it takes the same key as
-- closing a period rather than a separate settings key. One new key, not two:
-- the person who freezes the numbers is the person who decides the dates.
drop policy if exists company_pay_period_policy_write on public.company_pay_period_policy;
create policy company_pay_period_policy_write
  on public.company_pay_period_policy
  for all to authenticated
  using (
    company_id in (select auth_company_ids())
    and auth_has_permission('time.close_period', company_id)
  )
  with check (
    company_id in (select auth_company_ids())
    and auth_has_permission('time.close_period', company_id)
  );


-- ============================================================
-- 2. A closed period
-- ============================================================
create table if not exists public.pay_period (
  period_id   text primary key default (gen_random_uuid())::text,
  company_id  text not null references public.companies(company_id) on delete cascade,
  starts_on   date not null,
  ends_on     date not null,
  starts_at   timestamptz not null,
  ends_at     timestamptz not null,
  state       text not null default 'closed',
  closed_by   text references public.team(team_member_id) on delete set null,
  closed_at   timestamptz,
  reopened_by text references public.team(team_member_id) on delete set null,
  reopened_at timestamptz,
  note        text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  created_by  text,
  updated_by  text,
  constraint pay_period_state_check check (state in ('open', 'closed')),
  constraint pay_period_dates_ordered check (ends_on >= starts_on),
  constraint pay_period_bounds_ordered check (ends_at > starts_at),
  -- A closed period names who closed it. 🔴 DELIBERATELY ONE-DIRECTIONAL,
  -- unlike time_clock_entry_approval_has_approver. The two-way form
  -- `(state = 'closed') = (closed_by is not null)` reads better and is
  -- wrong here: reopening a period would then be forced to NULL closed_by
  -- to satisfy it, erasing the name of whoever froze the payroll in the one
  -- column that records it. An open period that remembers its last closure
  -- is exactly what an auditor needs; reopened_by/reopened_at say who undid
  -- it.
  constraint pay_period_closed_has_closer
    check (state <> 'closed' or (closed_by is not null and closed_at is not null))
);

-- One period per start date per company. This is what makes "close the
-- period starting 2026-11-16" idempotent, and what a reopen updates rather
-- than duplicating.
create unique index if not exists pay_period_company_start_uq
  on public.pay_period (company_id, starts_on);

-- The index the lock trigger reads on every single clock write, so it is
-- partial on the only state that can block one.
create index if not exists pay_period_closed_window_idx
  on public.pay_period (company_id, starts_at, ends_at)
  where state = 'closed';

grant select, insert, update on public.pay_period to authenticated;

alter table public.pay_period enable row level security;

-- Anyone in the company may see that a period is closed -- a bagger whose
-- correction is refused is entitled to know why, and the refusal message
-- names the period.
drop policy if exists pay_period_read on public.pay_period;
create policy pay_period_read
  on public.pay_period
  for select to authenticated
  using (company_id in (select auth_company_ids()));

-- 🔴 A CLOSURE NAMES ITS CLOSER, AND THE CLOSER IS THE ACTOR. Same reasoning
-- as the approval: the key says who MAY close a period, and only the
-- database can settle whose name goes on it. Without the actor_at leg a
-- holder of time.close_period could write a colleague's team_member_id into
-- closed_by and sign their name to a payroll freeze.
drop policy if exists pay_period_write on public.pay_period;
create policy pay_period_write
  on public.pay_period
  for all to authenticated
  using (
    company_id in (select auth_company_ids())
    and auth_has_permission('time.close_period', company_id)
  )
  with check (
    company_id in (select auth_company_ids())
    and auth_has_permission('time.close_period', company_id)
    and (
      state <> 'closed'
      or closed_by = (select team_member_id from public.actor_at(now()) limit 1)
    )
  );

create or replace function public.touch_pay_period()
returns trigger language plpgsql as $fn$
begin
  new.updated_at := now();
  return new;
end;
$fn$;

drop trigger if exists pay_period_touch on public.pay_period;
create trigger pay_period_touch
  before update on public.pay_period
  for each row execute function public.touch_pay_period();


-- ============================================================
-- 3. The lock
-- ============================================================
-- A shift belongs to the period containing the moment it STARTED. A night
-- shift that runs past midnight into a new period is one shift, paid in the
-- period it began -- splitting it would invent two shifts nobody worked.
--
-- UPDATE is checked on BOTH sides. Checking only the new row would let a
-- closed shift be dragged out of a frozen period, and checking only the old
-- would let an open shift be dragged into one. Either direction changes a
-- total that has already been paid.
create or replace function public.refuse_write_in_closed_pay_period()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  blocking record;
  subject  timestamptz;
  moments  timestamptz[];
  cid      text;
begin
  -- 🔴 BRANCH FIRST, THEN READ. DELETE has no NEW and INSERT has no OLD, and
  -- touching a field of an unassigned record raises "record new is not
  -- assigned yet" -- which would make a DELETE inside a closed period fail
  -- with a plpgsql internal error instead of the refusal below, or worse,
  -- turn every delete into an error whether the period is closed or not.
  -- One `coalesce(new.x, old.x)` is enough to do it, because coalesce does
  -- not short-circuit the field access.
  if tg_op = 'INSERT' then
    cid := new.company_id;
    moments := array[new.clock_in_at];
  elsif tg_op = 'DELETE' then
    cid := old.company_id;
    moments := array[old.clock_in_at];
  else
    cid := new.company_id;
    moments := array[old.clock_in_at, new.clock_in_at];
  end if;

  foreach subject in array moments loop
    select p.starts_on, p.ends_on into blocking
      from public.pay_period p
     where p.company_id = cid
       and p.state = 'closed'
       and subject >= p.starts_at
       and subject <  p.ends_at
     limit 1;

    if found then
      raise exception
        'Pay period % to % is closed, so these hours cannot be changed. Ask an administrator to reopen it.',
        blocking.starts_on, blocking.ends_on
        using errcode = 'check_violation';
    end if;
  end loop;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$fn$;

revoke all on function public.refuse_write_in_closed_pay_period() from public;

drop trigger if exists time_clock_entry_respect_closed_period on public.time_clock_entry;
create trigger time_clock_entry_respect_closed_period
  before insert or update or delete on public.time_clock_entry
  for each row execute function public.refuse_write_in_closed_pay_period();


-- ============================================================
-- 4. The one new key
-- ============================================================
-- Closing a period is its own act. Reading the report is NOT a new key:
-- time.view_all already means "read the whole company timesheet" and already
-- admits accounting_admin, which is exactly who the owner named. A second
-- read key over the same rows would be two gates on one fact, and the pair
-- would eventually disagree.
insert into public.permissions
  (permission_id, category, label, description, is_plan_gated, sort_order, default_deny_message)
values
  ('time.close_period', 'Team', 'Close a pay period',
   'Set when payroll runs, and freeze a finished period so its hours cannot change afterwards. Reopening one is the same permission.',
   true, 63,
   'You don''t have permission to close a pay period. Ask an administrator or whoever runs payroll.')
on conflict (permission_id) do update
  set category    = excluded.category,
      label       = excluded.label,
      description = excluded.description,
      is_plan_gated = excluded.is_plan_gated,
      sort_order  = excluded.sort_order,
      default_deny_message = excluded.default_deny_message,
      updated_at  = now();

-- 🔴 AND A CORRECTION TO AN EXISTING DESCRIPTION. time.approve claimed
-- "Nobody can approve their own." The policy it gates deliberately allows
-- exactly that, with its reasons written out: a roastery whose only
-- supervisor is the owner has nobody above them, and the timesheet badges
-- such a row "Approved by themselves" so it is visible rather than hidden.
-- Tested on the running app 2026-11-24; the sentence was simply wrong, and
-- a permission description is read by the person deciding who to trust.
update public.permissions
   set description = 'Rule on hand-typed shifts, correct recorded times, and enter a shift on someone else''s behalf. Approving your own typed shift is allowed and is labelled as such on the timesheet.',
       updated_at  = now()
 where permission_id = 'time.approve';

-- Closing payroll is the back office and the owner, not the floor.
-- Deliberately NOT `manager` or `roastery_manager`: they hold time.approve,
-- which decides whether somebody worked the hours, and that is a different
-- question from whether the pay run is final. accounting_admin IS here --
-- freezing a period is bookkeeping.
insert into public.role_permissions (role_id, permission_id, granted)
select r, 'time.close_period', true
from unnest(array[
  'company_admin','facility_admin','accounting_admin'
]) as r
on conflict (role_id, permission_id) do update set granted = true, updated_at = now();

-- Plan legs, matching the other three time.* keys exactly. A granted role
-- under a denying plan is a SILENT no, so both legs must agree.
insert into public.plan_permissions (plan_id, permission_id, granted, updated_reason)
select p, 'time.close_period', true, 'pay periods ship with hours tracking, which is pro and up'
from unnest(array['pro','enterprise','enterprise_plus']) as p
on conflict (plan_id, permission_id) do update set granted = true, updated_at = now();

insert into public.plan_permissions (plan_id, permission_id, granted, updated_reason)
values ('starter', 'time.close_period', false, 'hours tracking starts at pro')
on conflict (plan_id, permission_id) do update set granted = false, updated_at = now();


-- ============================================================
-- 5. Verify
-- ============================================================
-- Structure only, deliberately. A verify block that writes a test row to
-- prove the trigger fires would have to delete it again inside the same
-- transaction that is shipping the release, and a block that can only RAISE
-- rolls the whole migration back. The trigger's behaviour is rehearsed by
-- CI's db-push-staging and then exercised on staging through the app.
do $verify$
declare
  n integer;
begin
  -- The two tables, with RLS actually on.
  select count(*) into n from pg_class
   where relname in ('company_pay_period_policy', 'pay_period')
     and relnamespace = 'public'::regnamespace
     and relrowsecurity;
  if n <> 2 then
    raise exception 'expected 2 new tables with RLS enabled, found %', n;
  end if;

  -- Four policies: a read and a write on each.
  select count(*) into n from pg_policies
   where tablename in ('company_pay_period_policy', 'pay_period');
  if n <> 4 then
    raise exception 'expected 4 policies on the two new tables, found %', n;
  end if;

  -- The lock, on all three operations, and SECURITY DEFINER -- without which
  -- it reads pay_period under RLS and fails open.
  if not exists (
    select 1 from pg_trigger
     where tgrelid = 'public.time_clock_entry'::regclass
       and tgname = 'time_clock_entry_respect_closed_period'
  ) then
    raise exception 'the closed-period trigger is not on time_clock_entry';
  end if;

  if not exists (
    select 1 from pg_proc
     where oid = 'public.refuse_write_in_closed_pay_period()'::regprocedure
       and prosecdef
  ) then
    raise exception 'refuse_write_in_closed_pay_period must be SECURITY DEFINER';
  end if;

  -- The grants, which a new table does not get for free.
  select count(*) into n from information_schema.role_table_grants
   where table_name in ('company_pay_period_policy', 'pay_period')
     and grantee = 'authenticated'
     and privilege_type in ('SELECT', 'INSERT', 'UPDATE');
  if n <> 6 then
    raise exception 'expected 6 authenticated grants across the two tables, found %', n;
  end if;

  -- Both legs of the key, or it is a silent deny.
  select count(*) into n from public.role_permissions
   where permission_id = 'time.close_period' and granted;
  if n <> 3 then
    raise exception 'expected 3 roles granted time.close_period, found %', n;
  end if;

  select count(*) into n from public.plan_permissions
   where permission_id = 'time.close_period' and granted;
  if n <> 3 then
    raise exception 'expected 3 plans granting time.close_period, found %', n;
  end if;

  -- The correction actually landed.
  if exists (
    select 1 from public.permissions
     where permission_id = 'time.approve'
       and description like '%Nobody can approve their own%'
  ) then
    raise exception 'time.approve still claims nobody can approve their own';
  end if;

  raise notice 'pay periods: 2 tables, 4 policies, the lock, 3 roles, 3 plans, and the time.approve correction';
end
$verify$;

commit;
