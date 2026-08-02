-- Who gets a "Pay" button on their invoice.
--
-- 🔴 THE BUG THIS CLOSES. The invoice email ALWAYS rendered a "Pay $X" button.
-- It keyed on nothing but the shop slug and the order's pay_token — never on
-- whether the company can actually take a card. So a roaster whose payment
-- account was pending, rejected, or never started still emailed customers a Pay
-- button, and when there was no shop slug the link fell back to the STRATA
-- homepage: a customer clicking "Pay $1,234" landed on a marketing page.
--
-- THE MODEL, per the directive: card/ACH is how we want invoices paid, so it is
-- ON for every customer by default and the roaster opts a customer OUT — the one
-- who insists on posting a check. It is a property of the CUSTOMER, not of each
-- invoice: nobody wants to answer "payment link?" on every send, and the answer
-- is stable per account.
--
-- Two independent gates, and both must pass for a button to appear:
--   1. COMPANY  — plan allows card payments AND company_kyc.status='approved'.
--      Same pair shop_config's payments toggle already requires; the invoice
--      path simply never consulted it.
--   2. CUSTOMER — this flag.
--
-- Failing gate 1 does NOT block the invoice. A roaster who has just migrated off
-- QuickBooks needs to bill this week, and PayFac approval takes days; net-terms
-- wholesale customers pay by check regardless. The invoice goes, without the
-- button, and the roaster is told why.

begin;

alter table public.customers
  add column if not exists invoice_pay_link boolean not null default true;

comment on column public.customers.invoice_pay_link is
  'Include a card/ACH Pay button on this customer''s invoices. Default TRUE — card/ACH is the intended path and the roaster opts a customer out, not in. Still requires the COMPANY gate (plan can_accept_payments + company_kyc approved); this flag alone never makes a button appear.';

commit;

notify pgrst, 'reload schema';
