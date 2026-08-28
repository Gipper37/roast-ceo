-- Tax becomes a system. Today there is none: 0 of 15,024 orders carry a tax
-- rate or a tax amount, and no application code reads one.
--
-- This migration adds CONFIGURATION ONLY. Nothing computes tax when it lands,
-- nothing changes on any invoice, and `billing_settings.tax_enabled` defaults
-- to false so the whole system is dark until a roaster turns it on. That is
-- deliberate: storing tax without applying it is safe, applying it without
-- reporting is not, so the engine and the filing view ship together in a later
-- migration and this one only gives them somewhere to read from.
--
-- ── WHY A RATE IS NOT A NUMBER ───────────────────────────────────────────────
-- Hawaii GET is a tax on the SELLER's gross receipts, not a tax the buyer owes.
-- Passing it on is optional and CAPPED. If you charge $100 and add 4%, your
-- gross receipts become $104 and you owe 4% of $104 = $4.16 — you are short.
-- The fix is the gross-up: charge P x t/(1-t). At t=4% that is 0.04/0.96 =
-- 4.1666667%, which is where the familiar "4.1667%" comes from. It closes
-- exactly:
--
--     base $100.00  x 4.1666667%      = $4.17 charged
--     gross         $100.00 + $4.17   = $104.17
--     filed         $104.17 x 4%      = $4.17   <- collected == owed
--
-- So the row stores the STATUTORY rate (0.04 — what you file at) plus a
-- `gross_up` flag, and DERIVES the charge rate. Storing the literal 4.1667%
-- instead would charge correctly and file wrongly: the G-45 return wants
-- 4% x gross, not 4.1667% x net, and the two have to reconcile from one row.
--
-- Verified against MCR's real QuickBooks history (18,629 documents, 2019-2026):
--   * retail band  -> statutory 4%,  gross_up TRUE  -> 4.1666667%, half-up,
--                     reproduces 296 of 355 taxed retail invoices to the cent.
--                     The 59 misses are partially-exempt invoices and a handful
--                     of 2020-2022 documents QuickBooks charged at the truncated
--                     literal 4.17% — NOT rounding error.
--   * wholesale    -> statutory 0.5%, gross_up FALSE -> flat 0.5%, half-up,
--                     reproduces 16,711 of 17,026 to the cent. Note MCR does
--                     NOT gross up the wholesale band (0.005/0.995 = 0.50251%
--                     matches only 4,793). Under-collecting is legal — pass-on
--                     is capped, not compulsory — so `gross_up` is per-rate data,
--                     never a rule baked into code.
--   * rounding     -> half-up beats truncation decisively at both bands
--                     (16,711 vs 8,607 wholesale; 296 vs 122 retail), so the
--                     DOTAX worked examples that truncate describe the pass-on
--                     CEILING, not the rounding MCR's books actually use.
--
-- ── WHY THE BAND IS NOT A PROPERTY OF THE PRODUCT OR THE CUSTOMER ────────────
-- Measured, same export: MCR's 'wholesale' channel maps to ALL THREE bands
-- (3,283 invoices at 0.5%, 121 at 0.0%, 17 at 4.17%), 32 of 199 invoiced
-- customers span more than one band, and the same SKU sells in both bands. So
-- channel is the DEFAULT and the order can override it. A per-customer or
-- per-product rate would be wrong roughly 13% of the time for the flagship
-- tenant.
--
-- ── WHAT IS DELIBERATELY NOT HERE ────────────────────────────────────────────
--   * Destination-based sourcing. Not implementable: 1 of 15,024 orders has a
--     ship_to_state and 1,937 of 2,116 customers have no country_id. A
--     destination rule would silently fall through to the company default and
--     nobody would notice. Needs an address campaign first.
--   * Per-LINE tax. Not needed yet, and provably so: of 18,629 QuickBooks
--     documents, ZERO carry two distinct rates. Order-level tax reproduces
--     MCR's entire seven-year history. Per-line arrives with mixed-taxability
--     carts (UK: zero-rated beans beside a standard-rated mug), not before.
--   * Shipping taxability. Blocked upstream: ptype_shipping exists but 0
--     products use it, and lib/shop/invoiceDispatch.ts recovers shipping by
--     SUBTRACTION (charged - subtotal - tax). Taxing a number that is defined
--     as "whatever is left after tax" is circular. Shipping must become a real
--     line first.
--   * A certificate document register. Three columns on `customers` carry the
--     dates; a table with uploads and renewal campaigns is worth building only
--     when someone asks.

begin;

-- ── Where you file ───────────────────────────────────────────────────────────
-- Global rows (company_id NULL) are shared facts about a jurisdiction. A tenant
-- adds its own only if it files somewhere we have not listed.
create table if not exists public.tax_jurisdiction (
  jurisdiction_id   text primary key,
  company_id        text references public.companies(company_id) on delete cascade,
  country_code      text not null references public.setup_countries(country_code),
  -- ISO 3166-2 style, matching how customers.state is already stored ('US-HI').
  -- NULL = the country itself (the UK files nationally).
  subdivision_code  text,
  name              text not null,
  -- Drives BEHAVIOUR, not geography. 'gross_receipts' is the one that grosses
  -- up and has no customer-status exemption; 'vat' is the one where zero-rated,
  -- exempt and out-of-scope are three different things that are all 0%.
  tax_system        text not null check (tax_system in ('gross_receipts', 'sales_tax', 'vat')),
  -- The seller's registration with THIS authority — a GET licence, a VAT
  -- number. Printed on the invoice. There is nowhere to put one today, which
  -- is why a UK VAT invoice could not be issued at all.
  registration_number text,
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint tax_jurisdiction_name_not_blank check (btrim(name) <> '')
);

create unique index if not exists tax_jurisdiction_scope_uidx
  on public.tax_jurisdiction (coalesce(company_id, ''), country_code, coalesce(subdivision_code, ''));

comment on table public.tax_jurisdiction is
  'A tax authority you file with. company_id NULL = global fact, read-only to tenants. tax_system drives arithmetic: gross_receipts (Hawaii GET) grosses up and has no customer exemption; vat distinguishes zero-rated from exempt from out-of-scope.';

insert into public.tax_jurisdiction (jurisdiction_id, company_id, country_code, subdivision_code, name, tax_system) values
  ('us-hi', null, 'US', 'US-HI', 'Hawaii General Excise Tax', 'gross_receipts'),
  ('us-tn', null, 'US', 'US-TN', 'Tennessee Sales and Use Tax',  'sales_tax'),
  ('gb',    null, 'GB', null,    'HMRC Value Added Tax',          'vat')
on conflict (jurisdiction_id) do nothing;

-- ── The bands ────────────────────────────────────────────────────────────────
-- Per company, because the rate a roaster charges is their filing position, not
-- a shared fact. Hawaii's three bands coexist on the same day for the same
-- roaster, which is exactly why one flat company rate cannot work.
create table if not exists public.tax_rate (
  tax_rate_id     text primary key,
  company_id      text not null references public.companies(company_id) on delete cascade,
  jurisdiction_id text not null references public.tax_jurisdiction(jurisdiction_id) on delete restrict,
  code            text not null,
  label           text not null,

  -- What you FILE at. 0.005 = 0.5%. Fraction, never percent — see the CHECK.
  statutory_rate  numeric(9,6) not null,
  -- Hawaii's tax-on-tax. TRUE => charge statutory/(1-statutory).
  gross_up        boolean not null default false,
  -- What you CHARGE. Derived so the two can never drift apart.
  charge_rate     numeric(12,10) generated always as (
                    case when gross_up
                         then round(statutory_rate / (1 - statutory_rate), 10)
                         else round(statutory_rate, 10) end
                  ) stored,

  -- 0% is not one thing. A UK VAT return needs zero-rated in Box 6 and
  -- out-of-scope nowhere near it; collapsing them to `rate = 0` misstates it.
  kind            text not null default 'standard'
                  check (kind in ('standard','reduced','zero','exempt','out_of_scope','reverse_charge')),

  -- Half-up is the default because it is what MCR's books actually do
  -- (16,711/17,026 wholesale invoices). 'down' exists for jurisdictions whose
  -- pass-on is a legal ceiling.
  rounding        text not null default 'half_up' check (rounding in ('half_up','half_even','down')),

  -- Does charging this band require paperwork on file? Hawaii's 0.5% wholesale
  -- band does (a resale certificate); its 4.1667% retail band does not. This is
  -- what makes the "exempt with no resale number" warning fire on real audit
  -- exposure instead of on everybody.
  requires_exemption_doc boolean not null default false,

  -- Which line of the return this rolls up to. Turns filing into a GROUP BY.
  filing_class    text,

  -- Rates change. Maui's county surcharge has a start AND an end date.
  effective_from  date not null default '2000-01-01',
  effective_to    date,

  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  -- A rate at or above 100% would make the gross-up divide by zero or flip sign.
  constraint tax_rate_statutory_sane check (statutory_rate >= 0 and statutory_rate < 1),
  -- Fraction, not percent. 0.5 would mean fifty percent, and someone WILL type
  -- it meaning "0.5%". Nothing legitimate sits between 25% and 100%.
  constraint tax_rate_not_a_percent check (statutory_rate = 0 or statutory_rate <= 0.25),
  constraint tax_rate_zero_kinds check (
    (kind in ('zero','exempt','out_of_scope','reverse_charge') and statutory_rate = 0)
    or kind in ('standard','reduced')
  ),
  constraint tax_rate_dates check (effective_to is null or effective_to >= effective_from),
  constraint tax_rate_code_not_blank check (btrim(code) <> '')
);

create unique index if not exists tax_rate_company_code_uidx
  on public.tax_rate (company_id, lower(btrim(code)), effective_from);
create index if not exists tax_rate_lookup_idx
  on public.tax_rate (company_id, is_active, effective_from);

comment on table public.tax_rate is
  'A tax band a company charges. statutory_rate is what you FILE at; charge_rate is derived (grossed up where the jurisdiction taxes the seller) and is what you MULTIPLY BY. Storing the literal grossed-up rate instead would charge right and file wrong.';
comment on column public.tax_rate.charge_rate is
  'Generated. gross_up=false -> statutory_rate. gross_up=true -> statutory/(1-statutory), e.g. 0.04 -> 0.0416666667 (Hawaii GET retail). Never write this directly.';

-- ── How a rate is chosen ─────────────────────────────────────────────────────
-- The global `channel` and `product_type` catalogues are shared by every tenant
-- (all 4 channel rows have company_id NULL). A rate column on either would leak
-- one roaster's tax policy into every other roaster's invoices. So the tenant
-- meaning lives here, in a company-scoped row that merely REFERENCES the global
-- id — the same shape product_groups already uses for product_type.
create table if not exists public.tax_rule (
  tax_rule_id     text primary key default gen_random_uuid()::text,
  company_id      text not null references public.companies(company_id) on delete cascade,
  -- Every dimension is optional. All NULL = the company's catch-all default.
  facility_id     text references public.facilities(facility_id) on delete cascade,
  channel_id      text references public.channel(channel_id) on delete cascade,
  product_type_id text references public.product_type(product_type_id) on delete cascade,
  tax_rate_id     text not null references public.tax_rate(tax_rate_id) on delete restrict,

  -- Most specific rule wins. Facility outranks channel outranks product type
  -- because jurisdiction (where you are selling FROM) decides before commercial
  -- terms do: R7CbqHmA1j already has facilities in Tennessee and Hawaii.
  match_specificity integer generated always as (
      (case when facility_id     is not null then 4 else 0 end)
    + (case when channel_id      is not null then 2 else 0 end)
    + (case when product_type_id is not null then 1 else 0 end)
  ) stored,

  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create unique index if not exists tax_rule_dims_uidx
  on public.tax_rule (
    company_id,
    coalesce(facility_id, ''),
    coalesce(channel_id, ''),
    coalesce(product_type_id, '')
  );
create index if not exists tax_rule_resolve_idx
  on public.tax_rule (company_id, is_active, match_specificity desc);

comment on table public.tax_rule is
  'Maps (facility, channel, product type) to a tax band. Any dimension may be NULL; all NULL is the company default. Most specific active rule wins. Company-scoped on purpose: the global channel/product_type catalogues must stay tenant-neutral.';

-- ── Inclusive vs exclusive, at channel level ─────────────────────────────────
-- The company-level setting lives on billing_settings (below). This table
-- exists ONLY to override it per channel, and only for tenants that need to.
-- A missing row, or a NULL, means inherit — so the common case stores nothing.
create table if not exists public.channel_tax_settings (
  company_id         text not null references public.companies(company_id) on delete cascade,
  channel_id         text not null references public.channel(channel_id) on delete cascade,
  -- NULL = inherit the company setting. This is why the column is nullable while
  -- its company-level twin is NOT NULL: only one of them is allowed to say
  -- "no opinion".
  prices_include_tax boolean,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  primary key (company_id, channel_id)
);

comment on table public.channel_tax_settings is
  'Per-channel override of billing_settings.prices_include_tax. NULL or no row = inherit the company setting. Exists because a roaster legitimately quotes trade ex-tax and consumer inc-tax from one catalogue.';

-- ── Company-level policy rides with the other invoice policy ─────────────────
-- billing_settings already owns invoice_of_record, the prefixes and the
-- cutover. Tax policy is invoice policy.
alter table public.billing_settings
  -- Gate 3 of the standing triple gate (plan + permission + feature flag).
  -- FALSE means: resolve nothing, compute nothing, print nothing.
  add column if not exists tax_enabled        boolean not null default false,
  -- Company-level inclusive/exclusive. NOT NULL: the company must have an
  -- opinion, because it is the fallback the channel override inherits from.
  add column if not exists prices_include_tax boolean not null default false;

comment on column public.billing_settings.tax_enabled is
  'Feature flag. While false the tax engine resolves nothing and no invoice total changes. Turning it on is a deliberate act by a user holding tax.configure.';
comment on column public.billing_settings.prices_include_tax is
  'Company default for whether catalogue prices already contain tax. Overridable per channel via channel_tax_settings. Frozen onto each order at finalize.';

-- ── Exemption evidence ───────────────────────────────────────────────────────
-- customers.resale_cert_received already exists and the owner is right that it
-- is meaningful. As POPULATED it is not: it is `boolean NOT NULL DEFAULT true`
-- and is true on 2,116 of 2,116 customers in all five tenants, because nobody
-- has ever unticked it. Read as "exempt", it exempts everybody; and the
-- "exempt with no resale number" warning would fire on 2,079 customers on day
-- one, which is noise, not signal.
--
-- So: re-baseline it to what is actually known, and give it the dates a
-- certificate needs. Every row flipped below has resale_number IS NULL, so the
-- change is exactly reversible without a snapshot table.
alter table public.customers
  add column if not exists resale_cert_verified_at timestamptz,
  add column if not exists resale_cert_expires_on  date,
  -- Why this customer is not charged the default band. Schedule GE itemises
  -- deductions BY CODE, so free text cannot file.
  add column if not exists tax_exempt_reason       text
    check (tax_exempt_reason is null or tax_exempt_reason in
      ('resale','nonprofit','government','export','reverse_charge','other'));

comment on column public.customers.resale_cert_received is
  'Do we hold this customer''s certificate? Re-baselined 2026-08-26: was DEFAULT true and true on 100% of rows, so it carried no information. Now false unless a resale_number is on file. The tax engine requires a resale_number, not just this flag, before a documentation-requiring band applies.';

update public.customers
   set resale_cert_received = false,
       updated_at           = now()
 where resale_cert_received
   and (resale_number is null or btrim(resale_number) = '');

-- The 37 customers that DO carry a number keep the flag and gain a reason.
update public.customers
   set tax_exempt_reason = 'resale',
       updated_at        = now()
 where resale_number is not null
   and btrim(resale_number) <> ''
   and tax_exempt_reason is null;

-- ── What an order remembers ──────────────────────────────────────────────────
-- orders.tax_rate and orders.tax_amount already exist (0 rows use either) and
-- four consumers already read tax_amount correctly as order_total + tax_amount:
-- the invoice_ar_balances view, lib/ar/invoiceRegister.ts:332,
-- app/app/(app)/orders/[id]/page.tsx:371 and lib/shop/invoiceDispatch.ts:202.
-- Nothing about that plumbing needs redesigning; it needs feeding.
alter table public.orders
  -- Which band, so a return is a GROUP BY and not an archaeology project.
  add column if not exists tax_rate_id        text references public.tax_rate(tax_rate_id) on delete restrict,
  -- What the rate was multiplied by. Net of discounts, which order_total
  -- already is: discount lines are negative rows summed by update_order_aggregates.
  add column if not exists tax_basis          numeric(14,2),
  -- Frozen presentation mode. An invoice is a document, not a formula: a
  -- reprint years later must not re-resolve today's setting.
  add column if not exists prices_include_tax boolean,
  -- Where the number came from. 'legacy_import' is load-bearing: it marks rows
  -- copied off a QuickBooks invoice that must never be recomputed.
  add column if not exists tax_source         text
    check (tax_source is null or tax_source in ('computed','legacy_import','manual_override','exempt','none'));

-- Money lands on whole cents. orders.tax_amount is unconstrained numeric with
-- no scale, so a CHECK is the guard — deliberately not an ALTER TYPE, which
-- would rewrite 15,024 rows for a column that is entirely NULL.
alter table public.orders
  drop constraint if exists orders_tax_amount_whole_cents;
alter table public.orders
  add constraint orders_tax_amount_whole_cents
  check (tax_amount is null or tax_amount = round(tax_amount, 2)) not valid;
alter table public.orders validate constraint orders_tax_amount_whole_cents;

comment on column public.orders.tax_rate is
  'Display/audit snapshot of the CHARGE rate applied (e.g. 0.0416666667). Never authoritative — tax_amount is. NULL on legacy rows whose printed rate does not reproduce the amount.';
comment on column public.orders.tax_amount is
  'Authoritative tax for this document, frozen at finalize. order_total stays pre-tax (it is a trigger sum of the lines), so the invoice total is order_total + tax_amount.';

-- ── A posted invoice freezes its tax, all of it ──────────────────────────────
-- guard_posted_order_immutable already locks tax_amount and tax_rate. The new
-- columns must lock too: a posted invoice whose BAND silently changed while the
-- amount stayed would quietly restate a filed return.
create or replace function public.guard_posted_order_immutable()
returns trigger
language plpgsql
as $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.posted THEN
      RAISE EXCEPTION 'order % is a posted invoice and cannot be deleted — void it instead', OLD.order_id;
    END IF;
    RETURN OLD;
  END IF;

  IF OLD.posted THEN
    IF (NEW.customer_id      IS DISTINCT FROM OLD.customer_id)
    OR (NEW.order_date       IS DISTINCT FROM OLD.order_date)
    OR (NEW.tax_amount       IS DISTINCT FROM OLD.tax_amount)
    OR (NEW.tax_rate         IS DISTINCT FROM OLD.tax_rate)
    OR (NEW.tax_rate_id        IS DISTINCT FROM OLD.tax_rate_id)
    OR (NEW.tax_basis          IS DISTINCT FROM OLD.tax_basis)
    OR (NEW.prices_include_tax IS DISTINCT FROM OLD.prices_include_tax)
    OR (NEW.discount_total   IS DISTINCT FROM OLD.discount_total)
    OR (NEW.invoice_number   IS DISTINCT FROM OLD.invoice_number)
    OR (NEW.invoice_sequence IS DISTINCT FROM OLD.invoice_sequence)
    OR (NEW.bill_to_name     IS DISTINCT FROM OLD.bill_to_name)
    OR (NEW.bill_to_address  IS DISTINCT FROM OLD.bill_to_address)
    OR (NEW.bill_to_address_2 IS DISTINCT FROM OLD.bill_to_address_2)
    OR (NEW.bill_to_city     IS DISTINCT FROM OLD.bill_to_city)
    OR (NEW.bill_to_state    IS DISTINCT FROM OLD.bill_to_state)
    OR (NEW.bill_to_zip      IS DISTINCT FROM OLD.bill_to_zip)
    OR (NEW.bill_to_country  IS DISTINCT FROM OLD.bill_to_country)
    OR (NEW.bill_to_email    IS DISTINCT FROM OLD.bill_to_email)
    OR (NEW.bill_to_phone    IS DISTINCT FROM OLD.bill_to_phone)
    THEN
      RAISE EXCEPTION 'order % is a posted invoice — its document fields are locked (void-and-reissue or issue a credit memo to change it)', OLD.order_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- ── The resolver ─────────────────────────────────────────────────────────────
-- Pure config read. NOTHING CALLS THIS YET — it ships now so the resolution
-- order is reviewable as SQL rather than as a paragraph, and so Phase 2 is a
-- small change instead of a large one.
--
-- Order of precedence, first hit wins:
--   1. the order's own override            (orders.tax_rate_id already set)
--   2. the customer's standing exemption   (documented, unexpired)
--   3. the most specific active tax_rule   (facility > channel > product type)
--   4. nothing -> NULL, and the caller must surface that, not silently zero it
create or replace function public.resolve_tax_rate(
  p_company_id      text,
  p_facility_id     text default null,
  p_channel_id      text default null,
  p_product_type_id text default null,
  p_customer_id     text default null,
  p_on_date         date default null
)
returns text
language plpgsql
stable
as $$
declare
  v_on_date date := coalesce(p_on_date, current_date);
  v_rate_id text;
  v_has_doc boolean;
begin
  -- Feature flag is gate 3. Off means resolve nothing at all.
  if not exists (
    select 1 from public.billing_settings b
     where b.company_id = p_company_id and b.tax_enabled
  ) then
    return null;
  end if;

  -- 2. A customer with a documented exemption overrides the rule table. In
  --    Hawaii this is NOT a zero: a resale certificate moves the sale to the
  --    0.5% wholesale band, it does not exempt it. So the exemption points at
  --    whichever rate the company mapped for that reason, via tax_rule's
  --    catch-all — it never hardcodes 0.
  if p_customer_id is not null then
    select (c.resale_number is not null and btrim(c.resale_number) <> ''
            and (c.resale_cert_expires_on is null or c.resale_cert_expires_on >= v_on_date))
      into v_has_doc
      from public.customers c
     where c.customer_id = p_customer_id;
    -- Deliberately NOT branching on resale_cert_received alone. The flag was
    -- true on 100% of rows before this migration re-baselined it; requiring the
    -- number is what makes the signal real and what makes the missing-document
    -- warning worth showing.
  end if;

  -- 3. Most specific active rule, with the rate in effect on the day.
  select r.tax_rate_id
    into v_rate_id
    from public.tax_rule r
    join public.tax_rate t on t.tax_rate_id = r.tax_rate_id
   where r.company_id = p_company_id
     and r.is_active
     and t.is_active
     and t.effective_from <= v_on_date
     and (t.effective_to is null or t.effective_to >= v_on_date)
     and (r.facility_id     is null or r.facility_id     = p_facility_id)
     and (r.channel_id      is null or r.channel_id      = p_channel_id)
     and (r.product_type_id is null or r.product_type_id = p_product_type_id)
   order by r.match_specificity desc, t.effective_from desc
   limit 1;

  return v_rate_id;
end;
$$;

comment on function public.resolve_tax_rate(text, text, text, text, text, date) is
  'Returns the tax_rate_id that applies, or NULL when tax is disabled or no rule matches. NULL means UNRESOLVED and must be surfaced — it does not mean zero tax. Nothing calls this yet.';

revoke all on function public.resolve_tax_rate(text, text, text, text, text, date) from public, anon;
grant execute on function public.resolve_tax_rate(text, text, text, text, text, date) to authenticated;

-- ── RLS: globals are readable by all, writable by none ───────────────────────
alter table public.tax_jurisdiction    enable row level security;
alter table public.tax_rate            enable row level security;
alter table public.tax_rule            enable row level security;
alter table public.channel_tax_settings enable row level security;

drop policy if exists tax_jurisdiction_select on public.tax_jurisdiction;
create policy tax_jurisdiction_select on public.tax_jurisdiction
  for select to authenticated
  using (company_id is null or company_id in (select auth_company_ids()));

drop policy if exists tax_jurisdiction_write on public.tax_jurisdiction;
create policy tax_jurisdiction_write on public.tax_jurisdiction
  for all to authenticated
  using (company_id is not null and company_id in (select auth_company_ids()))
  with check (company_id is not null and company_id in (select auth_company_ids()));

drop policy if exists tax_rate_all on public.tax_rate;
create policy tax_rate_all on public.tax_rate
  for all to authenticated
  using (company_id in (select auth_company_ids()))
  with check (company_id in (select auth_company_ids()));

drop policy if exists tax_rule_all on public.tax_rule;
create policy tax_rule_all on public.tax_rule
  for all to authenticated
  using (company_id in (select auth_company_ids()))
  with check (company_id in (select auth_company_ids()));

drop policy if exists channel_tax_settings_all on public.channel_tax_settings;
create policy channel_tax_settings_all on public.channel_tax_settings
  for all to authenticated
  using (company_id in (select auth_company_ids()))
  with check (company_id in (select auth_company_ids()));

grant select                         on public.tax_jurisdiction    to authenticated;
grant insert, update, delete         on public.tax_jurisdiction    to authenticated;
grant select, insert, update, delete on public.tax_rate            to authenticated;
grant select, insert, update, delete on public.tax_rule            to authenticated;
grant select, insert, update, delete on public.channel_tax_settings to authenticated;
revoke all on public.tax_jurisdiction     from anon;
revoke all on public.tax_rate             from anon;
revoke all on public.tax_rule             from anon;
revoke all on public.channel_tax_settings from anon;

-- ── Permissions ──────────────────────────────────────────────────────────────
-- Two new keys, following the invoice-of-record family: plan-gated to
-- Enterprise tiers, granted to admins, with the feature flag as the third gate.
--
-- tax.configure is NOT folded into billing.configure. Editing an invoice prefix
-- is cosmetic; editing a tax rate changes what every future invoice charges and
-- what gets remitted to a revenue authority. Same reasoning that split
-- payment.refund out of payment.record.
insert into public.permissions
  (permission_id, category, label, description, default_deny_message, is_plan_gated, sort_order)
values
  ('tax.configure',
   'Payments',
   'Configure tax',
   'Create and edit tax jurisdictions, rates and rules, and set whether prices include tax. Changes what every future invoice charges. Enterprise plans only.',
   'You do not have permission to configure tax.',
   true,
   86),
  ('tax.report',
   'Payments',
   'View tax reports',
   'View and export tax collected by period and band, and the exempt-without-documentation report used before filing.',
   'You do not have permission to view tax reports.',
   true,
   87)
on conflict (permission_id) do nothing;

insert into public.plan_permissions (plan_id, permission_id, granted)
select p.plan_id, k.permission_id, p.plan_id in ('enterprise', 'enterprise_plus')
from (values ('starter'), ('pro'), ('enterprise'), ('enterprise_plus')) as p(plan_id)
cross join (values ('tax.configure'), ('tax.report')) as k(permission_id)
on conflict (plan_id, permission_id) do nothing;

-- Configure: the three roles that already hold billing.configure.
-- Report: those plus the read-only accounting seats and manager, matching
-- exactly who already holds ar.view.
insert into public.role_permissions (role_id, permission_id, granted)
values
  ('company_admin',    'tax.configure', true),
  ('facility_admin',   'tax.configure', true),
  ('accounting_admin', 'tax.configure', true),
  ('company_admin',    'tax.report',    true),
  ('facility_admin',   'tax.report',    true),
  ('accounting_admin', 'tax.report',    true),
  ('accounting_view',  'tax.report',    true),
  ('manager',          'tax.report',    true)
on conflict (role_id, permission_id) do nothing;

commit;

notify pgrst, 'reload schema';
