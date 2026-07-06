-- Invoice-of-record P3 (part 2): the atomic cutover.
-- One transaction: insert the line-less opening-balance orders, reconcile the
-- WRITTEN rows (not the parsed file) against the operator's control total, then
-- flip invoice_of_record='strata' + seed the numbering LAST. Any mismatch RAISEs
-- and rolls the whole thing back — you cannot half-cut-over. Do NOT route opening
-- orders through the chunked client-driven import pipeline (it can't share a tx).
-- Plan: memory/project_invoice_of_record.md (P3).

CREATE OR REPLACE FUNCTION public.commit_cutover(
  p_company_id          text,
  p_cutover_date        date,
  p_next_seq            bigint,
  p_prefix              text,
  p_pad                 integer,
  p_credit_memo_prefix  text,
  p_control_total_cents bigint,
  p_open_rows           jsonb   -- [{customer_id, facility_id, invoice_number, order_total, order_date, due_date}]
) RETURNS jsonb
  LANGUAGE plpgsql
AS $$
DECLARE
  r               jsonb;
  v_oid           text;
  v_count         integer := 0;
  v_written_cents bigint  := 0;
  v_mode          text;
BEGIN
  -- Tenant guard (belt; RLS WITH CHECK also enforces it on the INSERTs).
  IF p_company_id NOT IN (SELECT auth_company_ids()) THEN
    RAISE EXCEPTION 'not authorized for company %', p_company_id;
  END IF;

  -- Refuse to cut over twice — an already-STRATA company must not re-run this
  -- (it would double-count opening balances and reseed the live counter).
  SELECT invoice_of_record INTO v_mode FROM public.billing_settings WHERE company_id = p_company_id;
  IF v_mode = 'strata' THEN
    RAISE EXCEPTION 'company % has already cut over to STRATA billing', p_company_id;
  END IF;

  -- Insert the opening-balance orders. is_opening_balance=true makes
  -- update_order_metrics preserve the app-set order_total (no line-less $0 clobber)
  -- and keeps them out of customer cadence. posted=true + invoice_state='open' +
  -- is_legacy_import=false => a LIVE receivable that P4 can collect against.
  FOR r IN SELECT jsonb_array_elements(COALESCE(p_open_rows, '[]'::jsonb))
  LOOP
    v_oid := gen_random_uuid()::text;
    INSERT INTO public.orders (
      order_id, company_id, facility_id, customer_id, order_date, order_status,
      order_total, invoice_number, invoice_sequence, invoice_state, due_date,
      posted, is_legacy_import, is_opening_balance, qb_sync_status, order_notes
    ) VALUES (
      v_oid, p_company_id, (r->>'facility_id'), (r->>'customer_id'),
      COALESCE((r->>'order_date')::date, p_cutover_date), 'Delivered',
      (r->>'order_total')::numeric, NULLIF(r->>'invoice_number',''), NULL, 'open',
      (r->>'due_date')::date, true, false, true, 'skip',
      'Opening balance at cutover (QB #' || COALESCE(r->>'invoice_number','?') || ')'
    );
    v_count := v_count + 1;
  END LOOP;

  -- Reconcile the WRITTEN rows to the control total (the safety net against the
  -- trigger-clobber blocker — we reconcile the DB, not the CSV).
  SELECT COALESCE(SUM(round(order_total * 100)), 0) INTO v_written_cents
    FROM public.orders
   WHERE company_id = p_company_id AND is_opening_balance = true;

  IF p_control_total_cents IS NOT NULL AND v_written_cents <> p_control_total_cents THEN
    RAISE EXCEPTION 'cutover reconcile mismatch: opening balances total % cents, control total is % cents',
      v_written_cents, p_control_total_cents;
  END IF;

  -- Flip the flag + seed numbering LAST (so a mid-flight failure never leaves a
  -- Mode-A company with un-reconciled opens).
  INSERT INTO public.billing_settings
    (company_id, invoice_of_record, invoice_prefix, invoice_pad_width, invoice_next_seq, credit_memo_prefix, cutover_date)
  VALUES
    (p_company_id, 'strata', p_prefix, COALESCE(p_pad, 6), GREATEST(COALESCE(p_next_seq, 1), 1), p_credit_memo_prefix, p_cutover_date)
  ON CONFLICT (company_id) DO UPDATE SET
    invoice_of_record  = 'strata',
    invoice_prefix     = EXCLUDED.invoice_prefix,
    invoice_pad_width  = EXCLUDED.invoice_pad_width,
    invoice_next_seq   = EXCLUDED.invoice_next_seq,
    credit_memo_prefix = EXCLUDED.credit_memo_prefix,
    cutover_date       = EXCLUDED.cutover_date,
    updated_at         = now();

  RETURN jsonb_build_object(
    'ok', true,
    'opening_orders', v_count,
    'opening_total_cents', v_written_cents,
    'next_seq', GREATEST(COALESCE(p_next_seq, 1), 1)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.commit_cutover(text, date, bigint, text, integer, text, bigint, jsonb) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.commit_cutover(text, date, bigint, text, integer, text, bigint, jsonb) TO authenticated;

NOTIFY pgrst, 'reload schema';
