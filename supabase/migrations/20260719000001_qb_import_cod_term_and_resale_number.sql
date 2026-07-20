-- QB customer import needs two customer-master fields the schema didn't cover:
--
--   1) COD payment term. "COD" is the most common term on real wholesale-roaster
--      customer lists (133 of MCR's 382). Our payment_terms only allowed
--      card/net_15/net_30/net_60, so COD imported as no term. Add 'cod' to BOTH
--      the customers CHECK (the customer default) and the orders CHECK (COD is
--      now a selectable per-order override too).
--      finalize_invoice's term->days CASE already maps any non-net term to 0
--      days, so a COD invoice's due_date = order_date — correct "cash on
--      delivery / due on receipt" semantics, no function change needed.
--
--   2) resale_number. We already flag resale_cert_received (boolean); this stores
--      the actual resale / GE excise-tax id (38 of MCR's customers carry one),
--      which matters for wholesale tax-exemption records.

BEGIN;

-- customers.payment_terms is nullable; a NULL passes `= ANY(...)` (the comparison
-- is NULL, which a CHECK treats as satisfied), so no explicit NULL guard is
-- needed here — mirror the existing definition and just append 'cod'.
ALTER TABLE public.customers DROP CONSTRAINT IF EXISTS customers_payment_terms_chk;
ALTER TABLE public.customers ADD CONSTRAINT customers_payment_terms_chk
  CHECK (payment_terms = ANY (ARRAY['card'::text, 'net_15'::text, 'net_30'::text, 'net_60'::text, 'cod'::text]));

ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_payment_terms_check;
ALTER TABLE public.orders ADD CONSTRAINT orders_payment_terms_check
  CHECK (payment_terms IS NULL OR payment_terms = ANY (ARRAY['card'::text, 'net_15'::text, 'net_30'::text, 'net_60'::text, 'cod'::text]));

ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS resale_number text;

COMMIT;
