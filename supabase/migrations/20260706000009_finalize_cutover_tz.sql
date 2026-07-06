-- finalize_invoice: make the pre-cutover guard TIMEZONE-AWARE.
--
-- Bug: the new-order form defaults order_date to the operator's BROWSER-LOCAL day,
-- but the cutover wizard recorded cutover_date from UTC (new Date().toISOString()).
-- West of UTC (e.g. Hawaii, UTC-10) these differ by a day, so a just-cut-over
-- operator's brand-new order (local "today") sits one day BEFORE the UTC cutover
-- date and finalize RAISEs "predates the STRATA cutover" — the raw DB error the
-- operator saw as a system-looking popup.
--
-- Fix: keep the business rule (genuinely old, pre-cutover QB orders stay in QB) but
-- resolve BOTH the comparison and a floor in the FACILITY's timezone. The guard now
-- fires only when the order is before cutover AND before the facility's current
-- local day — so an order dated the facility's own "today" (or later) can never be
-- blocked, regardless of the UTC skew that produced an off-by-one cutover_date.
-- (The wizard is also fixed to record cutover_date in facility-local time.)

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

  SELECT payment_terms INTO v_terms FROM public.customers WHERE customer_id = v_customer;
  v_days := CASE v_terms WHEN 'net_15' THEN 15 WHEN 'net_30' THEN 30 WHEN 'net_60' THEN 60 ELSE 0 END;

  SELECT a.invoice_sequence, a.invoice_number INTO v_seq, v_num
    FROM public.allocate_invoice_number(v_company_id) a;

  UPDATE public.orders
     SET invoice_number         = v_num,
         invoice_sequence       = v_seq,
         invoice_state          = 'open',
         due_date               = COALESCE(v_order_date, current_date) + v_days,
         invoice_terms_snapshot = COALESCE(v_terms, 'receipt'),
         posted                 = true,
         pay_token              = COALESCE(pay_token, gen_random_uuid()::text)
   WHERE order_id = p_order_id;

  RETURN v_num;
END;
$$;

NOTIFY pgrst, 'reload schema';
