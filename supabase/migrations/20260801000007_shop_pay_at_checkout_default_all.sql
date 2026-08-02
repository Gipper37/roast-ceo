-- Every customer pays at checkout in the shop. Not "every customer we hadn't
-- already decided about" — every customer.
--
-- 20260801000006 added shop_pay_at_checkout and seeded it from each customer's
-- payment_terms, on the reasoning that flipping 248 net-terms accounts to
-- card-at-checkout was a behaviour change nobody asked for. That reasoning
-- carried the exact confusion the column was created to end: it treated an
-- INVOICING setting as evidence about how the SHOP should behave.
--
-- They are separate channels. A customer on Net 30 who is invoiced for phone,
-- email and in-person orders can still be required to pay by card when they use
-- the storefront — the storefront is the channel where we can take the money at
-- the moment of sale, and that is the point of having one.
--
--   SHOP      → card/ACH REQUIRED by default.  (this column)
--   INVOICING → card/ACH POSSIBLE by default.  (customers.invoice_pay_link)
--
-- Their payment_terms are untouched: an account billed Net 30 is still billed
-- Net 30 for every invoice you send them.
--
-- Turning this OFF for a customer is an enterprise_plus privilege, enforced in
-- setCustomerShopPayAtCheckout — processing volume is the revenue, so lower
-- tiers subsidise their subscription price with it.

begin;

update public.customers
   set shop_pay_at_checkout = true
 where shop_pay_at_checkout is distinct from true;

comment on column public.customers.shop_pay_at_checkout is
  'Does this customer pay by card/ACH at wholesale-shop checkout? TRUE for everyone by default — the shop is the channel where payment is collected at the moment of sale. Independent of payment_terms, which govern INVOICES only. Turning it off is an enterprise_plus privilege.';

commit;

notify pgrst, 'reload schema';
