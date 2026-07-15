-- Per-order payment-terms + due-date override.
--
-- Terms have lived only as a CUSTOMER default (customers.payment_terms). Operators
-- need to set terms / a due date on a SINGLE order from the order-detail page (a
-- one-off Net 60, a specific due date). This adds a nullable orders.payment_terms
-- override (same CHECK domain) and teaches finalize_invoice to honour it:
--   terms    = COALESCE(order override, customer default)
--   due_date = COALESCE(already-set due_date, order_date + term days)   -- manual
--              due-date override set before posting survives finalize.
-- Both fields sit OUTSIDE guard_posted_order_immutable's checked list, so a
-- post-post due-date tweak is allowed (matches the existing guard design).

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS payment_terms text
    CHECK (payment_terms IS NULL OR payment_terms IN ('card', 'net_15', 'net_30', 'net_60'));

CREATE OR REPLACE FUNCTION public.finalize_invoice(p_order_id text)
  RETURNS text
  LANGUAGE plpgsql AS $$
DECLARE
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
BEGIN
  SELECT company_id, customer_id, order_date, invoice_number, is_legacy_import,
         order_status, order_total, is_opening_balance, facility_id
    INTO v_company_id, v_customer, v_order_date, v_existing, v_legacy,
         v_status, v_total, v_opening, v_facility_id
    FROM public.orders
   WHERE order_id = p_order_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order % not found (or not accessible)', p_order_id;
  END IF;
  IF v_existing IS NOT NULL THEN
    RETURN v_existing;                 -- already finalized — idempotent
  END IF;
  IF COALESCE(v_legacy, false) THEN
    RAISE EXCEPTION 'order % is a legacy import — it keeps its original QB number', p_order_id;
  END IF;
  IF COALESCE(v_opening, false) THEN
    RAISE EXCEPTION 'order % is an opening-balance stub — already an invoice', p_order_id;
  END IF;
  IF v_status = 'Canceled' THEN
    RAISE EXCEPTION 'order % is canceled — cannot invoice it', p_order_id;
  END IF;
  IF COALESCE(v_total, 0) <= 0 THEN
    RAISE EXCEPTION 'order % has no billable total — cannot issue a zero-dollar invoice', p_order_id;
  END IF;

  -- Clean-start: pre-cutover orders stay in QuickBooks, never finalized in STRATA.
  -- Timezone-aware so an order dated the facility's own local "today" (or later) is
  -- never blocked by a UTC-skewed cutover_date.
  SELECT cutover_date INTO v_cutover FROM public.billing_settings WHERE company_id = v_company_id;
  SELECT time_zone   INTO v_facility_tz FROM public.facilities   WHERE facility_id = v_facility_id;
  v_today := (now() AT TIME ZONE COALESCE(NULLIF(v_facility_tz, ''), 'UTC'))::date;
  IF v_cutover IS NOT NULL AND v_order_date IS NOT NULL
     AND v_order_date < v_cutover
     AND v_order_date < v_today THEN
    RAISE EXCEPTION 'order % predates the STRATA cutover (%) — pre-cutover invoices stay in QuickBooks', p_order_id, v_cutover;
  END IF;

  -- Terms: the per-order override wins, else the customer default.
  SELECT COALESCE(
           (SELECT payment_terms FROM public.orders    WHERE order_id    = p_order_id),
           (SELECT payment_terms FROM public.customers WHERE customer_id = v_customer)
         ) INTO v_terms;
  v_days := CASE v_terms WHEN 'net_15' THEN 15 WHEN 'net_30' THEN 30 WHEN 'net_60' THEN 60 ELSE 0 END;

  SELECT a.invoice_sequence, a.invoice_number INTO v_seq, v_num
    FROM public.allocate_invoice_number(v_company_id) a;

  UPDATE public.orders
     SET invoice_number         = v_num,
         invoice_sequence       = v_seq,
         invoice_state          = 'open',
         -- A due date set manually before posting survives; else derive from terms.
         due_date               = COALESCE(due_date, COALESCE(v_order_date, current_date) + v_days),
         invoice_terms_snapshot = COALESCE(v_terms, 'receipt'),
         posted                 = true,
         pay_token              = COALESCE(pay_token, gen_random_uuid()::text)
   WHERE order_id = p_order_id;

  RETURN v_num;
END;
$$;

NOTIFY pgrst, 'reload schema';
