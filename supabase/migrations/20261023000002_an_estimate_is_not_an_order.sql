-- An estimate is not an order.
--
-- Owner, 2026-10-23, reasoning to the design himself: *"should it be it's own
-- table and then accounting could go into estimates and convert it to an
-- invoice and then it would make an invoice/order at that point. and then we
-- wouldn't have to worry about all the places to omit estimate designated
-- invoice from in the code and logic."*
--
-- That last clause is the whole argument, and it is right.
--
-- ── WHY NOT AN ORDER STATUS ───────────────────────────────────────────────
--
-- The obvious cheap version is a new `order_status = 'Estimate'`. It does not
-- work. `roast_detail_by_blend` -- the demand planner -- filters
-- `order_status <> 'Canceled'` in SIX places, and ten views carry the same
-- shape: customer_profitability, customer_revenue, order_profitability,
-- revenue_recognized, pack_totals_by_prep, totals, tax_liability_by_rate,
-- monthly_consumable_usage_by_item and the rest. Every one would have to learn
-- a second exclusion, each against SQL that is producing money numbers today,
-- and the one that got missed would quietly put coffee nobody ordered into the
-- roast plan or revenue nobody earned into a report.
--
-- (The same reasoning says `Draft` cannot be reused either: a Draft order is
-- already counted by all of them. MCR has 0 drafts of 4,232 orders, which is
-- the only reason nobody has been bitten.)
--
-- A table nothing has ever heard of cannot be forgotten by anything. An
-- estimate becomes real by CONVERTING -- which creates an ordinary order, down
-- the normal path, and from that moment every view sees it because it is an
-- order like any other. That is what QuickBooks does with an Estimate and what
-- Shopify does with a draft order, and taking their model is the house rule.
--
-- ── NUMBERING ─────────────────────────────────────────────────────────────
--
-- `lot_code_sequence` is already the shared per-company counter: bin cards
-- mint out of it under their own key space ('B'||YYMMDD), and its comment says
-- so. Estimates take the key 'ESTIMATE'. The name is about where it started
-- rather than what it is, but a second counter table with the same columns and
-- the same race would be worse than a name that reads oddly.

begin;

create table if not exists public.estimate (
  estimate_id      text        primary key,
  company_id       text        not null references public.companies(company_id) on delete cascade,
  facility_id      text,
  customer_id      text        references public.customers(customer_id),
  estimate_number  integer     not null,
  -- Not an enum: a new state is a code change and an enum makes it a migration
  -- as well. 'expired' is set by reading expires_on, never stored ahead of time.
  status           text        not null default 'open'
                     check (status in ('open', 'accepted', 'declined', 'expired')),
  estimate_date    date        not null default current_date,
  expires_on       date,
  notes            text,
  -- Set when this estimate became an order. Its presence is what makes the
  -- estimate read-only: a quote that was accepted must not drift afterwards,
  -- or the document the customer agreed to is not the one on file.
  converted_order_id text      references public.orders(order_id) on delete set null,
  converted_at     timestamptz,
  created_at       timestamptz not null default now(),
  created_by       text,
  updated_at       timestamptz not null default now(),
  updated_by       text,
  unique (company_id, estimate_number)
);

comment on table public.estimate is
  'A quote. Deliberately NOT an order: no view, planner or report knows this table exists, so an estimate cannot leak into demand, revenue or stock. It becomes real by converting into an ordinary order.';

create table if not exists public.estimate_line (
  estimate_line_id text        primary key,
  estimate_id      text        not null references public.estimate(estimate_id) on delete cascade,
  -- Carried so RLS needs no join. The estimate owns it and cascade deletes it.
  company_id       text        not null references public.companies(company_id) on delete cascade,
  product_id       text        references public.products(product_id),
  coffee_prep      text,
  quantity         numeric     not null check (quantity > 0),
  -- 🔴 A SNAPSHOT, not a lookup. The whole point of a quote is that it states a
  -- price and that price survives a price list changing underneath it. The
  -- order created on conversion gets these numbers as overrides, so what the
  -- customer agreed to is what they are charged.
  unit_price       numeric(12,2),
  line_total       numeric(12,2),
  sort_order       integer     not null default 0
);

comment on column public.estimate_line.unit_price is
  'The price quoted, snapshotted. Not re-read from the catalogue at conversion: a quote that silently repriced would not be a quote.';

create index if not exists estimate_company_idx      on public.estimate (company_id, estimate_date desc);
create index if not exists estimate_customer_idx     on public.estimate (customer_id);
create index if not exists estimate_line_estimate_idx on public.estimate_line (estimate_id);

alter table public.estimate      enable row level security;
alter table public.estimate_line enable row level security;

drop policy if exists estimate_read  on public.estimate;
create policy estimate_read on public.estimate
  for select using (company_id in (select auth_company_ids()));

drop policy if exists estimate_write on public.estimate;
create policy estimate_write on public.estimate
  for all
  using      (company_id in (select auth_company_ids()) and auth_has_permission('estimate.edit', company_id))
  with check (company_id in (select auth_company_ids()) and auth_has_permission('estimate.edit', company_id));

drop policy if exists estimate_line_read on public.estimate_line;
create policy estimate_line_read on public.estimate_line
  for select using (company_id in (select auth_company_ids()));

drop policy if exists estimate_line_write on public.estimate_line;
create policy estimate_line_write on public.estimate_line
  for all
  using      (company_id in (select auth_company_ids()) and auth_has_permission('estimate.edit', company_id))
  with check (company_id in (select auth_company_ids()) and auth_has_permission('estimate.edit', company_id));

grant select, insert, update, delete on public.estimate      to authenticated;
grant select, insert, update, delete on public.estimate_line to authenticated;

-- ── The number ────────────────────────────────────────────────────────────

create or replace function public.next_estimate_number(p_company_id text)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_seq int;
begin
  if p_company_id is null or not exists (
    select 1 from unnest(array(select auth_company_ids())) c(id) where c.id = p_company_id
  ) then
    raise exception 'Not your company.' using errcode = 'insufficient_privilege';
  end if;

  -- One atomic upsert, so two people quoting at the same instant cannot mint
  -- the same number. Same shape as next_bin_card_code, same table, its own key.
  insert into public.lot_code_sequence (company_id, seq_key, last_seq)
  values (p_company_id, 'ESTIMATE', 1)
  on conflict (company_id, seq_key) do update
    set last_seq = public.lot_code_sequence.last_seq + 1
  returning last_seq into v_seq;

  return v_seq;
end;
$$;

revoke all on function public.next_estimate_number(text) from public;
grant execute on function public.next_estimate_number(text) to authenticated;

-- ── Permissions ───────────────────────────────────────────────────────────
--
-- Two keys, not three. Converting is gated on estimate.edit AND order.create
-- in the action, which is the honest statement: turning a quote into an order
-- is making an order, and anyone who may do that already holds order.create.
-- A third key would be a third thing to forget.

insert into public.permissions
  (permission_id, category, label, description, is_plan_gated, sort_order)
values
  ('estimate.view', 'Sales', 'See estimates',
   'See quotes that have been sent to customers, and what became of them.', true, 41),
  ('estimate.edit', 'Sales', 'Write and convert estimates',
   'Create a quote, change one that has not been accepted, and convert an accepted one into an order. Converting also requires permission to create orders.', true, 42)
on conflict (permission_id) do update set
  category      = excluded.category,
  label         = excluded.label,
  description   = excluded.description,
  is_plan_gated = excluded.is_plan_gated,
  sort_order    = excluded.sort_order,
  updated_at    = now();

-- Everyone says yes or no out loud: a missing row reads as denied, but a
-- reviewer cannot tell "decided no" from "forgotten" unless it is written.
insert into public.role_permissions (role_id, permission_id, granted)
values
  ('company_admin',     'estimate.view', true),
  ('facility_admin',    'estimate.view', true),
  ('roastery_manager',  'estimate.view', true),
  ('manager',           'estimate.view', true),
  ('accounting_admin',  'estimate.view', true),
  ('accounting_view',   'estimate.view', true),
  ('sales_person',      'estimate.view', true),
  ('roastmaster',       'estimate.view', false),
  ('assistant_roaster', 'estimate.view', false),
  ('equipment_tech',    'estimate.view', false),
  ('staff',             'estimate.view', false),

  ('company_admin',     'estimate.edit', true),
  ('facility_admin',    'estimate.edit', true),
  ('manager',           'estimate.edit', true),
  ('accounting_admin',  'estimate.edit', true),
  ('sales_person',      'estimate.edit', true),
  -- Reads the book but does not write it, same as everywhere else.
  ('accounting_view',   'estimate.edit', false),
  ('roastery_manager',  'estimate.edit', false),
  ('roastmaster',       'estimate.edit', false),
  ('assistant_roaster', 'estimate.edit', false),
  ('equipment_tech',    'estimate.edit', false),
  ('staff',             'estimate.edit', false)
on conflict (role_id, permission_id) do update set
  granted = excluded.granted;

-- Plan-gated and granted on every plan. A quote moves no money -- it is a
-- sales document, not a payments feature -- so there is nothing here to put
-- behind the paid tier today. It is gated at all so the column stays
-- meaningful if that ever changes.
insert into public.plan_permissions (plan_id, permission_id, granted, updated_reason)
values
  ('starter',         'estimate.view', true, 'a quote moves no money'),
  ('pro',             'estimate.view', true, 'a quote moves no money'),
  ('enterprise',      'estimate.view', true, 'a quote moves no money'),
  ('enterprise_plus', 'estimate.view', true, 'a quote moves no money'),
  ('starter',         'estimate.edit', true, 'a quote moves no money'),
  ('pro',             'estimate.edit', true, 'a quote moves no money'),
  ('enterprise',      'estimate.edit', true, 'a quote moves no money'),
  ('enterprise_plus', 'estimate.edit', true, 'a quote moves no money')
on conflict (plan_id, permission_id) do update set
  granted        = excluded.granted,
  updated_reason = excluded.updated_reason,
  updated_at     = now();

-- 🔴 Asserts only what this file wrote.
do $$
begin
  if to_regclass('public.estimate') is null or to_regclass('public.estimate_line') is null then
    raise exception 'the estimate tables were not created';
  end if;
  if (select count(*) from public.role_permissions
       where permission_id in ('estimate.view', 'estimate.edit')) <> 22 then
    raise exception 'the estimate keys are missing role rows: every role must say yes or no out loud';
  end if;
  if (select count(*) from public.plan_permissions
       where permission_id in ('estimate.view', 'estimate.edit') and granted) <> 8 then
    raise exception 'the estimate keys must be granted on all four plans';
  end if;
  if not exists (select 1 from pg_policies where tablename = 'estimate' and policyname = 'estimate_write') then
    raise exception 'estimate has no write policy, so estimate.edit is not a fence';
  end if;
  if not exists (select 1 from pg_policies where tablename = 'estimate_line' and policyname = 'estimate_line_write') then
    raise exception 'estimate_line has no write policy';
  end if;
end $$;

commit;
