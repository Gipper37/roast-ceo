-- Bagged stock gets a count anchor, and counting it is not a food-safety feature.
--
-- Owner, 2026-10-24, on the Plan Inputs redesign: there are THREE ways to count
-- roasted coffee and the product only had two.
--
--     bins, by recipe    roast_stock_log  stock_type='blend'    exists
--     bins, by coffee    roast_stock_log  stock_type='origin'   exists
--     BAGS               nothing                                 this migration
--
-- ── WHY BAGGED STOCK DRIFTS AND NEVER COMES BACK ──────────────────────────
--
-- Green coffee has an anchor: a count, plus whatever happened after it, and
-- reality is allowed to overrule the ledger. Bagged stock has none.
-- `pack_run_remaining` is bags minus unreleased allocations, computed from the
-- first pack run ever recorded, forever. So a bagging session nobody recorded
-- under-counts the shelf permanently, a pack nobody recorded over-counts it
-- permanently, and neither ever washes out. That is the classic weakness of
-- BACKFLUSHING, and the textbook remedy is a count that posts a variance.
--
-- This migration adds the anchor and the permission. NOTHING READS IT YET:
-- `pack_run_remaining` still computes the old way, deliberately, because
-- changing live stock math is its own migration with its own proof. Additive
-- only, so it can go out on its own.
--
-- ── 🔴 NOT GATED ON FOOD SAFETY, WHICH IS A CHANGE TO THE WRITTEN DESIGN ──
--
-- The 2026-09-15 brief said the plan gate "must MATCH pack.run". The owner
-- overruled that today: *"this can't be only food safety dependant. it needs
-- to be surface for the roastmaster when food safety isn't on."*
--
-- He is right, and the shape of the bug proves it. `pack.run` carries
-- feature_key='haccp' and is granted on enterprise_plus ALONE, so a roastery
-- without the module records no pack runs at all -- which means every packed
-- line already reports a shortfall against bagged stock it never recorded.
-- Those are exactly the roasteries whose bagged number is furthest from the
-- shelf, and the written design would have denied them the only tool that
-- fixes it.
--
-- So `pack.count` carries NO feature_key and follows `inventory.count`'s plan
-- gate (pro and up), not pack.run's. Counting what is on your own shelf is the
-- same class of act as counting green, and neither is traceability. Same
-- precedent as freeing `terminal.manage` and `team.floor_staff` from haccp
-- earlier today: knowing who is at a machine, and knowing how much coffee you
-- have, are not food-safety questions.
--
-- 🔴 A COUNT SETTLES QUANTITY. IT DOES NOT SETTLE TRACEABILITY. Owner, on an
-- earlier draft: *"just because there's a way to true up the data doesn't mean
-- they didn't do something wrong."* A bag that went out against a shortfall
-- left with no lot behind it and no later count invents one. The variance row
-- records the quantity truth and says nothing about the trace, on purpose.

begin;

-- ── The anchor ────────────────────────────────────────────────────────────

create table if not exists public.pack_stock_count (
  pack_stock_count_id uuid primary key default gen_random_uuid(),
  company_id          text not null references public.companies(company_id) on delete cascade,
  facility_id         text not null references public.facilities(facility_id) on delete cascade,

  -- 🔴 NULLABLE, and that is the whole point of an honest count. Bags on the
  -- shelf with no pack run behind them are a real thing: somebody bagged and
  -- did not record it. They are counted as an UNATTRIBUTED surplus rather than
  -- discarded, so the recall report can say "these have no lot behind them"
  -- instead of implying they do. Nameable later; never silently attributed.
  pack_run_id         text references public.pack_run(pack_run_id) on delete set null,

  -- 🔴 A TIMESTAMP, NOT A DATE, and the green precedent gets this wrong.
  -- `calculate_current_stock_consumables` compares `date_received > a DATE`, so
  -- anything received the same day but AFTER the count is treated as already
  -- counted and silently dropped. On green that is rare because receiving is
  -- lumpy. Bagging runs continuously, so a Monday-morning count followed by
  -- Monday-afternoon bagging would lose those bags EVERY WEEK.
  counted_at          timestamptz not null default now(),

  counted_bags        numeric not null check (counted_bags >= 0),
  -- What the system believed at the moment of the count, frozen. Without it a
  -- variance cannot be re-read later: the live figure has moved on.
  system_bags         numeric not null,
  variance            numeric generated always as (counted_bags - system_bags) stored,

  -- Required when the count disagrees, enforced below. A variance with no
  -- reason is a number nobody can act on a month later.
  reason              text,
  -- Plain text, no FK, because that is what this schema already does:
  -- roast_stock_log.created_by holds a mix of ids and email addresses and
  -- references nothing. A new FK here would be the only one of its kind and
  -- would reject half the values the rest of the app writes. (`team_members`
  -- does not exist; the table is `team`.)
  counted_by          text,
  created_at          timestamptz not null default now(),

  -- Append-only is the contract; this makes "never updated" checkable.
  constraint pack_stock_count_reason_when_variance
    check (counted_bags = system_bags or (reason is not null and length(btrim(reason)) > 0))
);

comment on table public.pack_stock_count is
  'Append-only count anchor for BAGGED stock. One row per counted pack run per count. Never updated. pack_run_id null = bags found with no run behind them (unattributed surplus).';

create index if not exists pack_stock_count_facility_time_idx
  on public.pack_stock_count (facility_id, counted_at desc);
create index if not exists pack_stock_count_run_time_idx
  on public.pack_stock_count (pack_run_id, counted_at desc);

alter table public.pack_stock_count enable row level security;

drop policy if exists pack_stock_count_read on public.pack_stock_count;
create policy pack_stock_count_read on public.pack_stock_count
  for select using (company_id in (select auth_company_ids()));

-- M11 phase 2: the write policy carries the KEY, not just the tenant.
drop policy if exists pack_stock_count_write on public.pack_stock_count;
create policy pack_stock_count_write on public.pack_stock_count
  for all
  using      (company_id in (select auth_company_ids()) and auth_has_permission('pack.count', company_id))
  with check (company_id in (select auth_company_ids()) and auth_has_permission('pack.count', company_id));

grant select, insert on public.pack_stock_count to authenticated;

-- ── The permission ────────────────────────────────────────────────────────

insert into public.permissions
  (permission_id, category, label, description, is_plan_gated, sort_order)
values
  ('pack.count', 'Inventory', 'Count bagged stock',
   'Walk the shelf and record how many bags are actually there, so the bagged figure can be corrected. Counting settles the quantity; it does not recover a lot number that was never recorded.',
   true, 48)
on conflict (permission_id) do update set
  category      = excluded.category,
  label         = excluded.label,
  description   = excluded.description,
  is_plan_gated = excluded.is_plan_gated,
  sort_order    = excluded.sort_order,
  updated_at    = now();

-- 🔴 NO feature_key. Stated out loud because the written design said otherwise
-- and a reviewer must be able to tell "decided" from "forgotten".
update public.permissions set feature_key = null where permission_id = 'pack.count';

-- Roles: everyone who can RUN a bagging session, plus everyone who can count
-- green. Staff is included because the person holding the bags is often the
-- person who should be counting them.
insert into public.role_permissions (role_id, permission_id, granted)
values
  ('company_admin',     'pack.count', true),
  ('facility_admin',    'pack.count', true),
  ('roastery_manager',  'pack.count', true),
  ('manager',           'pack.count', true),
  ('roastmaster',       'pack.count', true),
  ('assistant_roaster', 'pack.count', true),
  ('staff',             'pack.count', true)
on conflict (role_id, permission_id) do update set granted = excluded.granted;

-- Plan: follows inventory.count (pro and up), NOT pack.run (enterprise_plus).
-- See the header: this is the owner's correction, not an oversight.
insert into public.plan_permissions (plan_id, permission_id, granted, updated_reason)
values
  ('starter',          'pack.count', false, 'Counting bagged stock follows inventory.count, which starter does not have'),
  ('pro',              'pack.count', true,  'Counting your own shelf is not a food-safety feature (owner, 2026-10-24)'),
  ('enterprise',       'pack.count', true,  'Counting your own shelf is not a food-safety feature (owner, 2026-10-24)'),
  ('enterprise_plus',  'pack.count', true,  'Counting your own shelf is not a food-safety feature (owner, 2026-10-24)')
on conflict (plan_id, permission_id) do update set
  granted        = excluded.granted,
  updated_reason = excluded.updated_reason,
  updated_at     = now();

-- ── Prove it, rather than assume it ───────────────────────────────────────
do $$
declare
  n_feature int;
  n_roles   int;
  n_plans   int;
  n_policy  int;
begin
  select count(*) into n_feature from public.permissions
   where permission_id = 'pack.count' and feature_key is null;
  if n_feature <> 1 then
    raise exception 'pack.count must carry NO feature_key: counting a shelf is not food safety';
  end if;

  select count(*) into n_roles from public.role_permissions
   where permission_id = 'pack.count' and granted;
  if n_roles <> 7 then
    raise exception 'pack.count should be granted to 7 roles, found %', n_roles;
  end if;

  -- The whole point of the owner's correction: a PRO roastery, with no food
  -- safety module, can still count its own bagged stock.
  select count(*) into n_plans from public.plan_permissions
   where permission_id = 'pack.count' and plan_id = 'pro' and granted;
  if n_plans <> 1 then
    raise exception 'pack.count must be granted on pro, or a roastery without food safety cannot count its own shelf';
  end if;

  select count(*) into n_policy from pg_policies
   where schemaname = 'public' and tablename = 'pack_stock_count';
  if n_policy <> 2 then
    raise exception 'pack_stock_count needs its read and write policies, found %', n_policy;
  end if;
end $$;

commit;
