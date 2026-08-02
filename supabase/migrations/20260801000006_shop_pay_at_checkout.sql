-- The wholesale shop stops being steered by an invoicing setting.
--
-- 🔴 WHAT WAS WRONG. The storefront decided whether to take a card at checkout
-- by reading customers.payment_terms: 'card' → card checkout, anything else →
-- place the order and invoice later. So PAYMENT TERMS — which exist to say when
-- an invoice is due — silently controlled whether the shop could process money
-- at all. Put a customer on Net 30 because that is how you bill them, and you
-- also, invisibly, turned off card payments for everything they buy in the shop.
--
-- Those are two different questions:
--   · "When is their invoice due?"        → customers.payment_terms
--   · "Does their shop order get paid now?" → this column
-- A customer can perfectly well pay by card at checkout AND be on Net 30 for the
-- invoices you send them directly. Conflating them meant every net-terms account
-- bypassed processing in the shop as a side effect of a billing decision nobody
-- connected to it.
--
-- DEFAULT TRUE, because card/ACH is the path we want shop orders to take.
--
-- 🔴 BACKFILLED TO PRESERVE TODAY'S BEHAVIOUR, NOT TO THE DEFAULT. Setting every
-- existing customer to true would, on deploy, start demanding a card at checkout
-- from accounts that have been ordering on terms for years — MCR has 248 such
-- customers. Their behaviour is unchanged; the two settings are simply
-- independent from here, and the roaster can switch any of them on deliberately.

begin;

alter table public.customers
  add column if not exists shop_pay_at_checkout boolean not null default true;

comment on column public.customers.shop_pay_at_checkout is
  'Does this customer pay by card at wholesale-shop checkout? Default TRUE — card/ACH is the intended path. Independent of payment_terms, which only says when an INVOICE is due. Still requires the shop to have payments enabled and the company to be able to accept them.';

-- Seed from the behaviour each customer has today, so nothing changes for
-- anyone the moment this ships. New customers get the TRUE default.
update public.customers
   set shop_pay_at_checkout = (payment_terms = 'card')
 where payment_terms is not null;

commit;

notify pgrst, 'reload schema';
