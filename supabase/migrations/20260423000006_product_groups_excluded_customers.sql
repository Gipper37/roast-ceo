-- ---------------------------------------------------------------------------
-- product_groups.excluded_from_customer_ids
--
-- Inverse of exclusive_to_customer_ids: a list of customer_ids that should
-- NOT see this product group in the wholesale shop.
--
-- Use cases:
--   - One particular wholesale customer is on a competing house blend, so
--     hide your "Espresso Blend" from them only.
--   - A VIP customer pre-buys the entire allocation of a single-origin and
--     you want to keep it off everyone else's shelf without flipping the
--     whole product to "Visible to: this one customer" (which would be more
--     work to undo).
--
-- Filter rules (enforced server-side in app/(shop)/[slug]/page.tsx):
--   1. exclusive_to_customer_ids takes precedence — if set, it's the
--      authoritative allowlist and the exclude list is ignored.
--   2. Otherwise the group is hidden from any customer whose customer_id
--      appears in excluded_from_customer_ids.
--   3. Guests (no customer record) bypass both lists; this column is only
--      relevant to wholesale/VIP buyers anyway.
-- ---------------------------------------------------------------------------

ALTER TABLE public.product_groups
  ADD COLUMN IF NOT EXISTS excluded_from_customer_ids text[];

COMMENT ON COLUMN public.product_groups.excluded_from_customer_ids IS
  'Wholesale shop: customer_ids that should NOT see this group. Ignored when exclusive_to_customer_ids is also set (allowlist wins).';
