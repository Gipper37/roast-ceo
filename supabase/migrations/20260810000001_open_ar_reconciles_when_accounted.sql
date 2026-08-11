-- apply_open_ar: an explained skip is accounted for, and must not block the import.
--
-- THE DEAD END. `reconciles` was
--
--     c_file - (promoted + created + live) = 0
--
-- and the commit button is disabled unless it is true. But the function also
-- skips rows on purpose — an invoice whose file balance exceeds its STRATA
-- total, or one whose customer cannot be matched — and neither skip appeared in
-- that sum. So a deliberate, reported, named skip read as an unexplained
-- difference and refused the entire import.
--
-- MCR hit it at full force: 202 invoices skipped for exceeding their invoice
-- total, and the button read "Resolve the difference to continue" with nothing
-- on screen able to resolve it. $116,543.97 of real receivable held behind
-- $741 of missing tax — the whole invoice dropped for being a few dollars over,
-- 197 times.
--
-- WHY THEY WERE OVER AT ALL. Sales by Item Detail cannot carry tax, so every
-- imported invoice was short by it while the aging file's open balance included
-- it. That is fixed at source by importing the Custom Transaction Detail report,
-- whose Accounts Receivable line is the total INCLUDING tax. This is the other
-- half: even once rare, an explained skip must never wedge the run.
--
-- WHAT DOES NOT CHANGE. The skips still happen and are still reported by
-- reference. Money is never invented and a mis-mapped column still cannot
-- inflate A/R. Only the definition of "reconciled" moves: knowing exactly which
-- rows these are and why IS being accounted for, which is what the word means.
-- unaccounted_open_cents keeps its old meaning — genuinely unexplained — so a
-- non-zero value is now a real discrepancy rather than a tally of things the
-- tool already told you about.
--
-- Body below is the deployed definition verbatim; only the two expressions at
-- the end differ.

begin;

CREATE OR REPLACE FUNCTION public.apply_open_ar(p_company_id text, p_rows jsonb, p_include_in_aging boolean DEFAULT true, p_dry_run boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
-- ROW SHAPE (the caller resolves customer names to ids before calling):
--   { "ref": "104534",                 -- QB document / invoice number  (required)
--     "customer_id": "cust-…",         -- required only to CREATE a missing invoice
--     "open_balance_cents": 20000,     -- what QB says is still owed    (required, >0)
--     "invoice_date": "2026-07-15",    -- used when creating
--     "due_date":     "2026-08-15",
--     "terms":        "net_30" }
DECLARE
  r  jsonb;
  v_mode          text;
  v_facility      text;
  v_order         record;
  v_ref           text;
  v_cust          text;
  v_bal           bigint;
  v_total         bigint;
  v_prepaid       bigint;
  v_pay_id        text;
  v_new_id        text;
  v_terms         text;
  v_due           date;
  v_inv_date      date;
  -- counters
  n_rows        integer := 0;
  n_promoted    integer := 0;
  n_created     integer := 0;
  n_live        integer := 0;
  n_over        integer := 0;
  n_nocust      integer := 0;
  n_zero        integer := 0;
  c_file        bigint  := 0;
  c_promoted    bigint  := 0;
  c_created     bigint  := 0;
  c_live        bigint  := 0;
  c_over        bigint  := 0;
  c_nocust      bigint  := 0;
  refs_over     text[] := '{}';
  refs_nocust   text[] := '{}';
BEGIN
  IF p_company_id NOT IN (SELECT auth_company_ids()) THEN
    RAISE EXCEPTION 'not authorized for company %', p_company_id;
  END IF;

  SELECT invoice_of_record INTO v_mode FROM public.billing_settings WHERE company_id = p_company_id;
  IF COALESCE(v_mode, 'quickbooks') <> 'strata' THEN
    RAISE EXCEPTION 'company % is not on STRATA invoicing — switch the book of record first', p_company_id;
  END IF;

  SELECT facility_id INTO v_facility FROM public.facilities
   WHERE company_id = p_company_id ORDER BY facility_id LIMIT 1;

  FOR r IN SELECT * FROM jsonb_array_elements(COALESCE(p_rows, '[]'::jsonb)) LOOP
    n_rows := n_rows + 1;
    v_ref  := btrim(COALESCE(r->>'ref', ''));
    v_bal  := COALESCE((r->>'open_balance_cents')::bigint, 0);

    -- A row with no document number or nothing owed is not a receivable. Counted so
    -- the file still reconciles rather than the row vanishing.
    IF v_ref = '' OR v_bal <= 0 THEN
      n_zero := n_zero + 1;
      CONTINUE;
    END IF;
    c_file := c_file + v_bal;

    v_cust     := NULLIF(btrim(COALESCE(r->>'customer_id', '')), '');
    v_terms    := NULLIF(btrim(COALESCE(r->>'terms', '')), '');
    IF v_terms IS NOT NULL AND v_terms NOT IN ('card','net_15','net_30','net_60','cod') THEN
      v_terms := NULL;                     -- unrecognised terms are dropped, not stored
    END IF;
    v_due      := CASE WHEN COALESCE(r->>'due_date','')     ~ '^\d{4}-\d{2}-\d{2}$' THEN (r->>'due_date')::date     ELSE NULL END;
    v_inv_date := CASE WHEN COALESCE(r->>'invoice_date','') ~ '^\d{4}-\d{2}-\d{2}$' THEN (r->>'invoice_date')::date ELSE NULL END;

    -- Match the invoice already in STRATA. QB document number first, then invoice
    -- number; both are unique per company, never globally.
    SELECT o.order_id, o.posted, o.invoice_state, o.order_date, o.customer_id,
           round((COALESCE(o.order_total,0) + COALESCE(o.tax_amount,0)) * 100)::bigint AS total_cents
      INTO v_order
      FROM public.orders o
     WHERE o.company_id = p_company_id
       AND (o.qb_txn_id = v_ref OR o.invoice_number = v_ref)
     ORDER BY (o.qb_txn_id = v_ref) DESC
     LIMIT 1;

    -- ══ NOT HERE → create a line-less stub ══════════════════════════════════
    -- The only honest use of is_opening_balance: an aging row carries a total and no
    -- lines, so that is all the invoice can contain.
    IF NOT FOUND THEN
      IF v_cust IS NULL THEN
        n_nocust := n_nocust + 1;
        c_nocust := c_nocust + v_bal;
        IF COALESCE(array_length(refs_nocust,1),0) < 50 THEN refs_nocust := refs_nocust || v_ref; END IF;
        CONTINUE;
      END IF;

      n_created := n_created + 1;
      c_created := c_created + v_bal;
      CONTINUE WHEN p_dry_run;

      v_new_id := gen_random_uuid()::text;
      INSERT INTO public.orders (
        order_id, company_id, facility_id, customer_id, order_date, order_status,
        order_total, invoice_number, qb_txn_id, posted, invoice_state, due_date,
        payment_terms, is_opening_balance, is_legacy_import, aging_excluded, order_notes
      ) VALUES (
        v_new_id, p_company_id, v_facility, v_cust,
        COALESCE(v_inv_date, current_date), 'Delivered',
        v_bal / 100.0, v_ref, v_ref, true, 'open', v_due,
        v_terms, true, false, NOT p_include_in_aging,
        'Opening balance imported from QuickBooks — no line detail available.'
      );
      CONTINUE;
    END IF;

    v_total := v_order.total_cents;

    -- ══ ALREADY A LIVE INVOICE → leave it completely alone ══════════════════
    -- Re-running must be safe. Touching it again would re-apply the adjustment below
    -- and double-count money already collected.
    IF COALESCE(v_order.posted, false) AND v_order.invoice_state IS NOT NULL THEN
      n_live := n_live + 1;
      c_live := c_live + v_bal;
      CONTINUE;
    END IF;

    -- ══ FILE CLAIMS MORE OPEN THAN THE INVOICE IS WORTH ════════════════════
    -- Do not guess which side is right — a mis-mapped column must not inflate A/R.
    -- Reported by reference so the operator can look at those invoices.
    IF v_bal > v_total THEN
      n_over := n_over + 1;
      c_over := c_over + v_bal;
      IF COALESCE(array_length(refs_over,1),0) < 50 THEN refs_over := refs_over || v_ref; END IF;
      CONTINUE;
    END IF;

    n_promoted := n_promoted + 1;
    c_promoted := c_promoted + v_bal;
    CONTINUE WHEN p_dry_run;

    -- Promote IN PLACE. Lines, products and amounts are untouched; only the payment
    -- status changes. posted=true also engages guard_posted_order_details_immutable,
    -- which locks those line amounts harder than amount_override does.
    UPDATE public.orders
       SET posted         = true,
           invoice_state  = 'open',
           due_date       = COALESCE(v_due, due_date),
           payment_terms  = COALESCE(v_terms, payment_terms),
           aging_excluded = NOT p_include_in_aging
     WHERE order_id = v_order.order_id;

    -- The already-collected portion, recorded as what it is: money that arrived
    -- before cutover in a system that did not tell us when or how. This is what makes
    -- the STRATA balance equal QuickBooks' without rewriting the invoice total.
    -- Inserted AFTER the promote, because guard_allocation_not_overapplied requires a
    -- posted, collectable invoice before it accepts an allocation.
    v_prepaid := v_total - v_bal;
    IF v_prepaid > 0 THEN
      v_pay_id := gen_random_uuid()::text;
      INSERT INTO public.invoice_payments
        (payment_id, company_id, customer_id, method, amount_cents, received_date, memo)
      VALUES (v_pay_id, p_company_id, v_order.customer_id, 'adjustment', v_prepaid,
              COALESCE(v_order.order_date, current_date),
              'Collected in QuickBooks before cutover');
      INSERT INTO public.invoice_payment_allocations
        (allocation_id, company_id, payment_id, order_id, amount_cents)
      VALUES (gen_random_uuid()::text, p_company_id, v_pay_id, v_order.order_id, v_prepaid);
    END IF;

    PERFORM public.recompute_invoice_ar_state(v_order.order_id);
  END LOOP;

  RETURN jsonb_build_object(
    'dry_run',                p_dry_run,
    'include_in_aging',       p_include_in_aging,
    -- what the file said
    'file_rows',              n_rows,
    'file_open_cents',        c_file,
    'skipped_blank_or_zero',  n_zero,
    -- what STRATA will hold
    'promoted',               n_promoted,
    'promoted_open_cents',    c_promoted,
    'created',                n_created,
    'created_open_cents',     c_created,
    'already_live',           n_live,
    'already_live_open_cents', c_live,
    -- what could NOT be handled — the UI must surface these, not swallow them
    'skipped_over_invoice',   n_over,
    'skipped_over_cents',     c_over,
    'skipped_over_refs',      to_jsonb(refs_over),
    'skipped_no_customer',    n_nocust,
    'skipped_no_customer_cents', c_nocust,
    'skipped_no_customer_refs',  to_jsonb(refs_nocust),
    -- THE reconciliation. Non-zero means STRATA and QuickBooks disagree about how
    -- much is owed, and the operator must not be told the import succeeded.
    'accounted_open_cents',   c_promoted + c_created + c_live,
    -- 🔴 A NAMED SKIP IS ACCOUNTED FOR. c_over and c_nocust are rows the function
    -- deliberately declined and reported BY REFERENCE above. Leaving them out of
    -- this term made a deliberate, explained skip read as an unexplained
    -- difference and refuse the whole import — MCR: 202 invoices, $116,543.97 of
    -- real receivable held behind a button that said "Resolve the difference to
    -- continue" with nothing on screen able to resolve it.
    'unaccounted_open_cents', c_file - (c_promoted + c_created + c_live + c_over + c_nocust),
    'reconciles',             (c_file - (c_promoted + c_created + c_live + c_over + c_nocust)) = 0
  );
END;
$function$;

comment on function public.apply_open_ar(text, jsonb, boolean, boolean) is
  'Imports open A/R. Reconciles when every row is either imported or explicitly reported as skipped — a named skip is accounted for and must not block the run.';

commit;
