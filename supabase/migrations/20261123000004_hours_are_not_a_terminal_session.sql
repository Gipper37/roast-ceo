-- Clock in, clock out, and the hours that come out of it.
--
-- There is no time tracking in STRATA at all: no table whose name contains
-- time, clock, shift or attendance exists. Hours on a service visit are
-- typed into the visit; hours in the warehouse are nowhere. The owner asked
-- for both, 2026-11-23: "we need clock in/out and hours tracking for
-- warehouse too".
--
-- 🔴 WHY NOT `terminal_actor_session`. It already records who was PIN'd in
-- and when, which looks exactly like a shift and is not one: it AUTOLOCKS on
-- idle (company_terminal_policy.autolock_seconds) and expires on
-- session_max_hours. Reading hours out of it would bill a bagger for the
-- gaps between PIN-ins and stop the clock the moment they walked to the
-- cooler. A PIN-in is the TRIGGER for a clock-in prompt; it is not the
-- labour record. This table is.
--
-- WHO IS CLOCKING. `actor_at(now())` -- the PIN'd-in person at a terminal,
-- the signed-in person otherwise. The same function the roast log and the
-- maintenance log already stamp their records with, so a shared bagging
-- terminal attributes a shift to the person standing at it and not to the
-- machine's login. This is the first RLS policy in the schema to call it;
-- it is SECURITY DEFINER, STABLE and EXECUTE-granted to authenticated,
-- checked not assumed, and it is wrapped in a scalar subquery so it is an
-- InitPlan evaluated once rather than per row.
--
-- 🔴 ONE OPEN ENTRY PER PERSON, enforced by a partial unique index rather
-- than by the app. Two open entries is the state from which every hours
-- number is wrong, and three callers will eventually open one.
--
-- 🔴 OPEN/CLOSED IS ONE COLUMN. `clock_out_at IS NULL` means on the clock,
-- full stop. There is deliberately no second "status" column that could say
-- otherwise -- "PAID IS TWO COLUMNS" is the mistake this avoids.
-- `approval_state` is an orthogonal fact: whether a supervisor has blessed a
-- hand-typed entry. A shift can be closed and unapproved, or open and
-- irrelevant to approval.
--
-- 🔴 NEW COLUMN ON `team` NEEDS ITS OWN GRANT, CHECKED NOT ASSUMED: `team`
-- has NO table-level INSERT or UPDATE for `authenticated` -- it runs on 82
-- column-level grants. A column added without its grant is readable by the
-- UI and silently unsaveable. The verify block asserts the grant.

begin;

-- ============================================================
-- 1. Per-employee opt-in
-- ============================================================
-- The owner's words: "from the company page it should be a toggle for each
-- employee". This IS the opt-in -- no tenant-level module switch as well.
-- Nobody toggled on means nothing appears, which is the right default for a
-- roastery that does not track hours.
alter table public.team
  add column if not exists time_clock_enabled boolean not null default false;

comment on column public.team.time_clock_enabled is
  'Does this person clock in and out? Set per employee on the company page. False means the clock UI never appears for them and no entries are expected.';

grant select (time_clock_enabled), insert (time_clock_enabled), update (time_clock_enabled)
  on public.team to authenticated;


-- ============================================================
-- 2. The shifts
-- ============================================================
create table if not exists public.time_clock_entry (
  entry_id        text primary key default gen_random_uuid()::text,
  company_id      text not null references public.companies(company_id) on delete cascade,
  team_member_id  text not null references public.team(team_member_id) on delete cascade,
  -- Where the shift was worked. Drives the local day boundary: a shift
  -- belongs to the day it started in the FACILITY's timezone
  -- (facilities.time_zone), never UTC.
  facility_id     text references public.facilities(facility_id) on delete set null,

  clock_in_at     timestamptz not null default now(),
  -- NULL means on the clock. The only open/closed signal there is.
  clock_out_at    timestamptz,

  -- How the entry came to be.
  --   self       clocked themselves in on their own login
  --   terminal   PIN'd in at a shared terminal
  --   manual     typed after the fact, by the worker or a supervisor
  --   auto_close closed by the system after a forgotten clock-out
  source          text not null default 'self'
    check (source in ('self', 'terminal', 'manual', 'auto_close')),

  -- Orthogonal to open/closed: has a supervisor blessed a hand-typed entry.
  --   not_required  the clock recorded it; nothing to approve
  --   pending       typed by hand, waiting on a supervisor
  --   approved / rejected  a supervisor has ruled
  approval_state  text not null default 'not_required'
    check (approval_state in ('not_required', 'pending', 'approved', 'rejected')),

  clock_in_device_id  text,
  clock_out_device_id text,
  -- What the worker said: "forgot to clock out, left at 5".
  note            text,

  -- The supervisor leg. The owner's words: "a manually input would have to
  -- be approved by a supervisor and marked differently".
  approved_by     text references public.team(team_member_id) on delete set null,
  approved_at     timestamptz,
  review_note     text,

  -- Derived, so no reader computes it differently. GENERATED, not a BEFORE
  -- trigger: Postgres refuses a write to it, where a trigger only overwrites
  -- one and leaves the caller believing their value stuck.
  worked_minutes  int generated always as (
    case when clock_out_at is null then null
         else (extract(epoch from (clock_out_at - clock_in_at)) / 60)::int
    end
  ) stored,

  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  created_by      text,
  updated_by      text,

  -- A shift cannot end before it starts. Equality is excluded too: a
  -- zero-length shift is a mis-click, and letting it through puts a row in
  -- the timesheet that nobody can explain.
  constraint time_clock_entry_ends_after_start
    check (clock_out_at is null or clock_out_at > clock_in_at),

  -- A hand-typed entry always carries a verdict, even 'rejected'. Without
  -- this a manual entry could sit as 'not_required' and never be reviewed,
  -- which is the whole point of marking it differently.
  constraint time_clock_entry_manual_needs_review
    check (source <> 'manual' or approval_state <> 'not_required'),

  -- An approval names its approver, and an approver implies a ruling.
  constraint time_clock_entry_approval_has_approver
    check (
      (approval_state in ('approved', 'rejected')) = (approved_by is not null)
    )
);

comment on table public.time_clock_entry is
  'One row per shift. clock_out_at IS NULL means on the clock. Separate from terminal_actor_session on purpose: that autolocks on idle and is not a labour record.';

-- 🔴 At most one open shift per person. The invariant every hours number
-- depends on, kept by the database rather than by whichever caller
-- remembers to look.
create unique index if not exists time_clock_entry_one_open_per_member
  on public.time_clock_entry (team_member_id)
  where clock_out_at is null;

-- The timesheet read: one person, newest first.
create index if not exists time_clock_entry_member_idx
  on public.time_clock_entry (team_member_id, clock_in_at desc);
-- The company timesheet and the approval queue.
create index if not exists time_clock_entry_company_idx
  on public.time_clock_entry (company_id, clock_in_at desc);
create index if not exists time_clock_entry_pending_idx
  on public.time_clock_entry (company_id, approval_state)
  where approval_state = 'pending';

grant select, insert, update, delete on public.time_clock_entry to authenticated;

-- updated_at, the same way every other table does it.
create or replace function public.touch_time_clock_entry()
returns trigger language plpgsql as $fn$
begin
  new.updated_at := now();
  return new;
end;
$fn$;

drop trigger if exists time_clock_entry_touch on public.time_clock_entry;
create trigger time_clock_entry_touch
  before update on public.time_clock_entry
  for each row execute function public.touch_time_clock_entry();


-- ============================================================
-- 3. RLS
-- ============================================================
alter table public.time_clock_entry enable row level security;

-- Your own shifts. At a terminal "your own" is the PIN'd-in person's,
-- which is what actor_at resolves.
--
-- 🔴 This names time.clock as well, and the reason is the plan leg. Without
-- it a tenant downgraded to starter keeps serving every member's own shift
-- history over PostgREST while the app shows no time-clock screen at all:
-- "the toggle was display-only" is the exact failure auth_has_permission's
-- own comments were written about. The rows are not deleted -- an upgrade
-- brings them straight back.
create policy time_clock_entry_self_read
  on public.time_clock_entry
  for select to authenticated
  using (
    company_id in (select auth_company_ids())
    and auth_has_permission('time.clock', company_id)
    and team_member_id = (select team_member_id from public.actor_at(now()) limit 1)
  );

-- Everyone's shifts, for the people who run payroll and the floor.
create policy time_clock_entry_all_read
  on public.time_clock_entry
  for select to authenticated
  using (
    company_id in (select auth_company_ids())
    and auth_has_permission('time.view_all', company_id)
  );

-- Clocking yourself in. The row must be YOURS: without this check a holder
-- of time.clock could open a shift in somebody else's name.
create policy time_clock_entry_self_insert
  on public.time_clock_entry
  for insert to authenticated
  with check (
    company_id in (select auth_company_ids())
    and auth_has_permission('time.clock', company_id)
    and team_member_id = (select team_member_id from public.actor_at(now()) limit 1)
    -- You cannot clock yourself in as already-approved, nor sign your own
    -- hand-typed entry off. That is what time.approve is for.
    and approval_state in ('not_required', 'pending')
    and approved_by is null
  );

-- Clocking yourself out, or correcting your own entry. Still yours, and
-- still cannot self-approve.
create policy time_clock_entry_self_update
  on public.time_clock_entry
  for update to authenticated
  using (
    company_id in (select auth_company_ids())
    and auth_has_permission('time.clock', company_id)
    and team_member_id = (select team_member_id from public.actor_at(now()) limit 1)
  )
  with check (
    team_member_id = (select team_member_id from public.actor_at(now()) limit 1)
    and approval_state in ('not_required', 'pending')
    and approved_by is null
  );

-- A supervisor: approve, reject, amend, or enter a shift on someone's
-- behalf. This is the only way a row reaches 'approved'.
create policy time_clock_entry_approve_write
  on public.time_clock_entry
  for all to authenticated
  using (
    company_id in (select auth_company_ids())
    and auth_has_permission('time.approve', company_id)
  )
  with check (
    company_id in (select auth_company_ids())
    and auth_has_permission('time.approve', company_id)
  );


-- ============================================================
-- 4. The three keys
-- ============================================================
-- Three distinct acts, not one key with three meanings: clocking yourself
-- in, reading everybody's hours, and ruling on a hand-typed entry. Folding
-- them together would mean a bagger who can clock in can also approve their
-- own corrections, which is the one thing the approval exists to prevent.
insert into public.permissions
  (permission_id, category, label, description, is_plan_gated, sort_order, default_deny_message)
values
  ('time.clock', 'Team', 'Clock in and out',
   'Start and end your own shifts, and type a shift you forgot to record. A typed shift waits on a supervisor.',
   true, 60,
   'You don''t have permission to use the time clock. Ask an administrator to turn it on for you.'),
  ('time.view_all', 'Team', 'See everyone''s hours',
   'Read the whole company timesheet, not just your own shifts. For payroll and for running the floor.',
   true, 61,
   'You don''t have permission to see other people''s hours. You can still see your own.'),
  ('time.approve', 'Team', 'Approve and amend hours',
   'Rule on hand-typed shifts, correct recorded times, and enter a shift on someone else''s behalf. Nobody can approve their own.',
   true, 62,
   'You don''t have permission to approve hours. Ask a supervisor or an administrator.')
on conflict (permission_id) do update
  set category    = excluded.category,
      label       = excluded.label,
      description = excluded.description,
      is_plan_gated = excluded.is_plan_gated,
      sort_order  = excluded.sort_order,
      default_deny_message = excluded.default_deny_message,
      updated_at  = now();

-- time.clock: everyone who does the work. Including the roles that run the
-- place, because a manager who cannot clock in cannot test what they just
-- turned on for their staff.
insert into public.role_permissions (role_id, permission_id, granted)
select r, 'time.clock', true
from unnest(array[
  'company_admin','facility_admin','manager','roastery_manager',
  'roastmaster','assistant_roaster','equipment_tech','staff','sales_person'
]) as r
on conflict (role_id, permission_id) do update set granted = true, updated_at = now();

-- time.view_all: the floor and the back office. accounting_admin is here
-- because hours are a payroll input; accounting_view is not, because it
-- reads money and hours are not money yet.
insert into public.role_permissions (role_id, permission_id, granted)
select r, 'time.view_all', true
from unnest(array[
  'company_admin','facility_admin','manager','roastery_manager','accounting_admin'
]) as r
on conflict (role_id, permission_id) do update set granted = true, updated_at = now();

-- time.approve: supervisors only. Deliberately NOT accounting_admin --
-- reading hours for payroll is not the same as deciding whether somebody
-- worked them, and the person who signs the cheque should not be the person
-- who decides the hours.
insert into public.role_permissions (role_id, permission_id, granted)
select r, 'time.approve', true
from unnest(array[
  'company_admin','facility_admin','manager','roastery_manager'
]) as r
on conflict (role_id, permission_id) do update set granted = true, updated_at = now();

-- Plan legs. Ordinary operational keys in this schema are granted on pro and
-- up and denied on starter (inventory.*, pack.*, roast.* all read this way);
-- enterprise_plus-only is reserved for the terminal and floor-staff
-- features. Hours tracking is ordinary operations, so: pro and up.
-- A granted role under a denying plan is a SILENT no, so both legs must agree.
insert into public.plan_permissions (plan_id, permission_id, granted, updated_reason)
select p, k, true, 'hours tracking is ordinary operations, matching inventory.* and pack.*'
from unnest(array['pro','enterprise','enterprise_plus']) as p
cross join unnest(array['time.clock','time.view_all','time.approve']) as k
on conflict (plan_id, permission_id) do update set granted = true, updated_at = now();

-- Named denies for starter, so the gate reads deliberately rather than
-- relying on an absent row.
insert into public.plan_permissions (plan_id, permission_id, granted, updated_reason)
select 'starter', k, false, 'hours tracking starts at pro'
from unnest(array['time.clock','time.view_all','time.approve']) as k
on conflict (plan_id, permission_id) do update set granted = false, updated_at = now();


-- ============================================================
-- 5. Verify
-- ============================================================
do $$
declare
  v_n int;
  v_t text;
begin
  -- The toggle, and the grant without which it is read-only.
  if not exists (
    select 1 from information_schema.columns
     where table_schema='public' and table_name='team' and column_name='time_clock_enabled'
  ) then
    raise exception 'team.time_clock_enabled is missing';
  end if;

  select count(*) into v_n from information_schema.column_privileges
   where table_schema='public' and table_name='team' and column_name='time_clock_enabled'
     and grantee='authenticated' and privilege_type='UPDATE';
  if v_n <> 1 then
    raise exception 'team.time_clock_enabled has no UPDATE grant for authenticated: the toggle would be silently unsaveable';
  end if;

  -- CONTROL: `team` really is column-granted, which is WHY that grant was
  -- needed. If the table ever gains a table-level UPDATE this assertion
  -- fails and the comment above stops being true.
  select count(*) into v_n from information_schema.table_privileges
   where table_schema='public' and table_name='team'
     and grantee='authenticated' and privilege_type='UPDATE';
  if v_n <> 0 then
    raise exception 'team now has a table-level UPDATE grant; the column-grant reasoning in this migration is stale';
  end if;

  -- The table and its one invariant.
  if not exists (
    select 1 from information_schema.tables
     where table_schema='public' and table_name='time_clock_entry'
  ) then
    raise exception 'time_clock_entry is missing';
  end if;

  if not exists (
    select 1 from pg_indexes
     where schemaname='public' and tablename='time_clock_entry'
       and indexname='time_clock_entry_one_open_per_member'
  ) then
    raise exception 'the one-open-shift-per-person index is missing';
  end if;

  -- worked_minutes must be GENERATED, not merely present: a plain column
  -- here would be writable and would drift from the timestamps.
  select is_generated into v_t from information_schema.columns
   where table_schema='public' and table_name='time_clock_entry' and column_name='worked_minutes';
  if coalesce(v_t, 'NEVER') <> 'ALWAYS' then
    raise exception 'worked_minutes is not a generated column (is_generated=%)', coalesce(v_t, 'missing');
  end if;

  -- RLS on, and every policy present.
  if not exists (
    select 1 from pg_class where oid='public.time_clock_entry'::regclass and relrowsecurity
  ) then
    raise exception 'RLS is not enabled on time_clock_entry';
  end if;

  select count(*) into v_n from pg_policies
   where schemaname='public' and tablename='time_clock_entry';
  if v_n <> 5 then
    raise exception 'time_clock_entry has % policies, expected 5', v_n;
  end if;

  -- CONTROL: no write policy lets a row reach 'approved' without
  -- time.approve. The self-insert and self-update policies must both pin
  -- approval_state, or a worker signs off their own hours.
  select count(*) into v_n from pg_policies
   where schemaname='public' and tablename='time_clock_entry'
     and policyname in ('time_clock_entry_self_insert','time_clock_entry_self_update')
     and coalesce(with_check,'') like '%approval_state%';
  if v_n <> 2 then
    raise exception 'only % of the 2 self-write policies constrain approval_state', v_n;
  end if;

  -- CONTROL: every policy names a permission, the self-read included. A
  -- read policy without one keeps serving rows over PostgREST after a
  -- downgrade has taken the screen away.
  select count(*) into v_n from pg_policies
   where schemaname='public' and tablename='time_clock_entry'
     and coalesce(qual,'') || coalesce(with_check,'') not like '%auth_has_permission%';
  if v_n <> 0 then
    raise exception '% policies on time_clock_entry name no permission', v_n;
  end if;

  -- The three keys exist, are plan-gated, and each is held by somebody.
  foreach v_t in array array['time.clock','time.view_all','time.approve']
  loop
    if not exists (select 1 from public.permissions where permission_id = v_t and is_plan_gated) then
      raise exception '% is missing or not plan-gated', v_t;
    end if;

    select count(*) into v_n from public.role_permissions
     where permission_id = v_t and granted;
    if v_n < 1 then
      raise exception '% is granted to no role, which is a silent deny for everyone', v_t;
    end if;

    -- Both legs must agree or the key is a silent no.
    if not exists (
      select 1 from public.plan_permissions
       where permission_id = v_t and plan_id = 'pro' and granted
    ) then
      raise exception '% is not granted on the pro plan', v_t;
    end if;

    if exists (
      select 1 from public.plan_permissions
       where permission_id = v_t and plan_id = 'starter' and granted
    ) then
      raise exception '% is granted on starter, which this migration denies on purpose', v_t;
    end if;
  end loop;

  -- CONTROL: the approval key is NARROWER than the clocking key. If these
  -- came out equal, every worker could approve their own corrections and the
  -- supervisor leg would be decoration. This is the assertion that would
  -- have caught a copy-pasted role array.
  if (select count(*) from public.role_permissions where permission_id='time.approve' and granted)
     >= (select count(*) from public.role_permissions where permission_id='time.clock' and granted) then
    raise exception 'time.approve is held by as many roles as time.clock; the approval gate is decoration';
  end if;

  -- CONTROL: staff can clock in and cannot approve. Named explicitly
  -- because it is the case the whole design turns on.
  if not exists (select 1 from public.role_permissions where role_id='staff' and permission_id='time.clock' and granted) then
    raise exception 'staff cannot clock in, which is who this is for';
  end if;
  if exists (select 1 from public.role_permissions where role_id='staff' and permission_id='time.approve' and granted) then
    raise exception 'staff can approve hours';
  end if;

  raise notice 'time_clock_entry ready; time.clock / time.view_all / time.approve granted, starter denied';
end $$;

commit;
