-- The resale-cert chase list was resolving a tax rate PER ORDER LINE.
--
-- customers_missing_resale_cert called resolve_tax_rate() inside the
-- orders × order_details × products join — 10,551 calls for a year of MCR,
-- each one a plpgsql function running two RLS-checked queries. As the
-- authenticated role that is ~10 seconds for a single read, and the settings
-- page blocked its first paint on it (owner, 2026-09-04: 30 seconds to load).
--
-- The rate a line resolves to depends only on (company, facility, channel,
-- product type, customer, date) — so dedupe to those combos FIRST and resolve
-- once per combo: 327 calls instead of 10,551 for the same tenant.
--
-- One deliberate semantic change rides along: the rate is resolved at
-- CURRENT_DATE, not each historical order date. This list answers "who owes
-- us a certificate now", so the rate that matters is the one their purchases
-- would carry today — a customer whose old orders hit a cert-requiring rate
-- that no longer applies to them has nothing to chase. (It is also what
-- collapses the date dimension out of the combos.) Measured under RLS as an
-- MCR admin: 9.9s → 0.4s, 201 rows → 176.

begin;

create or replace view public.customers_missing_resale_cert
with (security_invoker = true) as
with combos as (
  select distinct o.company_id, o.facility_id, p.channel, p.product_type, o.customer_id
    from public.orders o
    join public.order_details od on od.order_id = o.order_id
    join public.products p on p.product_id = od.product_id
   where o.order_status <> 'Canceled'
     and o.order_date >= current_date - 365
),
charged as (
  select distinct customer_id, company_id,
         public.resolve_tax_rate(company_id, facility_id, channel, product_type,
                                 customer_id, current_date) as tax_rate_id
    from combos
)
select c.customer_id,
       c.company_id,
       c.name_company,
       c.email,
       c.resale_number,
       c.resale_cert_expires_on,
       t.tax_rate_id,
       t.label as tax_rate_label,
       case
         when coalesce(btrim(c.resale_number), '') = ''    then 'never provided'
         when c.resale_cert_expires_on < current_date       then 'expired'
         else 'expiring soon'
       end as cert_status
  from public.customers c
  join charged ch on ch.customer_id = c.customer_id
  join public.tax_rate t on t.tax_rate_id = ch.tax_rate_id
 where c.is_active
   and t.requires_resale_cert
   and (
        coalesce(btrim(c.resale_number), '') = ''
     or c.resale_cert_expires_on is null
     or c.resale_cert_expires_on < current_date + 60
   );

comment on view public.customers_missing_resale_cert is
  'Active customers who have bought in the last year on a channel/product mix '
  'that resolves TODAY to a tax rate wanting a resale certificate, and have not '
  'produced one or whose certificate has lapsed or lapses within 60 days. '
  'Drives the warning on the customer record and the list to email. Never '
  'affects what anyone is charged — the rate applies from day one and the '
  'paperwork follows. Rates are resolved once per distinct '
  '(company, facility, channel, product type, customer) combo, never per line.';

grant select on public.customers_missing_resale_cert to authenticated;

commit;
