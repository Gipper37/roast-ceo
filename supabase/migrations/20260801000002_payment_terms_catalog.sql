-- Payment terms become DATA: a shared set of common terms, plus whatever a
-- roaster needs to add for themselves.
--
-- WHAT IT WAS. Five strings — 'card','net_15','net_30','net_60','cod' — nailed
-- down by two CHECK constraints, with the day-count written out FOUR more times
-- in the app (lib/billing/terms.ts, lib/shop/invoiceDispatch.ts, ALLOWED_TERMS
-- in the shop actions) and once more here in finalize_invoice. Adding "Net 45" —
-- ordinary in wholesale — meant editing two constraints and five copies of the
-- same lookup, and missing one gave you an invoice showing a term it could not
-- compute a due date from. A QuickBooks import carrying "Net 45" or "Net 10" had
-- nowhere to put it, so the term was dropped.
--
-- 🔴 KIND IS NOT COSMETIC. 'card' and 'cod' were never really terms — they are
-- payment ROUTES. The storefront branches on payment_terms='card' to send a
-- customer to card checkout instead of placing an invoiced order. So behaviour
-- hangs off `kind` (net | card | cod | receipt), and label/net_days are purely
-- presentational. Without that split, a roaster inventing a term called "Card on
-- Delivery" would silently change how their storefront checks out.
--
-- ZERO BACKFILL. The five existing codes are seeded as GLOBAL rows keeping their
-- exact ids, so every customers.payment_terms/orders.payment_terms value already
-- stored stays valid and the CHECKs become foreign keys with nothing to migrate.
-- Verified against prod first: customers hold only card/cod/net_30/net_15 and
-- every one of 14,691 orders is NULL.
--
-- NOT DONE HERE, on purpose:
--   · End-of-month / "1st of the month" terms. Those are not a fixed day offset
--     and need a different due-date rule than order_date + N; inventing one
--     silently would put wrong dates on real invoices.
--   · Letting a tenant hide a GLOBAL term they never use. RLS deliberately makes
--     globals read-only, so that needs a per-company override row, which is only
--     worth building if anyone asks.

begin;

-- ── The catalog ──────────────────────────────────────────────────────────────
create table if not exists public.payment_terms (
  terms_id    text primary key,
  -- NULL = global, available to every company. Non-null = that company's own.
  company_id  text references public.companies(company_id) on delete cascade,
  label       text not null,
  -- Behaviour. 'net' = due order_date + net_days. 'card' = pay at checkout.
  -- 'cod' = due on delivery. 'receipt' = due immediately.
  kind        text not null check (kind in ('net', 'card', 'cod', 'receipt')),
  net_days    integer,
  sort_order  integer not null default 100,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint payment_terms_label_not_blank check (btrim(label) <> ''),
  -- net_days belongs to 'net' and nowhere else: a "COD, 30 days" row is a
  -- contradiction that would render one thing and compute another.
  constraint payment_terms_net_days_chk check (
    (kind = 'net'  and net_days is not null and net_days between 0 and 3650)
    or (kind <> 'net' and net_days is null)
  )
);

-- One "Net 45" per company (and one per global set). Case-insensitive, because
-- "net 45" and "Net 45" in the same dropdown is a bug report waiting to happen.
create unique index if not exists payment_terms_scope_label_uidx
  on public.payment_terms (coalesce(company_id, ''), lower(btrim(label)));

-- Ordering the pickers use.
create index if not exists payment_terms_company_idx
  on public.payment_terms (company_id, sort_order, label);

comment on table public.payment_terms is
  'Payment terms available for customers + orders. company_id NULL = global (read-only to tenants); non-null = that company''s own. `kind` drives behaviour (net/card/cod/receipt); label and net_days are presentation.';

-- ── The common set, shared by everyone ───────────────────────────────────────
-- The first five keep the ids the old CHECK allowed, so nothing needs migrating.
insert into public.payment_terms (terms_id, company_id, label, kind, net_days, sort_order) values
  ('receipt', null, 'Due on receipt', 'receipt', null,  10),
  ('card',    null, 'Card on file',   'card',    null,  20),
  ('prepaid', null, 'Prepaid',        'receipt', null,  30),
  ('cod',     null, 'COD',            'cod',     null,  40),
  ('net_10',  null, 'Net 10',         'net',       10,  50),
  ('net_15',  null, 'Net 15',         'net',       15,  60),
  ('net_20',  null, 'Net 20',         'net',       20,  70),
  ('net_30',  null, 'Net 30',         'net',       30,  80),
  ('net_45',  null, 'Net 45',         'net',       45,  90),
  ('net_60',  null, 'Net 60',         'net',       60, 100),
  ('net_90',  null, 'Net 90',         'net',       90, 110)
on conflict (terms_id) do nothing;

-- ── CHECK → foreign key ──────────────────────────────────────────────────────
alter table public.customers drop constraint if exists customers_payment_terms_chk;
alter table public.orders    drop constraint if exists orders_payment_terms_check;

alter table public.customers
  add constraint customers_payment_terms_fkey
  foreign key (payment_terms) references public.payment_terms(terms_id)
  on update cascade on delete restrict;

alter table public.orders
  add constraint orders_payment_terms_fkey
  foreign key (payment_terms) references public.payment_terms(terms_id)
  on update cascade on delete restrict;

-- A foreign key proves the term EXISTS. It cannot prove the term is available to
-- THIS company — nothing stops a row pointing at another tenant's custom term,
-- which would put their label on your invoice. That is what the CHECK used to
-- guarantee implicitly by allowing only five shared values.
create or replace function public.assert_payment_terms_available()
returns trigger
language plpgsql as $$
declare
  v_owner text;
begin
  select company_id into v_owner
    from public.payment_terms
   where terms_id = new.payment_terms;

  -- Global (owner null) is available to everyone. Otherwise it must be ours.
  if v_owner is not null and v_owner is distinct from new.company_id then
    raise exception 'payment term % is not available to company %', new.payment_terms, new.company_id;
  end if;
  return new;
end;
$$;

drop trigger if exists customers_payment_terms_available on public.customers;
create trigger customers_payment_terms_available
  before insert or update of payment_terms on public.customers
  for each row when (new.payment_terms is not null)
  execute function public.assert_payment_terms_available();

drop trigger if exists orders_payment_terms_available on public.orders;
create trigger orders_payment_terms_available
  before insert or update of payment_terms on public.orders
  for each row when (new.payment_terms is not null)
  execute function public.assert_payment_terms_available();

-- ── RLS: everyone reads the globals, nobody edits them ───────────────────────
alter table public.payment_terms enable row level security;

drop policy if exists payment_terms_select on public.payment_terms;
create policy payment_terms_select on public.payment_terms
  for select to authenticated
  using (company_id is null or company_id in (select auth_company_ids()));

-- Write policies omit the globals entirely (company_id must be one of yours), so
-- a tenant can add and edit their own terms and cannot touch the shared set.
drop policy if exists payment_terms_insert on public.payment_terms;
create policy payment_terms_insert on public.payment_terms
  for insert to authenticated
  with check (company_id is not null and company_id in (select auth_company_ids()));

drop policy if exists payment_terms_update on public.payment_terms;
create policy payment_terms_update on public.payment_terms
  for update to authenticated
  using (company_id is not null and company_id in (select auth_company_ids()))
  with check (company_id is not null and company_id in (select auth_company_ids()));

drop policy if exists payment_terms_delete on public.payment_terms;
create policy payment_terms_delete on public.payment_terms
  for delete to authenticated
  using (company_id is not null and company_id in (select auth_company_ids()));

grant select, insert, update, delete on public.payment_terms to authenticated;
revoke all on public.payment_terms from anon;

-- ── One source of truth for "how many days is this term?" ────────────────────
create or replace function public.terms_net_days(p_terms_id text)
returns integer
language sql
stable
as $$
  select case when t.kind = 'net' then coalesce(t.net_days, 0) else 0 end
    from public.payment_terms t
   where t.terms_id = p_terms_id
$$;

comment on function public.terms_net_days(text) is
  'Days to add to order_date for a payment term. Non-net kinds (card/cod/receipt) are 0 — due immediately. NULL when the term does not exist; callers coalesce to 0.';

revoke all on function public.terms_net_days(text) from public, anon;
grant execute on function public.terms_net_days(text) to authenticated;

-- ── finalize_invoice reads the catalog instead of a hardcoded CASE ───────────
-- Byte-identical to 20260714000003 except for the v_days line. Kept whole rather
-- than patched so the current definition is readable in one place.
create or replace function public.finalize_invoice(p_order_id text)
  returns text
  language plpgsql as $$
declare
  v_company_id  text;
  v_customer    text;
  v_order_date  date;
  v_existing    text;
  v_legacy      boolean;
  v_status      text;
  v_total       numeric;
  v_opening     boolean;
  v_facility_id text;
  v_facility_tz text;
  v_today       date;
  v_cutover     date;
  v_terms       text;
  v_days        integer;
  v_num         text;
  v_seq         bigint;
begin
  select company_id, customer_id, order_date, invoice_number, is_legacy_import,
         order_status, order_total, is_opening_balance, facility_id
    into v_company_id, v_customer, v_order_date, v_existing, v_legacy,
         v_status, v_total, v_opening, v_facility_id
    from public.orders
   where order_id = p_order_id
   for update;

  if not found then
    raise exception 'order % not found (or not accessible)', p_order_id;
  end if;
  if v_existing is not null then
    return v_existing;                 -- already finalized — idempotent
  end if;
  if coalesce(v_legacy, false) then
    raise exception 'order % is a legacy import — it keeps its original QB number', p_order_id;
  end if;
  if coalesce(v_opening, false) then
    raise exception 'order % is an opening-balance stub — already an invoice', p_order_id;
  end if;
  if v_status = 'Canceled' then
    raise exception 'order % is canceled — cannot invoice it', p_order_id;
  end if;
  if coalesce(v_total, 0) <= 0 then
    raise exception 'order % has no billable total — cannot issue a zero-dollar invoice', p_order_id;
  end if;

  -- Clean-start: pre-cutover orders stay in QuickBooks, never finalized in STRATA.
  -- Timezone-aware so an order dated the facility's own local "today" (or later) is
  -- never blocked by a UTC-skewed cutover_date.
  select cutover_date into v_cutover from public.billing_settings where company_id = v_company_id;
  select time_zone   into v_facility_tz from public.facilities   where facility_id = v_facility_id;
  v_today := (now() at time zone coalesce(nullif(v_facility_tz, ''), 'UTC'))::date;
  if v_cutover is not null and v_order_date is not null
     and v_order_date < v_cutover
     and v_order_date < v_today then
    raise exception 'order % predates the STRATA cutover (%) — pre-cutover invoices stay in QuickBooks', p_order_id, v_cutover;
  end if;

  -- Terms: the per-order override wins, else the customer default.
  select coalesce(
           (select payment_terms from public.orders    where order_id    = p_order_id),
           (select payment_terms from public.customers where customer_id = v_customer)
         ) into v_terms;
  -- Was: CASE v_terms WHEN 'net_15' THEN 15 ... ELSE 0 END — one of five copies.
  v_days := coalesce(public.terms_net_days(v_terms), 0);

  select a.invoice_sequence, a.invoice_number into v_seq, v_num
    from public.allocate_invoice_number(v_company_id) a;

  update public.orders
     set invoice_number         = v_num,
         invoice_sequence       = v_seq,
         invoice_state          = 'open',
         -- A due date set manually before posting survives; else derive from terms.
         due_date               = coalesce(due_date, coalesce(v_order_date, current_date) + v_days),
         invoice_terms_snapshot = coalesce(v_terms, 'receipt'),
         posted                 = true,
         pay_token              = coalesce(pay_token, gen_random_uuid()::text)
   where order_id = p_order_id;

  return v_num;
end;
$$;

commit;

notify pgrst, 'reload schema';
