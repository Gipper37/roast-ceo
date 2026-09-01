-- The C market grows a flow: price alerts.
--
-- The coffee inventory's C-market pill becomes a page (frontend) where a
-- roaster watches ICE Coffee C against their own green purchases and sets
-- trigger emails — "tell me if the C moves above / below X". This migration
-- is the storage and the permission:
--
-- 1. cmarket_alerts — one row per trigger. `last_state` is the re-arm
--    mechanism: the cron computes above/below from the live quote, fires the
--    email only when the state CHANGES onto the alert's trigger side, and
--    re-arms automatically when the price crosses back — so a threshold
--    sitting under the market all week emails once, not daily.
--
-- 2. market.alerts_manage — owner's spec: editing is Pro-and-up (plan) and
--    manager / accounting_admin and up (role). Viewing the page needs no new
--    key; the market itself is public data.

begin;

create table if not exists public.cmarket_alerts (
  alert_id           uuid primary key default gen_random_uuid(),
  company_id         text not null,
  direction          text not null check (direction in ('above', 'below')),
  threshold_cents    numeric not null check (threshold_cents > 0),
  email              text not null,
  is_active          boolean not null default true,
  -- 'above' | 'below' | null — where the price was at last check; the
  -- crossing detector. Null until the first cron pass.
  last_state         text check (last_state in ('above', 'below')),
  last_checked_price numeric,
  last_triggered_at  timestamptz,
  created_by         text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create index if not exists idx_cmarket_alerts_active on public.cmarket_alerts (is_active) where is_active;

alter table public.cmarket_alerts enable row level security;
do $$ begin
  create policy tenant_company_access on public.cmarket_alerts
    for all
    using (company_id in (select public.auth_company_ids()))
    with check (company_id in (select public.auth_company_ids()));
exception when duplicate_object then null; end $$;

-- ── The permission ───────────────────────────────────────────────────────────
insert into public.permissions (permission_id, category, label, description, default_deny_message, is_plan_gated, sort_order)
values (
  'market.alerts_manage',
  'Inventory',
  'Manage C-market price alerts',
  'Create, change and remove the C-market trigger emails on the coffee inventory''s market page.',
  'You don''t have permission to manage market alerts. Contact your administrator if you need access.',
  true,
  95
)
on conflict (permission_id) do nothing;

insert into public.plan_permissions (plan_id, permission_id, granted, updated_reason)
select sp.plan_id, 'market.alerts_manage',
       sp.plan_id in ('pro', 'enterprise', 'enterprise_plus'),
       'C-market alerts launch — Pro and up per owner spec'
from public.subscription_plans sp
on conflict (plan_id, permission_id) do update
  set granted = excluded.granted, updated_reason = excluded.updated_reason;

insert into public.role_permissions (role_id, permission_id, granted)
values ('manager',          'market.alerts_manage', true),
       ('accounting_admin', 'market.alerts_manage', true),
       ('facility_admin',   'market.alerts_manage', true),
       ('company_admin',    'market.alerts_manage', true)
on conflict (role_id, permission_id) do update set granted = excluded.granted;

commit;

notify pgrst, 'reload schema';
