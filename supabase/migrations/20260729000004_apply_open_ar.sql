-- Open-A/R import: make STRATA agree with QuickBooks, to the cent, about who owes
-- what — and make the step runnable at any time, in any order, as often as needed.
--
-- ══ WHY THE OLD PATH COULD NOT BE USED ══════════════════════════════════════
-- The wizard already parses an `open_balance` column, but the A/R path only fires on
-- a first-ever import where the sales report and the aging report are uploaded in the
-- SAME session, because the orders phase is INSERT-ONLY (it skips any invoice number
-- already present). And for the invoices it does treat as A/R it throws the LINE
-- ITEMS AWAY and overwrites order_total with the open balance. So:
--   · a roaster who imported history last week has no route in at all
--   · and an unpaid invoice loses its products, unlike every paid one
-- That is backend-migration scaffolding, not a feature.
--
-- ══ THE MODEL ═══════════════════════════════════════════════════════════════
-- One invoice = one row, keeping its real line items, forever. Whether it is PAID is
-- a separate fact, settable at any time.
--
--   is_legacy_import   HOW IT ARRIVED. Amounts came from QuickBooks: do not recompute
--                      them, and do not let its lines deplete consumable stock
--                      (stock counts start at cutover). Says NOTHING about money owed.
--   posted +
--   invoice_state      IS MONEY OWED. The only thing A/R reads.
--   is_opening_balance A line-less stub. Used ONLY for an invoice that is not already
--                      here, where a total is genuinely all we have.
--
-- Dropping orders_open_not_legacy_chk is what unlocks this. That constraint said "an
-- open invoice is a live STRATA receivable, never archived legacy history" — i.e. it
-- assumed that if money is owed, STRATA must have issued the invoice itself, so
-- "imported" and "still unpaid" could never both be true. That is simply wrong: an
-- imported invoice being unpaid is the entire reason to import A/R. It is NOT VALID,
-- so there is nothing to backfill.
--
-- ══ ACCURACY IS THE POINT ═══════════════════════════════════════════════════
-- A roaster acting on this chases real people for real money, so the function returns
-- a full reconciliation and never silently absorbs a row it could not handle:
--   · every file row lands in exactly one bucket (promoted / created / already-live /
--     skipped-*), and the buckets sum back to the file
--   · `unaccounted_open_cents` is the gap between what the file says is owed and what
--     STRATA will show. The UI must refuse to look successful while it is non-zero.
--   · p_dry_run defaults TRUE, so the caller must ask explicitly to write.
--
-- Where QuickBooks says a $500 invoice has $200 open, STRATA ends up holding the
-- $500 invoice WITH ITS LINES plus a $300 'adjustment' payment dated to the invoice.
-- The balance matches QB exactly, the products survive, and the ledger explains where
-- the $300 went instead of the total being quietly rewritten.

begin;

-- ── The constraint that made this impossible ────────────────────────────────
alter table public.orders drop constraint if exists orders_open_not_legacy_chk;

comment on column public.orders.is_legacy_import is
  'Provenance: this row came from an import, so its amounts are authoritative (never recomputed from the price list) and its lines do not deplete consumable stock. Says NOTHING about whether money is owed — that is posted + invoice_state. An imported invoice can be open.';

-- ── apply_open_ar ───────────────────────────────────────────────────────────
create or replace function public.apply_open_ar(
  p_company_id       text,
  p_rows             jsonb,                 -- see ROW SHAPE below
  p_include_in_aging boolean default true,
  p_dry_run          boolean default true
) returns jsonb
language plpgsql
as $$
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
    'unaccounted_open_cents', c_file - (c_promoted + c_created + c_live),
    'reconciles',             (c_file - (c_promoted + c_created + c_live)) = 0
  );
END;
$$;

comment on function public.apply_open_ar(text, jsonb, boolean, boolean) is
  'Set payment status on invoices from a QuickBooks A/R aging / open-invoices file. Matches by document number: found → promote in place keeping line items, recording the already-collected portion as an adjustment payment; missing → create a line-less opening-balance invoice. Idempotent (already-live invoices are skipped), and returns a full reconciliation whose unaccounted_open_cents must be zero. p_dry_run defaults TRUE.';

revoke all on function public.apply_open_ar(text, jsonb, boolean, boolean) from public, anon;
grant execute on function public.apply_open_ar(text, jsonb, boolean, boolean) to authenticated;

commit;

notify pgrst, 'reload schema';
