-- set_invoice_next_seq: let an admin manually RESET the next invoice number, with
-- duplicate prevention. Needed because commit_cutover (the only other seeder)
-- refuses to re-run on an already-strata company, so there is otherwise no
-- supported way to change the counter after cutover.
--
-- Duplicate prevention is FORMAT-AWARE. Forward numbers are formatted
-- prefix || lpad(seq, pad) (same formula as allocate_invoice_number). Because
-- allocation increments from the seed, a safe seed must sit ABOVE every existing
-- invoice number that shares the forward format — otherwise the 2nd/3rd/... issued
-- invoice would collide and hard-fail on orders_company_invoice_number_uidx.
--
-- We compute the max "tail" of existing invoice_numbers that (a) start with the
-- company's current prefix and (b) are all-digits after the prefix. With an empty
-- prefix (seamless QB continuation) that is the max pure-numeric legacy invoice
-- number; with an 'INV-' prefix it ignores raw legacy numbers entirely. This
-- avoids the poison where stripping non-digits from refs like 'CM2272026' inflated
-- the ceiling and would have rejected a legitimate seed.
--
-- SECURITY INVOKER: RLS scopes the caller to their own company (a cross-tenant
-- caller finds no billing_settings row -> NOT FOUND -> raise), exactly like
-- allocate_invoice_number.

CREATE OR REPLACE FUNCTION public.set_invoice_next_seq(p_company_id text, p_value bigint)
  RETURNS jsonb
  LANGUAGE plpgsql AS $$
DECLARE
  v_prefix     text;
  v_pad        integer;
  v_mode       text;
  v_next       text;
  v_max_series bigint;
BEGIN
  IF p_value IS NULL OR p_value < 1 THEN
    RAISE EXCEPTION 'invoice start number must be a positive whole number';
  END IF;

  -- Row-lock the settings row; RLS scopes us to our own company (INVOKER).
  SELECT invoice_prefix, invoice_pad_width, invoice_of_record
    INTO v_prefix, v_pad, v_mode
    FROM public.billing_settings
   WHERE company_id = p_company_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'billing settings not found — set up invoice-of-record first';
  END IF;
  IF v_mode <> 'strata' THEN
    RAISE EXCEPTION 'STRATA is not your biller — no invoice counter to set';
  END IF;

  -- The number the NEXT invoice would carry (same formula as allocate_invoice_number).
  v_next := COALESCE(v_prefix, '') || lpad(p_value::text, COALESCE(v_pad, 6), '0');

  -- (A) exact-number collision: that formatted number is already issued.
  IF EXISTS (SELECT 1 FROM public.orders
              WHERE company_id = p_company_id AND invoice_number = v_next) THEN
    RAISE EXCEPTION 'invoice number % is already used — pick a higher start number', v_next;
  END IF;

  -- (B) format-aware monotonic floor: the seed must exceed every existing invoice
  -- number that shares the forward format (prefix + digits), so incrementing
  -- allocation can never re-enter used territory (incl. backfilled QB numbers).
  SELECT COALESCE(max(tail::bigint), 0)
    INTO v_max_series
    FROM (
      SELECT substring(invoice_number FROM char_length(COALESCE(v_prefix, '')) + 1) AS tail
        FROM public.orders
       WHERE company_id = p_company_id
         AND invoice_number IS NOT NULL
         AND left(invoice_number, char_length(COALESCE(v_prefix, ''))) = COALESCE(v_prefix, '')
    ) s
   WHERE tail ~ '^\d+$';
  IF p_value <= v_max_series THEN
    RAISE EXCEPTION 'invoice start number % must be greater than your highest invoice number (%)', p_value, v_max_series;
  END IF;

  UPDATE public.billing_settings
     SET invoice_next_seq = p_value, updated_at = now()
   WHERE company_id = p_company_id;

  RETURN jsonb_build_object('ok', true, 'invoice_next_seq', p_value, 'next_number', v_next);
END;
$$;

REVOKE ALL ON FUNCTION public.set_invoice_next_seq(text, bigint) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.set_invoice_next_seq(text, bigint) TO authenticated;

NOTIFY pgrst, 'reload schema';
