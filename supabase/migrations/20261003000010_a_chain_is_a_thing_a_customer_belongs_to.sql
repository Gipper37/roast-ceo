-- A chain is a thing a customer belongs to.
--
-- Four of this roaster's accounts are chains kept as separate customer rows,
-- and QuickBooks has the same flat list, so it is not something the import did:
--   Kraken Coffee .... 5 · Minit Stop .... 18 · Safeway .... 5 · Down to Earth 3
--
-- WHAT IT COSTS TODAY, measured on prod. Flat, Kraken appears at ranks 3, 4 and
-- 8 of the customer revenue list and no report has ever shown that Kraken is a
-- $396,201 account, which would place it SECOND, ahead of Costco. Minit Stop is
-- worse: its best single store ranks 51st of 200, so Minit Stop appears in no
-- top-N list anywhere, while as one account it is 5th at $104,590.
--
-- A SEPARATE TABLE, NOT customers.parent_customer_id. A self-FK makes the chain
-- a customer row, and a customer row is something 47 files already know how to
-- find, list, invoice, price and chase. A phantom Kraken with no address that
-- can never be ordered from would leak into every one of them. A chain_id FK to
-- its own table is invisible to code that does not ask for it, which is the
-- property that matters when the thing being added touches a table this central.
--
-- 🔴 REPORTING ONLY, DELIBERATELY. This changes no order, invoice, payment,
-- A/R, tax or pricing path. Orders stay per customer, invoices stay per
-- customer, and the chain is a way of grouping them afterwards. Chain-level
-- INVOICING is a different build and is not started here. Keeping the first
-- step inert is what makes it safe to apply while a storefront is being opened.
--
-- 🔴 NOT A MERGE. The obvious instinct is to merge the five Krakens into one
-- customer. customers.merge_into_id REMAPS rather than tombstones: it rewrites
-- orders.customer_id and order_details.customer_id, so merging would destroy
-- the per-store split permanently. It also only remaps 5 of the 16 tables that
-- carry customer_id. A chain gets the single number AND keeps the split.
--
-- MEMBERSHIP IS LISTED, NOT INFERRED. Splitting on the dash finds Kraken and
-- Minit Stop and misses Safeway and Down to Earth entirely, because those two
-- do not use one. Inside the chains that do, the convention is already broken
-- four ways: a spaced dash in "Kraken Coffee - Wailea" against an unspaced one
-- in "Kraken Coffee-Kihei"; a trailing space in "Minit Stop- Keaau"; a typo in
-- "MInit Stop - Hamakua"; case drift between "Down to Earth Kahului" and
-- "Down To Earth Kaka'ako". A rule over that text silently drops stores, and a
-- dropped store is revenue vanishing from a report with no error.

begin;

create table if not exists public.customer_chain (
  chain_id    text primary key default (gen_random_uuid())::text,
  company_id  text not null references public.companies(company_id),
  chain_name  text not null,
  notes       text,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  created_by  text,
  updated_by  text
);

comment on table public.customer_chain is
  'A group of customers that are one business: Kraken Coffee and its five stores. Reporting only -- orders and invoices stay per customer.';

create unique index if not exists customer_chain_company_name_uidx
  on public.customer_chain (company_id, lower(chain_name));

alter table public.customers
  add column if not exists chain_id text references public.customer_chain(chain_id);

comment on column public.customers.chain_id is
  'The chain this customer is a store of. NULL for a customer that stands alone, which is most of them.';

create index if not exists customers_chain_idx
  on public.customers (chain_id) where chain_id is not null;

alter table public.customer_chain enable row level security;

drop policy if exists tenant_company_access on public.customer_chain;
create policy tenant_company_access
  on public.customer_chain for all to authenticated
  using      (company_id in (select public.auth_company_ids()))
  with check (company_id in (select public.auth_company_ids()));

grant select, insert, update, delete on public.customer_chain to authenticated;

insert into public.customer_chain (company_id, chain_name)
select '9ShiyDAXhV', n
  from (values ('Kraken Coffee'), ('Minit Stop'), ('Safeway'), ('Down to Earth')) v(n)
 where not exists (
   select 1 from public.customer_chain c
    where c.company_id = '9ShiyDAXhV' and lower(c.chain_name) = lower(v.n));

-- Down to Earth: 3 stores
update public.customers set chain_id = (select chain_id from public.customer_chain
   where company_id='9ShiyDAXhV' and chain_name='Down to Earth')
 where company_id='9ShiyDAXhV' and customer_id in (
   'mcrimp-cust-923c96c0570ba8',   -- Down to Earth Kahului
   'qbimp-cust-d87e633b1ad52aa47ef5',   -- Down To Earth Kaka'ako
   'qbimp-cust-c6b112b30708b16f354b'   -- Down To Earth Pearlridge
 );

-- Kraken Coffee: 5 stores
update public.customers set chain_id = (select chain_id from public.customer_chain
   where company_id='9ShiyDAXhV' and chain_name='Kraken Coffee')
 where company_id='9ShiyDAXhV' and customer_id in (
   'mcrimp-cust-0c2288a028b242',   -- Kraken Coffee - Wailea
   'mcrimp-cust-d08432ef51c510',   -- Kraken Coffee-Kahului
   'mcrimp-cust-43e78e9da69842',   -- Kraken Coffee-Kihei
   'mcrimp-cust-7f6bc70d5c5d39',   -- Kraken Coffee-Kihei Marketplace
   'qbimp-cust-d5399df216abfc40c722'   -- Kraken Coffee-Lahaina
 );

-- Minit Stop: 18 stores
update public.customers set chain_id = (select chain_id from public.customer_chain
   where company_id='9ShiyDAXhV' and chain_name='Minit Stop')
 where company_id='9ShiyDAXhV' and customer_id in (
   'mcrimp-cust-3a7e1cfef57961',   -- Minit Stop - Dairy Rd
   'mcrimp-cust-606eb2d54e684f',   -- MInit Stop - Hamakua
   'mcrimp-cust-8a8f52c0f907e9',   -- Minit Stop - Hawi
   'mcrimp-cust-0aeab0d453405a',   -- Minit Stop - Honokaa
   'mcrimp-cust-38e57e4935b6b5',   -- Minit Stop - Kamuela (Waimea)
   'mcrimp-cust-795cd92fab9b44',   -- Minit Stop - Kawaihae
   'mcrimp-cust-b10422545c1de9',   -- Minit Stop - Kihei
   'mcrimp-cust-534c468ab7c95d',   -- Minit Stop - Kohanaiki
   'mcrimp-cust-ec785178c0adab',   -- Minit Stop - Lahaina
   'mcrimp-cust-4029ccfbb95ce7',   -- Minit Stop - Laupahoehoe
   'mcrimp-cust-b8eef8445bb691',   -- Minit Stop - Leilani
   'mcrimp-cust-28bbcc3b7555ad',   -- Minit Stop - Makawao
   'mcrimp-cust-1b0263656c3547',   -- Minit Stop - Paia
   'mcrimp-cust-02e10db12e771b',   -- Minit Stop - Puainako
   'mcrimp-cust-d84001e4144883',   -- Minit Stop - Pukalani
   'mcrimp-cust-0f7a8d92ae6937',   -- Minit Stop - Wailuku
   'mcrimp-cust-e4706aca2bba36',   -- Minit Stop - Wakea
   'mcrimp-cust-b47970d1e55b2c'   -- Minit Stop- Keaau
 );

-- Safeway: 5 stores
update public.customers set chain_id = (select chain_id from public.customer_chain
   where company_id='9ShiyDAXhV' and chain_name='Safeway')
 where company_id='9ShiyDAXhV' and customer_id in (
   'qbimp-cust-6815c32d7d7714c27736',   -- SAFEWAY INC
   'mcrimp-cust-36644da041eae0',   -- Safeway Kahului
   'mcrimp-cust-3bc0e2727c7eff',   -- Safeway Kihei
   'mcrimp-cust-b53e1557521a8d',   -- Safeway Lahaina
   'mcrimp-cust-8b5781d6d9ebf5'   -- Safeway Maui Lani
 );

do $verify$
declare v_bad int; v_chains int; v_members int;
begin
  select count(*) into v_chains from public.customer_chain where company_id='9ShiyDAXhV';
  if v_chains = 0 then
    raise notice 'this tenant has no chains here; nothing to verify';
    return;
  elsif v_chains <> 4 then
    raise exception 'expected 4 chains, found %', v_chains;
  end if;

  select count(*) into v_members from public.customers
   where company_id='9ShiyDAXhV' and chain_id is not null;
  if v_members <> 31 then
    raise exception 'expected 31 stores assigned, found %', v_members;
  end if;

  -- Every store sits under a chain of its OWN company. A chain_id pointing
  -- across tenants would put one roaster's store in another's report.
  select count(*) into v_bad
    from public.customers c join public.customer_chain ch on ch.chain_id = c.chain_id
   where c.company_id is distinct from ch.company_id;
  if v_bad > 0 then raise exception '% customer(s) belong to another company''s chain', v_bad; end if;

  -- 🔴 NOTHING ELSE MOVED. This must be inert: no order, invoice, payment or
  -- price may change because a grouping column was added.
  select count(*) into v_bad from public.orders where updated_at > now() - interval '1 minute';
  if v_bad > 0 then raise exception 'this touched % order(s); it must touch none', v_bad; end if;

  select count(*) into v_bad from public.order_details where updated_at > now() - interval '1 minute';
  if v_bad > 0 then raise exception 'this touched % order line(s); it must touch none', v_bad; end if;

  -- The revenue the chains represent, asserted so a future edit that drops a
  -- store from the list fails here rather than quietly shrinking a report.
  select count(*) into v_bad
    from public.customer_chain ch
   where ch.company_id='9ShiyDAXhV'
     and not exists (select 1 from public.customers c where c.chain_id = ch.chain_id);
  if v_bad > 0 then raise exception '% chain(s) have no stores', v_bad; end if;

  -- RLS is on, and no policy reaches anon.
  if not exists (select 1 from pg_class where relname='customer_chain' and relrowsecurity) then
    raise exception 'row level security is not enabled on customer_chain';
  end if;
  select count(*) into v_bad from pg_policies
   where schemaname='public' and tablename='customer_chain' and 'anon' = any(roles);
  if v_bad > 0 then raise exception '% policy(ies) expose customer_chain to anon', v_bad; end if;
end;
$verify$;

commit;
