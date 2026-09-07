-- The team record learns who a person actually is, and gains people who never log in.
--
-- Two gaps, one table.
--
-- 1. A team row today is a name, an email and a role. Food-safety records have
--    to name a person and their POSITION: the Costco GMP corrective-action form
--    asks for "Responsible Person (Name & Title)", 3.2.1 scores a written
--    organisation chart linking everyone responsible for food safety up to
--    management, 4.1.1 wants a HACCP team drawn from a cross-section of staff,
--    and the audit workbook's Employee Interviews sheet — a required input, the
--    file nags until it is filled — has columns for Position, Department and
--    Shift that nothing in STRATA can currently answer.
--
-- 2. The people who do the work often have no login. A packer or a cleaner is
--    never going to be invited to the app, but their name belongs on the record
--    of what they did, and at a shared terminal they need to be pickable.
--    `auth_user_id` was already nullable, but every surface treats a row without
--    one as "invited, hasn't accepted yet". `login_kind` makes the difference
--    explicit: 'account' is a person who has or will have a login, 'pin_only' is
--    floor staff who exist to be named on records and, later, to PIN in.
--    (Owner, 2026-09-07: "we'll need a separate section of the users section for
--    non login staff.")
--
-- Deliberately NOT plan-gated. These are record-keeping primitives — a starter
-- roaster should be able to write down who their packer is. The HACCP module
-- and the PIN terminal that build on top of this are enterprise_plus; naming a
-- human being is not a paid feature.
--
-- Seat cap: pin_only rows hold no auth account and must NOT count against
-- subscription_plans.max_team_members. The two places that count active members
-- (S/app/app/(app)/configuration/page.tsx, S/app/app/(app)/layout.tsx) are
-- updated in the same change.
--
-- PIN storage is deliberately NOT here. Hashing, verification, lockout and the
-- terminal session are their own migration with their own security review;
-- this one only establishes who exists.

begin;

alter table public.team
  add column if not exists job_title  text,
  add column if not exists department text,
  add column if not exists shift      text,
  add column if not exists started_on date,
  add column if not exists reports_to text,
  add column if not exists login_kind text not null default 'account';

comment on column public.team.job_title  is 'Position. Costco GMP: the CAP form''s "Responsible Person (Name & Title)" and the Employee Interviews sheet.';
comment on column public.team.department is 'Employee Interviews sheet column; also how 4.1.1 judges a cross-functional HACCP team.';
comment on column public.team.shift      is 'Employee Interviews sheet column. Free text — a tenant''s shifts are their own.';
comment on column public.team.started_on is 'Start date. Drives "trained at hire" checks (117.4(d)) rather than being decorative.';
comment on column public.team.reports_to is 'Self-FK. The reporting line 3.2.1 scores; null for the top of the chart.';
comment on column public.team.login_kind is '''account'' = has or will have an auth login. ''pin_only'' = floor staff who never log in: named on records, pickable at a terminal, and NOT counted against the plan seat cap.';

-- A self-FK for the org chart. ON DELETE SET NULL: losing a manager must not
-- delete their reports, it just detaches the line.
alter table public.team
  drop constraint if exists team_reports_to_fkey;
alter table public.team
  add constraint team_reports_to_fkey
  foreign key (reports_to) references public.team(team_member_id) on delete set null;

-- Nobody reports to themselves; there is no login on a pin_only row.
alter table public.team
  drop constraint if exists team_reports_to_not_self;
alter table public.team
  add constraint team_reports_to_not_self
  check (reports_to is null or reports_to <> team_member_id);

alter table public.team
  drop constraint if exists team_login_kind_check;
alter table public.team
  add constraint team_login_kind_check
  check (login_kind in ('account', 'pin_only'));

-- The invariant that makes the seat-cap exemption safe: a pin_only row can
-- never carry an auth account. If a floor member is later given a login, the
-- row is switched to 'account' first, which is a deliberate act.
alter table public.team
  drop constraint if exists team_pin_only_has_no_login;
alter table public.team
  add constraint team_pin_only_has_no_login
  check (login_kind <> 'pin_only' or auth_user_id is null);

create index if not exists idx_team_company_login_kind
  on public.team (company_id, login_kind)
  where coalesce(is_active, true);

create index if not exists idx_team_reports_to
  on public.team (reports_to) where reports_to is not null;

-- ── Permission ──────────────────────────────────────────────────────────────
-- Adding a person who cannot log in is not an invitation, so team.invite is the
-- wrong key: it exists to gate handing out access, and its deny copy says so.
insert into public.permissions
  (permission_id, category, label, description, default_deny_message, is_plan_gated, sort_order)
values (
  'team.floor_staff',
  'Team',
  'Manage floor staff',
  'Add and edit people who work here but never log in — packers, cleaners, seasonal help. They hold no account and no seat; their names go on production and sanitation records.',
  'You don''t have permission to do that. Contact your administrator if you need access.',
  false,
  0
)
on conflict (permission_id) do nothing;

-- Every plan. Writing down who works for you is not an upsell.
insert into public.plan_permissions (plan_id, permission_id, granted, updated_reason)
values
  ('starter',         'team.floor_staff', true, 'Naming the people who do the work — all plans'),
  ('pro',             'team.floor_staff', true, 'Naming the people who do the work — all plans'),
  ('enterprise',      'team.floor_staff', true, 'Naming the people who do the work — all plans'),
  ('enterprise_plus', 'team.floor_staff', true, 'Naming the people who do the work — all plans')
on conflict (plan_id, permission_id) do update
  set granted = excluded.granted, updated_reason = excluded.updated_reason;

-- Same shape as team.invite, plus manager: the person who knows who was on
-- shift is the one who should be able to add them.
insert into public.role_permissions (role_id, permission_id, granted)
values
  ('company_admin',  'team.floor_staff', true),
  ('facility_admin', 'team.floor_staff', true),
  ('manager',        'team.floor_staff', true)
on conflict (role_id, permission_id) do update set granted = excluded.granted;

commit;
