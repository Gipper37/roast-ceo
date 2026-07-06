-- Invoice-of-record PHASE 2 — basic invoicing (Mode A) backend.
-- Adds the numbering keystone (gap-free per-company invoice + credit-memo
-- counters), the finalize transition (order -> issued invoice), and post-and-lock
-- immutability. All DORMANT for existing tenants: every function requires a
-- billing_settings row with invoice_of_record='strata' (Mode A), and no company
-- has one until it opts in via the cutover flow. Mode B (default / no row) is
-- untouched. Plan: memory/project_invoice_of_record.md.
--
-- SAFETY — post-and-lock vs the trigger chain (the P2 risk in the plan):
--   * update_order_metrics (BEFORE UPDATE on orders) ALWAYS recomputes
--     order_total/total_weight from SUM(order_details) — so those are DERIVED,
--     not independently settable. The guard therefore does NOT protect them
--     (they'd false-trip on any benign fulfillment update); it locks the LINES
--     (order_details) and the truly-independent document fields instead.
--   * handle_order_detail_logic (BEFORE on order_details) only rewrites
--     total_price/unit_cost_at_sale when quantity/product_id change — so a
--     fulfillment-only change (item_status) never mutates money. Fulfillment
--     (order_status/item_status), COGS recompute, and the AR lifecycle
--     (invoice_state, paid/void/write-off stamps) all stay editable on a
--     posted invoice; only qty/product/price/customer/date/tax/bill-to lock.

-- ── Numbering keystone ────────────────────────────────────────────────────────
-- Generalizes allocate_shop_order_ref()/shop_order_ref_counter (gap-free
-- ON CONFLICT row-lock) onto billing_settings.invoice_next_seq. The single
-- UPDATE ... RETURNING takes the row lock so concurrent callers serialize; a
-- RAISE after the bump aborts the (sub)transaction, so no sequence is consumed
-- on the error paths (no gaps). SECURITY INVOKER so RLS scopes each caller to
-- their own company (cross-tenant callers see no row -> NOT FOUND -> raise).
CREATE OR REPLACE FUNCTION public.allocate_invoice_number(p_company_id text)
  RETURNS TABLE(invoice_sequence bigint, invoice_number text)
  LANGUAGE plpgsql AS $$
DECLARE
  v_seq    bigint;
  v_prefix text;
  v_pad    integer;
  v_mode   text;
BEGIN
  UPDATE public.billing_settings
     SET invoice_next_seq = invoice_next_seq + 1,
         updated_at       = now()
   WHERE company_id = p_company_id
  RETURNING invoice_next_seq - 1, invoice_prefix, invoice_pad_width, invoice_of_record
       INTO v_seq, v_prefix, v_pad, v_mode;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'billing_settings row missing for company % — configure invoice-of-record before invoicing', p_company_id;
  END IF;
  IF v_mode <> 'strata' THEN
    RAISE EXCEPTION 'company % is Mode B (invoice_of_record=%) — QuickBooks is the biller, no STRATA number allocated', p_company_id, v_mode;
  END IF;

  invoice_sequence := v_seq;
  invoice_number   := COALESCE(v_prefix, '') || lpad(v_seq::text, COALESCE(v_pad, 6), '0');
  RETURN NEXT;
END;
$$;

-- Credit memos get their OWN sequence (jurisdiction-compliant separation).
CREATE OR REPLACE FUNCTION public.allocate_credit_memo_number(p_company_id text)
  RETURNS TABLE(credit_memo_sequence bigint, credit_memo_number text)
  LANGUAGE plpgsql AS $$
DECLARE
  v_seq    bigint;
  v_prefix text;
  v_pad    integer;
  v_mode   text;
BEGIN
  UPDATE public.billing_settings
     SET credit_memo_next_seq = credit_memo_next_seq + 1,
         updated_at           = now()
   WHERE company_id = p_company_id
  RETURNING credit_memo_next_seq - 1, credit_memo_prefix, invoice_pad_width, invoice_of_record
       INTO v_seq, v_prefix, v_pad, v_mode;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'billing_settings row missing for company %', p_company_id;
  END IF;
  IF v_mode <> 'strata' THEN
    RAISE EXCEPTION 'company % is Mode B — no STRATA credit-memo number allocated', p_company_id;
  END IF;

  credit_memo_sequence := v_seq;
  credit_memo_number   := COALESCE(v_prefix, 'CM-') || lpad(v_seq::text, COALESCE(v_pad, 6), '0');
  RETURN NEXT;
END;
$$;

-- ── Finalize: order -> issued invoice ─────────────────────────────────────────
-- Atomic: allocate the number, snapshot the terms/due date, flip invoice_state
-- to 'open' and post (lock). Idempotent — re-calling a finalized order returns
-- its existing number WITHOUT consuming a new one. Legacy QB-imported orders are
-- never numbered (they keep the original QB Num as reference). RLS-scoped: an
-- order the caller can't see returns NOT FOUND.
CREATE OR REPLACE FUNCTION public.finalize_invoice(p_order_id text)
  RETURNS text
  LANGUAGE plpgsql AS $$
DECLARE
  v_company_id text;
  v_customer   text;
  v_order_date date;
  v_existing   text;
  v_legacy     boolean;
  v_terms      text;
  v_days       integer;
  v_num        text;
  v_seq        bigint;
BEGIN
  SELECT company_id, customer_id, order_date, invoice_number, is_legacy_import
    INTO v_company_id, v_customer, v_order_date, v_existing, v_legacy
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
    RAISE EXCEPTION 'order % is a legacy import — it keeps its original QB number and is not finalized as a STRATA invoice', p_order_id;
  END IF;

  -- Terms -> due date. payment_terms: card|net_15|net_30|net_60 (else due on receipt).
  SELECT payment_terms INTO v_terms
    FROM public.customers WHERE customer_id = v_customer;
  v_days := CASE v_terms
              WHEN 'net_15' THEN 15
              WHEN 'net_30' THEN 30
              WHEN 'net_60' THEN 60
              ELSE 0
            END;

  SELECT a.invoice_sequence, a.invoice_number
    INTO v_seq, v_num
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

-- ── Post-and-lock guards ──────────────────────────────────────────────────────
-- orders: block DELETE of a posted invoice, and block edits to the independent
-- document fields (customer/date/tax/discount/invoice#/bill-to). order_total and
-- total_weight are intentionally NOT checked — update_order_metrics rederives them
-- from the (locked) lines on every update, so guarding them would false-trip.
CREATE OR REPLACE FUNCTION public.guard_posted_order_immutable()
  RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.posted THEN
      RAISE EXCEPTION 'order % is a posted invoice and cannot be deleted — void it instead', OLD.order_id;
    END IF;
    RETURN OLD;
  END IF;

  IF OLD.posted THEN
    IF (NEW.customer_id      IS DISTINCT FROM OLD.customer_id)
    OR (NEW.order_date       IS DISTINCT FROM OLD.order_date)
    OR (NEW.tax_amount       IS DISTINCT FROM OLD.tax_amount)
    OR (NEW.tax_rate         IS DISTINCT FROM OLD.tax_rate)
    OR (NEW.discount_total   IS DISTINCT FROM OLD.discount_total)
    OR (NEW.invoice_number   IS DISTINCT FROM OLD.invoice_number)
    OR (NEW.invoice_sequence IS DISTINCT FROM OLD.invoice_sequence)
    OR (NEW.bill_to_name     IS DISTINCT FROM OLD.bill_to_name)
    OR (NEW.bill_to_address  IS DISTINCT FROM OLD.bill_to_address)
    OR (NEW.bill_to_address_2 IS DISTINCT FROM OLD.bill_to_address_2)
    OR (NEW.bill_to_city     IS DISTINCT FROM OLD.bill_to_city)
    OR (NEW.bill_to_state    IS DISTINCT FROM OLD.bill_to_state)
    OR (NEW.bill_to_zip      IS DISTINCT FROM OLD.bill_to_zip)
    OR (NEW.bill_to_country  IS DISTINCT FROM OLD.bill_to_country)
    OR (NEW.bill_to_email    IS DISTINCT FROM OLD.bill_to_email)
    OR (NEW.bill_to_phone    IS DISTINCT FROM OLD.bill_to_phone)
    THEN
      RAISE EXCEPTION 'order % is a posted invoice — its document fields are locked (void-and-reissue or issue a credit memo to change it)', OLD.order_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- order_details: on a posted parent, no add/remove lines and no qty/product/price
-- edits. item_status (fulfillment) and unit_cost_at_sale (COGS recompute) stay open.
CREATE OR REPLACE FUNCTION public.guard_posted_order_detail_immutable()
  RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_posted boolean;
BEGIN
  SELECT posted INTO v_posted FROM public.orders
   WHERE order_id = COALESCE(NEW.order_id, OLD.order_id);

  IF NOT COALESCE(v_posted, false) THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'cannot remove a line from posted invoice % — void or issue a credit memo', OLD.order_id;
  END IF;
  IF TG_OP = 'INSERT' THEN
    RAISE EXCEPTION 'cannot add a line to posted invoice % — void or issue a credit memo', NEW.order_id;
  END IF;
  IF (NEW.quantity    IS DISTINCT FROM OLD.quantity)
  OR (NEW.product_id  IS DISTINCT FROM OLD.product_id)
  OR (NEW.total_price IS DISTINCT FROM OLD.total_price) THEN
    RAISE EXCEPTION 'line on posted invoice % is locked (qty/product/price) — void or issue a credit memo', OLD.order_id;
  END IF;
  RETURN NEW;
END;
$$;

-- Fire the guards LAST in the BEFORE phase (name chosen to sort after the
-- existing trg_* triggers) so they see the final NEW after the metrics/pricing
-- triggers have run.
DROP TRIGGER IF EXISTS zzz_guard_posted_order ON public.orders;
CREATE TRIGGER zzz_guard_posted_order
  BEFORE UPDATE OR DELETE ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.guard_posted_order_immutable();

DROP TRIGGER IF EXISTS zzz_guard_posted_order_detail ON public.order_details;
CREATE TRIGGER zzz_guard_posted_order_detail
  BEFORE INSERT OR UPDATE OR DELETE ON public.order_details
  FOR EACH ROW EXECUTE FUNCTION public.guard_posted_order_detail_immutable();

-- Backstop: the sequence integer is unique per company too, not just the
-- formatted number. Guards against a future prefix/pad-width edit letting two
-- orders share a sequence while their number strings differ (the number-string
-- unique index alone wouldn't catch that). Allocation is already serialized;
-- this is belt-and-suspenders.
CREATE UNIQUE INDEX IF NOT EXISTS orders_company_invoice_sequence_uidx
  ON public.orders (company_id, invoice_sequence)
  WHERE invoice_sequence IS NOT NULL;

-- ── Grants (audit lesson: authenticated only, never anon) ──────────────────────
REVOKE ALL ON FUNCTION public.allocate_invoice_number(text)     FROM public, anon;
REVOKE ALL ON FUNCTION public.allocate_credit_memo_number(text) FROM public, anon;
REVOKE ALL ON FUNCTION public.finalize_invoice(text)            FROM public, anon;
GRANT EXECUTE ON FUNCTION public.allocate_invoice_number(text)     TO authenticated;
GRANT EXECUTE ON FUNCTION public.allocate_credit_memo_number(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_invoice(text)            TO authenticated;

NOTIFY pgrst, 'reload schema';
