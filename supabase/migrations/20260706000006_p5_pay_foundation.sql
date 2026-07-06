-- Invoice-of-record P5 (Phase A foundation): payment-link + aging-decoupling data
-- model. Adds orders.pay_token (link secret, mirrors receipt_token) + orders.
-- aging_excluded (imported invoices stay sendable/payable but drop out of aging).
-- Extends finalize_invoice to mint the pay_token + enforce the pre-cutover guard
-- (clean-start: an order dated before the STRATA cutover can't be invoiced — it
-- stays in QuickBooks). All additive/gated — no company is in Mode A yet.
-- Plan: memory/project_invoice_payment_p5.md.

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS pay_token       text,
  ADD COLUMN IF NOT EXISTS aging_excluded  boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN public.orders.pay_token IS 'Per-invoice payment-link secret (crypto UUID, minted at finalize). Authorizes VIEWING the invoice pay page; paying requires an authenticated customer_users-bound session.';
COMMENT ON COLUMN public.orders.aging_excluded IS 'True for imported QB invoices: sendable + payable via STRATA but excluded from A/R aging (collect-without-cluttering-aging).';

CREATE UNIQUE INDEX IF NOT EXISTS orders_company_pay_token_uidx
  ON public.orders (company_id, pay_token) WHERE pay_token IS NOT NULL;

-- Fix the claim/bind TOCTOU: one customer per (company, email). Verified 0 dupes.
CREATE UNIQUE INDEX IF NOT EXISTS customers_company_lower_email_uidx
  ON public.customers (company_id, lower(email)) WHERE email IS NOT NULL AND email <> '';

-- ── invoice_ar_balances: exclude aging_excluded invoices from aging ───────────
-- (They remain posted + open, so they're still sendable/payable — they just don't
-- appear in the aging report / getCompanyAging.)
CREATE OR REPLACE VIEW public.invoice_ar_balances WITH (security_invoker = true) AS
SELECT o.company_id, o.order_id, o.customer_id, o.invoice_number, o.invoice_state, o.due_date,
       round((COALESCE(o.order_total,0) + COALESCE(o.tax_amount,0)) * 100)::bigint AS total_cents,
       COALESCE(pa.paid_cents,0) + COALESCE(cm.credit_cents,0) AS paid_cents,
       GREATEST(round((COALESCE(o.order_total,0) + COALESCE(o.tax_amount,0)) * 100)::bigint
                - COALESCE(pa.paid_cents,0) - COALESCE(cm.credit_cents,0), 0) AS balance_due_cents
FROM public.orders o
LEFT JOIN (
  SELECT a.order_id, SUM(a.amount_cents) AS paid_cents
    FROM public.invoice_payment_allocations a
    JOIN public.invoice_payments p ON p.payment_id=a.payment_id AND p.voided_at IS NULL
   GROUP BY a.order_id
) pa ON pa.order_id = o.order_id
LEFT JOIN (
  SELECT applied_to_order_id AS order_id, SUM(amount_cents) AS credit_cents
    FROM public.credit_memos WHERE applied_to_order_id IS NOT NULL AND voided_at IS NULL
   GROUP BY applied_to_order_id
) cm ON cm.order_id = o.order_id
WHERE o.posted AND o.invoice_state IS NOT NULL AND NOT COALESCE(o.aging_excluded, false);
GRANT SELECT ON public.invoice_ar_balances TO authenticated;

-- ── finalize_invoice: + pre-cutover guard + mint pay_token ────────────────────
CREATE OR REPLACE FUNCTION public.finalize_invoice(p_order_id text)
  RETURNS text
  LANGUAGE plpgsql AS $$
DECLARE
  v_company_id text;
  v_customer   text;
  v_order_date date;
  v_existing   text;
  v_legacy     boolean;
  v_status     text;
  v_total      numeric;
  v_opening    boolean;
  v_cutover    date;
  v_terms      text;
  v_days       integer;
  v_num        text;
  v_seq        bigint;
BEGIN
  SELECT company_id, customer_id, order_date, invoice_number, is_legacy_import,
         order_status, order_total, is_opening_balance
    INTO v_company_id, v_customer, v_order_date, v_existing, v_legacy,
         v_status, v_total, v_opening
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
  SELECT cutover_date INTO v_cutover FROM public.billing_settings WHERE company_id = v_company_id;
  IF v_cutover IS NOT NULL AND v_order_date IS NOT NULL AND v_order_date < v_cutover THEN
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
