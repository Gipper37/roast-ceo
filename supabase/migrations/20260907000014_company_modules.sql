-- Modules a tenant chooses to use.
--
-- Owner, 2026-09-07: the reason for a module toggle "is so the user has the
-- capability to choose what features they want to use. if an ent+ user doesn't
-- want to use haccp they aren't forced to."
--
-- That is a different thing from a plan gate, and the difference decides the
-- design. A plan gate is OUR answer to "may you have this". A module toggle is
-- THEIRS to "do you want it". So this defaults to OFF and nothing turns it on
-- but the tenant: paying for enterprise_plus buys the option, not the obligation.
--
-- It is deliberately not a haccp boolean. This is the first module of several
-- already designed (roast monitor, mass email, offline mode), so a new one is a
-- catalog row and a permission tag, never another column and another gate.
--
-- ── How it reaches every existing check ─────────────────────────────────────
-- permissions.feature_key tags a key as belonging to a module. Both places that
-- resolve permissions then AND the module in:
--   * auth_has_permission() here, which is what the security-definer RPCs use;
--   * buildPermissionSnapshot() in the app, which is what the UI uses.
-- So the gates already written for team.floor_staff and terminal.manage start
-- respecting the toggle without one call site changing.
--
-- ── The bug this also closes ────────────────────────────────────────────────
-- current_terminal() checked only team.is_terminal, never the plan. A tenant who
-- marked their packing login a terminal and then dropped to pro — or whose
-- payment failed — kept the lock screen on that machine, while the toggle to
-- turn it off had disappeared with the plan. They were locked out of their own
-- terminal with no way back. It now requires the module, so losing the plan or
-- switching the module off quietly returns the machine to an ordinary login.

begin;

-- ── What modules exist ──────────────────────────────────────────────────────
create table public.feature_catalog (
  feature_key text primary key,
  label       text not null,
  description text not null,
  -- Which plans may switch it on. An array rather than a "minimum plan",
  -- because subscription_plans has no rank column and inventing an ordering
  -- would be a second, silent source of truth about what a plan includes.
  plans       text[] not null,
  sort_order  int not null default 0,
  is_active   boolean not null default true
);

comment on table public.feature_catalog is
  'The modules a tenant can switch on. A new module is a row here plus permissions.feature_key on its keys — not new columns and not new gates.';

alter table public.feature_catalog enable row level security;
create policy feature_catalog_read on public.feature_catalog for select using (true);

-- ── What this tenant chose ──────────────────────────────────────────────────
create table public.company_feature (
  company_id  text not null references public.companies(company_id) on delete cascade,
  feature_key text not null references public.feature_catalog(feature_key) on delete cascade,
  enabled     boolean not null default false,
  updated_at  timestamptz not null default now(),
  updated_by  text,
  primary key (company_id, feature_key)
);

comment on table public.company_feature is
  'A tenant''s own choice, off unless they say otherwise. A missing row reads as off, so buying the plan turns nothing on by itself.';

alter table public.company_feature enable row level security;
create policy company_feature_read on public.company_feature
  for select using (company_id in (select auth_company_ids()));
create policy company_feature_write on public.company_feature
  for all
  using (company_id in (select auth_company_ids()) and public.auth_has_permission('config.features', company_id))
  with check (company_id in (select auth_company_ids()) and public.auth_has_permission('config.features', company_id));

alter table public.permissions
  add column if not exists feature_key text references public.feature_catalog(feature_key);

comment on column public.permissions.feature_key is
  'When set, this key also requires the tenant to have switched that module on. Null for everything that is simply part of the app.';

-- ── The one question: does this company have this module ────────────────────
create or replace function public.company_has_feature(p_company_id text, p_feature_key text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
      from public.feature_catalog f
      join public.company_feature cf
        on cf.feature_key = f.feature_key and cf.company_id = p_company_id
      left join public.company_subscription_status s on s.company_id = p_company_id
     where f.feature_key = p_feature_key
       and f.is_active
       and cf.enabled
       and s.plan_id = any (f.plans)
  );
$$;

comment on function public.company_has_feature(text, text) is
  'Plan allows it AND the tenant switched it on. Both halves, because the plan is our answer and the toggle is theirs.';

-- ── Permission resolution now respects the module ───────────────────────────
create or replace function public.auth_has_permission(p_permission_id text, p_company_id text default null)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
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
               on pp.plan_id = s.plan_id and pp.permission_id = p_permission_id and pp.granted
            where s.company_id = t.company_id
         )
       )
       -- ...and the tenant has to have chosen the module this key belongs to.
       and (p.feature_key is null or public.company_has_feature(t.company_id, p.feature_key))
  );
$$;

-- ── A terminal is only a terminal while the module is on ────────────────────
create or replace function public.current_terminal()
returns public.team
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select t.* from public.team t
   where t.auth_user_id = auth.uid()
     and coalesce(t.is_active, true)
     and t.is_terminal
     and public.company_has_feature(t.company_id, 'haccp');
$$;

-- ── Seed ────────────────────────────────────────────────────────────────────
insert into public.feature_catalog (feature_key, label, description, plans, sort_order)
values (
  'haccp',
  'Food safety records',
  'Shared terminals with PIN sign-in, floor staff who never log in, and a named person on every production record. Turn this on if you are audited — Costco, SQF, BRCGS — or if you simply want to know who did what.',
  array['enterprise_plus'],
  10
)
on conflict (feature_key) do update
  set label = excluded.label, description = excluded.description, plans = excluded.plans;

update public.permissions
   set feature_key = 'haccp'
 where permission_id in ('team.floor_staff', 'terminal.manage');

-- Managing the switches is not itself a module, and not plan-gated: a tenant on
-- any plan should be able to see what they could turn on and what it needs.
insert into public.permissions
  (permission_id, category, label, description, default_deny_message, is_plan_gated, sort_order)
values (
  'config.features',
  'Configuration',
  'Turn modules on and off',
  'Choose which optional parts of STRATA this company uses.',
  'You don''t have permission to do that. Contact your administrator if you need access.',
  false,
  6
)
on conflict (permission_id) do nothing;

insert into public.plan_permissions (plan_id, permission_id, granted, updated_reason)
values
  ('starter',         'config.features', true, 'Everyone can see what modules exist and what they need'),
  ('pro',             'config.features', true, 'Everyone can see what modules exist and what they need'),
  ('enterprise',      'config.features', true, 'Everyone can see what modules exist and what they need'),
  ('enterprise_plus', 'config.features', true, 'Everyone can see what modules exist and what they need')
on conflict (plan_id, permission_id) do update
  set granted = excluded.granted, updated_reason = excluded.updated_reason;

insert into public.role_permissions (role_id, permission_id, granted)
values ('company_admin', 'config.features', true)
on conflict (role_id, permission_id) do update set granted = excluded.granted;

revoke all on function public.company_has_feature(text, text) from public;
grant execute on function public.company_has_feature(text, text) to authenticated;

commit;
