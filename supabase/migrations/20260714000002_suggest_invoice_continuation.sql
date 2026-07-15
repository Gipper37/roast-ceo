-- suggest_invoice_continuation: for the invoice-of-record cutover UI, compute the
-- highest invoice number this company has ALREADY used — whether issued natively
-- (orders.invoice_number) or carried in from a QuickBooks migration
-- (orders.qb_txn_id) — so "Switch to STRATA" / the reset field can pre-fill the
-- next number as max+1 and CONTINUE the series instead of restarting at 1.
--
-- Numeric-only: refs that aren't all-digits (QB credit-memo codes like 'CM2272026'
-- or hand refs) are ignored, matching the empty-prefix "seamless continuation"
-- forward format. This is read-only and advisory; set_invoice_next_seq remains the
-- authoritative guard that actually rejects a colliding seed.
--
-- SECURITY INVOKER: orders RLS scopes the caller to their own company, so a
-- cross-tenant caller simply sees no rows (max null -> suggested null).

CREATE OR REPLACE FUNCTION public.suggest_invoice_continuation(p_company_id text)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
AS $$
  WITH nums AS (
    SELECT (invoice_number)::bigint AS n
      FROM public.orders
     WHERE company_id = p_company_id
       AND invoice_number ~ '^\d+$'
    UNION ALL
    SELECT (qb_txn_id)::bigint AS n
      FROM public.orders
     WHERE company_id = p_company_id
       AND qb_txn_id ~ '^\d+$'
  )
  SELECT jsonb_build_object(
    'max_number',     max(n),
    'suggested_next', CASE WHEN max(n) IS NULL THEN NULL ELSE max(n) + 1 END,
    'source_count',   count(*)
  )
  FROM nums;
$$;

REVOKE ALL ON FUNCTION public.suggest_invoice_continuation(text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.suggest_invoice_continuation(text) TO authenticated;

NOTIFY pgrst, 'reload schema';
