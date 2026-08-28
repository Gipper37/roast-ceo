-- Discounts become a first-class thing, instead of a product pretending to be one.
--
-- Today a discount is a NEGATIVE LINE ITEM: a fake "Sales Discount" product sits
-- in the catalogue and gets sold at a negative price. That came across with the
-- QuickBooks migration and it is not how this should work. It puts non-products
-- in the product list, it cannot express "10% off coffee for this customer"
-- without someone doing the arithmetic by hand, and the moment the quantity
-- changes the percentage is wrong because it was frozen into a dollar amount at
-- entry.
--
-- A discount is an ATTRIBUTE OF THE THING IT DISCOUNTS. A line knows its own
-- list price, its own discount, and therefore its own net.
--
-- ── WHY NET STAYS IN total_price ─────────────────────────────────────────────
-- order_total is a trigger sum of order_details.total_price
-- (update_order_aggregates). TWENTY-ONE places read total_price — 3 views, 6 DB
-- functions, 12 frontend files. If total_price kept holding the GROSS and the
-- discount lived somewhere else, every one of those would overstate revenue
-- until it was individually taught otherwise, and the ones that were missed
-- would disagree with the ones that were not. That failure already happened once
-- here: customer_profitability and customer_revenue disagreed about $1.4M.
--
-- So total_price keeps meaning exactly what it means now — what the customer is
-- actually charged for this line — and gains a gross figure beside it. Nothing
-- downstream changes. Tax computed on order_total is then automatically
-- discount-then-tax, which is the correct order.
--
-- ── WHY THE LINE SNAPSHOTS ITS DISCOUNT ──────────────────────────────────────
-- The resolved discount is STAMPED on the line at write time, exactly as the
-- price, the cost and the product name already are. A customer's standing deal
-- changing next March must not restate what was invoiced last June. This is the
-- same principle that unit_price_at_sale exists to protect, applied to the
-- second half of the same number.
--
-- ── WHAT THIS MIGRATION DOES NOT DO ──────────────────────────────────────────
-- Nothing is computed automatically yet: no rule is created, no line gains a
-- discount, and no existing total moves. The resolver is here so the UI can ask
-- it questions; wiring it into order entry is the next migration.
--
-- MCR's 351 legacy "Sales Discount" lines (-$55,041.28) are NOT migrated and
-- must not be. They are QuickBooks history, protected by is_legacy_import, and
-- they stay exactly as they are. The new model COEXISTS with them; the old
-- product simply stops being the way new discounts are recorded.

begin;

-- ── The standing deal ────────────────────────────────────────────────────────
create table if not exists public.customer_discount (
  customer_discount_id text primary key,
  company_id      text not null references public.companies(company_id) on delete cascade,
  customer_id     text not null references public.customers(customer_id) on delete cascade,

  -- What it covers. 'all' is the whole-store discount; 'product_type' is the
  -- category case the owner asked for ("coffee at one rate, distribution at
  -- another"); 'product' is per-item. Deliberately keyed on product_groups —
  -- the PRODUCT — not on a variant, because a deal is struck on the coffee, not
  -- on the 8oz-wholesale SKU of it.
  scope           text not null check (scope in ('all','product_type','product')),
  scope_ref       text,

  kind            text not null check (kind in ('percent','amount')),
  value           numeric(12,4) not null check (value >= 0),

  -- The expiration the owner asked for. NULL effective_to means it runs until
  -- somebody stops it.
  effective_from  date not null default current_date,
  effective_to    date,
  is_active       boolean not null default true,
  note            text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by text,
  updated_by text,

  constraint customer_discount_scope_ref_present check (
    (scope = 'all' and scope_ref is null) or (scope <> 'all' and scope_ref is not null)
  ),
  -- A percentage over 100 is not a discount, it is a refund with extra steps.
  constraint customer_discount_percent_sane check (kind <> 'percent' or value <= 100),
  constraint customer_discount_dates check (effective_to is null or effective_to >= effective_from)
);

-- One live rule per customer per scope target. Without this an operator can
-- create "10% off coffee" twice and the resolver has to guess.
create unique index if not exists customer_discount_unique_scope
  on public.customer_discount (customer_id, scope, coalesce(scope_ref, '__all__'))
  where is_active;

create index if not exists customer_discount_lookup
  on public.customer_discount (customer_id, is_active, effective_from, effective_to);

comment on table public.customer_discount is
  'A customer''s standing discount. Scope is the whole store, a product type, or '
  'one product; value is a percentage or a dollar amount; effective_to is the '
  'optional expiry. Resolved and SNAPSHOTTED onto the order line at write time, '
  'so changing a deal never restates an invoice already issued.';

-- ── What the line remembers ──────────────────────────────────────────────────
alter table public.order_details
  add column if not exists list_price_total  numeric,
  add column if not exists discount_kind     text,
  add column if not exists discount_value    numeric(12,4),
  add column if not exists discount_amount   numeric,
  add column if not exists discount_source   text,
  add column if not exists discount_rule_id  text;

alter table public.order_details
  drop constraint if exists order_details_discount_kind_check;
alter table public.order_details
  add constraint order_details_discount_kind_check
  check (discount_kind is null or discount_kind in ('percent','amount'));

alter table public.order_details
  drop constraint if exists order_details_discount_source_check;
alter table public.order_details
  add constraint order_details_discount_source_check
  check (discount_source is null or discount_source in ('customer_rule','manual','order_allocated'));

comment on column public.order_details.list_price_total is
  'Gross for this line before any discount. total_price remains the NET — what '
  'the customer is charged — so every existing consumer of total_price keeps '
  'working unchanged.';
comment on column public.order_details.discount_amount is
  'Money taken off this line, always POSITIVE. list_price_total - discount_amount '
  '= total_price, on every line, always.';
comment on column public.order_details.discount_source is
  'Why this discount applied: customer_rule (their standing deal), manual (typed '
  'on this line), order_allocated (this line''s share of an order-level '
  'discount). Carried so the invoice and the operator can both explain a number.';

-- Backfill: every existing line is undiscounted, so its gross IS its net. Stated
-- explicitly rather than left null so `list_price_total - discount_amount =
-- total_price` holds for history too and no report has to special-case it.
-- Triggers off — this annotates rows, it is not an operator edit and must not
-- re-run pricing.
alter table public.order_details disable trigger user;
update public.order_details
   set list_price_total = total_price,
       discount_amount  = 0
 where list_price_total is null;
alter table public.order_details enable trigger user;

-- ── What the order remembers ─────────────────────────────────────────────────
-- discount_total already existed and was populated on 0 of 15,027 orders. It now
-- gets a meaning: the sum of what was ALLOCATED to the lines, never a figure
-- that lives only here. An order-level discount that did not reach the lines
-- would be invisible to all 21 readers of total_price.
alter table public.orders
  add column if not exists discount_kind  text,
  add column if not exists discount_value numeric(12,4);

alter table public.orders drop constraint if exists orders_discount_kind_check;
alter table public.orders
  add constraint orders_discount_kind_check
  check (discount_kind is null or discount_kind in ('percent','amount'));

comment on column public.orders.discount_total is
  'Sum of the order-level discount actually allocated across the lines. Derived, '
  'never authoritative: the money always lives on the lines, because order_total '
  'and every revenue view are built from them.';

-- ── Resolving a customer''s deal ─────────────────────────────────────────────
-- Most specific wins, one rule per line: product beats product type beats
-- store-wide. Not additive — stacking a store 5% with a coffee 10% gives a
-- number no operator can predict or explain to a customer, and "most specific
-- wins" is the rule every system that survived contact with users converged on.
--
-- Returns NULL when nothing applies. NULL means no discount; it does not mean
-- zero percent, and callers must not invent one.
create or replace function public.resolve_customer_discount(
  p_customer_id text,
  p_product_id  text,
  p_on_date     date default current_date
)
returns table (
  customer_discount_id text,
  kind  text,
  value numeric,
  scope text
)
language sql
stable
security invoker
as $function$
  select d.customer_discount_id, d.kind, d.value, d.scope
  from public.customer_discount d
  join public.products p on p.product_id = p_product_id
  left join public.product_groups pg on pg.group_id = p.group_id
  where d.customer_id = p_customer_id
    and d.is_active
    and d.effective_from <= p_on_date
    and (d.effective_to is null or d.effective_to >= p_on_date)
    and (
         d.scope = 'all'
      or (d.scope = 'product_type' and d.scope_ref = p.product_type)
      or (d.scope = 'product'      and d.scope_ref = pg.group_id::text)
    )
  order by case d.scope when 'product' then 3 when 'product_type' then 2 else 1 end desc
  limit 1;
$function$;

comment on function public.resolve_customer_discount is
  'The one discount that applies to this customer for this product on this date. '
  'Most specific wins: product > product type > store-wide. Never additive. '
  'NULL means none, not zero.';

alter table public.customer_discount enable row level security;

drop policy if exists customer_discount_tenant on public.customer_discount;
create policy customer_discount_tenant on public.customer_discount
  using (company_id in (select auth_company_ids()))
  with check (company_id in (select auth_company_ids()));

grant select, insert, update, delete on public.customer_discount to authenticated;

commit;
