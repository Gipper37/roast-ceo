-- The three new views stop bypassing row security.
--
-- A Postgres view runs with its OWNER's privileges unless told otherwise, and
-- the owner here is postgres — which bypasses RLS entirely. Every established
-- view in this schema (customer_revenue, customer_profitability,
-- invoice_ar_balances) carries security_invoker=true for exactly that reason.
-- The three views added this week did not, which made
-- customers_missing_resale_cert — live on prod — readable ACROSS TENANTS by any
-- authenticated user querying it directly through PostgREST: customer names,
-- emails and resale numbers, with a company_id column politely labelling whose
-- they were. The frontend filters by company; the database did not enforce it.
--
-- Found by auditing the new surfaces against the schema's own convention. The
-- fix is the convention: run the views as the CALLER, so the RLS on customers,
-- orders, tax_rate and billing_settings underneath does its job.
--
-- Guarded per view because they arrive at different times: the cert view is
-- already on prod, the other two land earlier in this same release sequence.

begin;

do $$
begin
  if to_regclass('public.customers_missing_resale_cert') is not null then
    alter view public.customers_missing_resale_cert set (security_invoker = true);
  end if;
  if to_regclass('public.tax_liability_by_rate') is not null then
    alter view public.tax_liability_by_rate set (security_invoker = true);
  end if;
  if to_regclass('public.revenue_recognized') is not null then
    alter view public.revenue_recognized set (security_invoker = true);
  end if;
end $$;

commit;
