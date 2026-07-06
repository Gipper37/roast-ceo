-- Invoice-of-record P4: the A/R ledger. Manual payments, allocations, credit
-- memos — all INTEGER CENTS, SEPARATE from PayFac (payment_transactions = card
-- math; statements = card payouts — neither touched here). Plus the derived
-- invoice_state recompute + a tenant-safe balances view. Every money surface is
-- gated at the DB: Mode A required, same-customer + posted-STRATA-invoice
-- enforced (RLS blocks cross-COMPANY but not cross-CUSTOMER within a tenant).
-- Plan: memory/project_invoice_of_record.md (P4).

-- Refuse to apply on a P2-less schema (finalize/guards + allocate_credit_memo_number
-- are prerequisites). Belt for the prod release ordering.
DO $$ BEGIN
  IF to_regprocedure('public.finalize_invoice(text)') IS NULL
     OR to_regprocedure('public.allocate_credit_memo_number(text)') IS NULL THEN
    RAISE EXCEPTION 'P2 invoice-of-record backend must be applied before the P4 A/R ledger';
  END IF;
END $$;

-- ── invoice_payments — money received (check/ach/cash/wire/card/adjustment) ────
CREATE TABLE IF NOT EXISTS public.invoice_payments (
  payment_id             text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  company_id             text NOT NULL REFERENCES public.companies(company_id) ON DELETE CASCADE,
  customer_id            text REFERENCES public.customers(customer_id) ON DELETE SET NULL,
  method                 text NOT NULL CHECK (method IN ('check','ach','cash','wire','card','adjustment')),
  amount_cents           bigint NOT NULL CHECK (amount_cents > 0),
  received_date          date NOT NULL DEFAULT current_date,
  payment_transaction_id uuid REFERENCES public.payment_transactions(payment_transaction_id) ON DELETE SET NULL,
  qb_payment_id          text,
  memo                   text,
  voided_at              timestamptz,
  created_by             text,
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS invoice_payments_company_customer_idx
  ON public.invoice_payments (company_id, customer_id, received_date DESC);
ALTER TABLE public.invoice_payments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_company_access ON public.invoice_payments;
CREATE POLICY tenant_company_access ON public.invoice_payments FOR ALL TO authenticated
  USING (company_id IN (SELECT auth_company_ids())) WITH CHECK (company_id IN (SELECT auth_company_ids()));

-- ── invoice_payment_allocations — payment↔invoice (splits / unapplied credit) ──
CREATE TABLE IF NOT EXISTS public.invoice_payment_allocations (
  allocation_id text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  company_id    text NOT NULL REFERENCES public.companies(company_id) ON DELETE CASCADE,
  payment_id    text NOT NULL REFERENCES public.invoice_payments(payment_id) ON DELETE CASCADE,
  order_id      text NOT NULL REFERENCES public.orders(order_id) ON DELETE CASCADE,
  amount_cents  bigint NOT NULL CHECK (amount_cents > 0),
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (payment_id, order_id)
);
CREATE INDEX IF NOT EXISTS ipa_order_idx   ON public.invoice_payment_allocations (order_id);
CREATE INDEX IF NOT EXISTS ipa_payment_idx ON public.invoice_payment_allocations (payment_id);
ALTER TABLE public.invoice_payment_allocations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_company_access ON public.invoice_payment_allocations;
CREATE POLICY tenant_company_access ON public.invoice_payment_allocations FOR ALL TO authenticated
  USING (company_id IN (SELECT auth_company_ids())) WITH CHECK (company_id IN (SELECT auth_company_ids()));

-- ── credit_memos — first-class negative doc (own number; UNIQUE per company) ───
CREATE TABLE IF NOT EXISTS public.credit_memos (
  credit_memo_id       text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  company_id           text NOT NULL REFERENCES public.companies(company_id) ON DELETE CASCADE,
  customer_id          text REFERENCES public.customers(customer_id) ON DELETE SET NULL,
  credit_memo_number   text NOT NULL,
  credit_memo_sequence bigint,
  amount_cents         bigint NOT NULL CHECK (amount_cents > 0),
  applied_to_order_id  text REFERENCES public.orders(order_id) ON DELETE SET NULL,
  reason               text,
  voided_at            timestamptz,
  created_by           text,
  created_at           timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, credit_memo_number)   -- reviewer MEDIUM: CM dedup backstop
);
CREATE INDEX IF NOT EXISTS credit_memos_company_customer_idx ON public.credit_memos (company_id, customer_id);
CREATE INDEX IF NOT EXISTS credit_memos_applied_order_idx ON public.credit_memos (applied_to_order_id) WHERE applied_to_order_id IS NOT NULL;
ALTER TABLE public.credit_memos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_company_access ON public.credit_memos;
CREATE POLICY tenant_company_access ON public.credit_memos FOR ALL TO authenticated
  USING (company_id IN (SELECT auth_company_ids())) WITH CHECK (company_id IN (SELECT auth_company_ids()));

-- ── Guard: A/R rows only exist for Mode-A companies (missing row => reject) ────
CREATE OR REPLACE FUNCTION public.guard_ar_row_strata_mode() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_mode text;
BEGIN
  SELECT invoice_of_record INTO v_mode FROM public.billing_settings WHERE company_id = NEW.company_id;
  IF COALESCE(v_mode,'quickbooks') <> 'strata' THEN
    RAISE EXCEPTION 'company % is not in STRATA billing mode — cannot create A/R rows', NEW.company_id;
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_guard_payment_mode ON public.invoice_payments;
CREATE TRIGGER trg_guard_payment_mode BEFORE INSERT ON public.invoice_payments
  FOR EACH ROW EXECUTE FUNCTION public.guard_ar_row_strata_mode();

-- ── Guard: allocation ≤ payment, same customer, posted STRATA invoice, Mode A ──
CREATE OR REPLACE FUNCTION public.guard_allocation_not_overapplied() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_pay bigint; v_alloc bigint; v_ord_cust text; v_pay_cust text; v_posted boolean; v_state text; v_mode text;
BEGIN
  SELECT amount_cents, customer_id INTO v_pay, v_pay_cust FROM public.invoice_payments
   WHERE payment_id = NEW.payment_id AND voided_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'payment % missing or voided', NEW.payment_id; END IF;

  SELECT o.customer_id, o.posted, o.invoice_state INTO v_ord_cust, v_posted, v_state
    FROM public.orders o WHERE o.order_id = NEW.order_id;
  IF NOT COALESCE(v_posted,false) OR v_state IS NULL OR v_state IN ('void','draft') THEN
    RAISE EXCEPTION 'order % is not a posted STRATA invoice', NEW.order_id;
  END IF;
  IF v_pay_cust IS NOT NULL AND v_ord_cust IS DISTINCT FROM v_pay_cust THEN
    RAISE EXCEPTION 'allocation customer mismatch (order % belongs to a different customer)', NEW.order_id;
  END IF;

  SELECT invoice_of_record INTO v_mode FROM public.billing_settings WHERE company_id = NEW.company_id;
  IF COALESCE(v_mode,'quickbooks') <> 'strata' THEN
    RAISE EXCEPTION 'company % is not in STRATA billing mode', NEW.company_id;
  END IF;

  SELECT COALESCE(SUM(amount_cents),0) INTO v_alloc FROM public.invoice_payment_allocations
   WHERE payment_id = NEW.payment_id AND allocation_id IS DISTINCT FROM NEW.allocation_id;
  IF v_alloc + NEW.amount_cents > v_pay THEN
    RAISE EXCEPTION 'allocations (%) exceed payment (%)', v_alloc + NEW.amount_cents, v_pay;
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_guard_allocation ON public.invoice_payment_allocations;
CREATE TRIGGER trg_guard_allocation BEFORE INSERT OR UPDATE ON public.invoice_payment_allocations
  FOR EACH ROW EXECUTE FUNCTION public.guard_allocation_not_overapplied();

-- ── Guard: credit memo same-customer + posted STRATA target + Mode A ──────────
CREATE OR REPLACE FUNCTION public.guard_credit_memo_valid() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_ord_cust text; v_posted boolean; v_state text; v_mode text;
BEGIN
  SELECT invoice_of_record INTO v_mode FROM public.billing_settings WHERE company_id = NEW.company_id;
  IF COALESCE(v_mode,'quickbooks') <> 'strata' THEN
    RAISE EXCEPTION 'company % is not in STRATA billing mode', NEW.company_id;
  END IF;
  IF NEW.applied_to_order_id IS NOT NULL THEN
    SELECT o.customer_id, o.posted, o.invoice_state INTO v_ord_cust, v_posted, v_state
      FROM public.orders o WHERE o.order_id = NEW.applied_to_order_id;
    IF NOT COALESCE(v_posted,false) OR v_state IS NULL OR v_state IN ('void','draft') THEN
      RAISE EXCEPTION 'credit memo target order % is not a posted STRATA invoice', NEW.applied_to_order_id;
    END IF;
    IF NEW.customer_id IS NOT NULL AND v_ord_cust IS DISTINCT FROM NEW.customer_id THEN
      RAISE EXCEPTION 'credit memo customer mismatch on order %', NEW.applied_to_order_id;
    END IF;
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_guard_credit_memo ON public.credit_memos;
CREATE TRIGGER trg_guard_credit_memo BEFORE INSERT OR UPDATE ON public.credit_memos
  FOR EACH ROW EXECUTE FUNCTION public.guard_credit_memo_valid();

-- ── Derived state: recompute invoice_state from payments + credits ────────────
-- Only writes invoice_state (left editable by the P2 post-lock guard — verified).
-- paid >= total => paid; 0<paid<total => partial; past due & unpaid => overdue.
CREATE OR REPLACE FUNCTION public.recompute_invoice_ar_state(p_order_id text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_total bigint; v_paid bigint; v_state text; v_due date; v_posted boolean; v_new text;
BEGIN
  SELECT round(COALESCE(order_total,0)*100)::bigint, invoice_state, due_date, posted
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

-- Nightly sweep: flip open->overdue past due (wire into /api/cron per Mode-A company).
CREATE OR REPLACE FUNCTION public.recompute_overdue_invoices(p_company_id text) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE v_n integer;
BEGIN
  UPDATE public.orders o SET invoice_state='overdue'
   WHERE o.company_id=p_company_id AND o.invoice_state='open'
     AND o.due_date IS NOT NULL AND o.due_date < current_date;
  GET DIAGNOSTICS v_n = ROW_COUNT; RETURN v_n;
END; $$;

-- ── Balances view — MUST be security_invoker (PG17 defaults FALSE => leak) ─────
CREATE OR REPLACE VIEW public.invoice_ar_balances WITH (security_invoker = true) AS
SELECT o.company_id, o.order_id, o.customer_id, o.invoice_number, o.invoice_state, o.due_date,
       round(COALESCE(o.order_total,0)*100)::bigint AS total_cents,
       COALESCE(pa.paid_cents,0) + COALESCE(cm.credit_cents,0) AS paid_cents,
       GREATEST(round(COALESCE(o.order_total,0)*100)::bigint
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

-- ── Grants (authenticated only; never anon) ───────────────────────────────────
REVOKE ALL ON FUNCTION public.recompute_invoice_ar_state(text)  FROM public, anon;
REVOKE ALL ON FUNCTION public.recompute_overdue_invoices(text)  FROM public, anon;
GRANT EXECUTE ON FUNCTION public.recompute_invoice_ar_state(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.recompute_overdue_invoices(text) TO authenticated;
GRANT SELECT ON public.invoice_ar_balances TO authenticated;

NOTIFY pgrst, 'reload schema';
