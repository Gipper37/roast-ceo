-- Sprint 6.1 (B2C guest checkout): tokenized receipt access for guests.
--
-- Guest buyers have no auth session, so the receipt page can't gate by
-- customer_users → customer.company_id like wholesale/VIP buyers do.
-- Instead, the order gets a per-order opaque token (UUID, ~122 bits of
-- entropy) that's appended to the success/email links as ?t=<token>.
--
-- Wholesale and VIP orders (auth'd buyers) leave this column NULL — they
-- continue to use the auth-scoped lookup path. Only the guest checkout
-- writes a token here.
--
-- Tokens never expire and aren't rotated. They're per-order, one-shot
-- secrets in the same risk class as a Shopify order-status URL — guess-
-- able only via brute force of 2^122. Not used for any privileged action,
-- only read access to the receipt detail. Acceptable risk for the read-
-- only use case.

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS receipt_token text;

COMMENT ON COLUMN public.orders.receipt_token IS
  'Per-order opaque token for guest receipt access via /[slug]/order/[ref]?t=<token>. NULL for auth''d (wholesale/VIP) orders.';

-- Index by token so the receipt-page lookup is O(1). Partial index on
-- non-null only — the column is mostly NULL so a full index would waste
-- space without helping any query.
CREATE INDEX IF NOT EXISTS idx_orders_receipt_token
  ON public.orders(receipt_token)
  WHERE receipt_token IS NOT NULL;
