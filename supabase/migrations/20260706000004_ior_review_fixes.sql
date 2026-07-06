-- Invoice-of-record: pre-release money-safety fixes from the adversarial review.
-- CREATE OR REPLACE (the originals are staging-only, not prod) — none of these
-- objects exist on prod yet, so this ships the corrected versions in the same
-- release. Fixes: over-allocation race + per-invoice over-application, finalize
-- guards (Canceled/$0/opening), tax-aware A/R totals, atomic credit-memo number.

-- ── 1. finalize_invoice: refuse Canceled / $0 / opening-balance orders ────────
-- Prevents a canceled or zero-total order from becoming a permanent open
-- receivable + burning a gap-free number. order_total is kept current by
-- update_order_metrics, so no SUM fallback is needed.
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
         posted                 = true
   WHERE order_id = p_order_id;

  RETURN v_num;
END;
$$;

-- ── 2. guard_allocation_not_overapplied: FOR UPDATE + per-invoice backstop ─────
-- Adds a row lock on the payment (closes the over-allocation race — two
-- concurrent splits of one payment) AND a per-invoice ceiling (allocations to a
-- single invoice can't exceed its tax-inclusive balance).
CREATE OR REPLACE FUNCTION public.guard_allocation_not_overapplied() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_pay bigint; v_alloc bigint; v_pay_cust text;
  v_ord_cust text; v_posted boolean; v_state text; v_mode text;
  v_ord_total_cents bigint; v_ord_alloc bigint;
BEGIN
  -- Lock the payment row so concurrent allocations to it serialize.
  SELECT amount_cents, customer_id INTO v_pay, v_pay_cust
    FROM public.invoice_payments WHERE payment_id = NEW.payment_id AND voided_at IS NULL
    FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'payment % missing or voided', NEW.payment_id; END IF;

  SELECT o.customer_id, o.posted, o.invoice_state,
         round((COALESCE(o.order_total,0) + COALESCE(o.tax_amount,0)) * 100)::bigint
    INTO v_ord_cust, v_posted, v_state, v_ord_total_cents
    FROM public.orders o WHERE o.order_id = NEW.order_id;
  IF NOT COALESCE(v_posted,false) OR v_state IS NULL OR v_state IN ('void','draft','written_off') THEN
    RAISE EXCEPTION 'order % is not a collectable STRATA invoice', NEW.order_id;
  END IF;
  IF v_pay_cust IS NOT NULL AND v_ord_cust IS DISTINCT FROM v_pay_cust THEN
    RAISE EXCEPTION 'allocation customer mismatch (order % belongs to a different customer)', NEW.order_id;
  END IF;

  SELECT invoice_of_record INTO v_mode FROM public.billing_settings WHERE company_id = NEW.company_id;
  IF COALESCE(v_mode,'quickbooks') <> 'strata' THEN
    RAISE EXCEPTION 'company % is not in STRATA billing mode', NEW.company_id;
  END IF;

  -- Ceiling 1: allocations for THIS payment can't exceed the payment.
  SELECT COALESCE(SUM(amount_cents),0) INTO v_alloc FROM public.invoice_payment_allocations
   WHERE payment_id = NEW.payment_id AND allocation_id IS DISTINCT FROM NEW.allocation_id;
  IF v_alloc + NEW.amount_cents > v_pay THEN
    RAISE EXCEPTION 'allocations (%) exceed payment (%)', v_alloc + NEW.amount_cents, v_pay;
  END IF;

  -- Ceiling 2: allocations to THIS invoice (from all live payments) can't exceed
  -- its balance. Prevents silently over-paying one invoice.
  SELECT COALESCE(SUM(a.amount_cents),0) INTO v_ord_alloc
    FROM public.invoice_payment_allocations a
    JOIN public.invoice_payments p ON p.payment_id = a.payment_id AND p.voided_at IS NULL
   WHERE a.order_id = NEW.order_id AND a.allocation_id IS DISTINCT FROM NEW.allocation_id;
  v_ord_alloc := v_ord_alloc + COALESCE((SELECT SUM(amount_cents) FROM public.credit_memos
                                          WHERE applied_to_order_id = NEW.order_id AND voided_at IS NULL), 0);
  IF v_ord_alloc + NEW.amount_cents > v_ord_total_cents THEN
    RAISE EXCEPTION 'allocation would over-apply invoice % (balance %, attempted %)',
      NEW.order_id, v_ord_total_cents - v_ord_alloc, NEW.amount_cents;
  END IF;

  RETURN NEW;
END; $$;

-- ── 3. recompute_invoice_ar_state: tax-aware total ────────────────────────────
CREATE OR REPLACE FUNCTION public.recompute_invoice_ar_state(p_order_id text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_total bigint; v_paid bigint; v_state text; v_due date; v_posted boolean; v_new text;
BEGIN
  SELECT round((COALESCE(order_total,0) + COALESCE(tax_amount,0)) * 100)::bigint,
         invoice_state, due_date, posted
    INTO v_total, v_state, v_due, v_posted FROM public.orders WHERE order_id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RETURN NULL; END IF;
  IF NOT COALESCE(v_posted,false) OR v_state IS NULL THEN RETURN v_state; END IF;
  IF v_state IN ('void','written_off') THEN RETURN v_state; END IF;

  SELECT COALESCE(SUM(a.amount_cents),0) INTO v_paid
    FROM public.invoice_payment_allocations a
    JOIN public.invoice_payments p ON p.payment_id = a.payment_id
   WHERE a.order_id = p_order_id AND p.voided_at IS NULL;
  v_paid := v_paid + COALESCE((SELECT SUM(amount_cents) FROM public.credit_memos
                                WHERE applied_to_order_id = p_order_id AND voided_at IS NULL), 0);

  v_new := CASE
             WHEN v_paid >= v_total AND v_total > 0 THEN 'paid'
             WHEN v_paid > 0 THEN 'partial'
             WHEN v_due IS NOT NULL AND v_due < current_date THEN 'overdue'
             ELSE 'open'
           END;
  IF v_new IS DISTINCT FROM v_state THEN
    UPDATE public.orders SET invoice_state = v_new WHERE order_id = p_order_id;
  END IF;
  RETURN v_new;
END; $$;

-- ── 4. invoice_ar_balances: tax-aware total ───────────────────────────────────
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
WHERE o.posted AND o.invoice_state IS NOT NULL;
GRANT SELECT ON public.invoice_ar_balances TO authenticated;

-- ── 5. create_credit_memo: atomic allocate-number + insert (gap-free) ─────────
-- Mirrors finalize_invoice: the number is allocated in the SAME tx as the insert,
-- so a rejected insert (guard trigger) rolls back the sequence bump.
CREATE OR REPLACE FUNCTION public.create_credit_memo(
  p_company_id text, p_customer_id text, p_amount_cents bigint,
  p_applied_to_order_id text, p_reason text, p_created_by text
) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_seq bigint; v_num text; v_cm_id text;
BEGIN
  IF p_company_id NOT IN (SELECT auth_company_ids()) THEN
    RAISE EXCEPTION 'not authorized for company %', p_company_id;
  END IF;
  IF COALESCE(p_amount_cents,0) <= 0 THEN RAISE EXCEPTION 'amount must be positive'; END IF;

  SELECT a.credit_memo_sequence, a.credit_memo_number INTO v_seq, v_num
    FROM public.allocate_credit_memo_number(p_company_id) a;

  v_cm_id := gen_random_uuid()::text;
  INSERT INTO public.credit_memos
    (credit_memo_id, company_id, customer_id, credit_memo_number, credit_memo_sequence,
     amount_cents, applied_to_order_id, reason, created_by)
  VALUES
    (v_cm_id, p_company_id, p_customer_id, v_num, v_seq,
     p_amount_cents, NULLIF(p_applied_to_order_id,''), p_reason, p_created_by);

  RETURN jsonb_build_object('ok', true, 'credit_memo_number', v_num, 'credit_memo_id', v_cm_id);
END; $$;

REVOKE ALL ON FUNCTION public.create_credit_memo(text,text,bigint,text,text,text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.create_credit_memo(text,text,bigint,text,text,text) TO authenticated;

NOTIFY pgrst, 'reload schema';
