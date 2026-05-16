-- ─────────────────────────────────────────────────────────────────────
-- Distinguish "what we expected to pay" (target) from "what we actually
-- paid" on coffee purchase line items.
--
-- Background: when a PO is sent to a supplier we record an expected
-- price per pound. When the shipment arrives the actual invoiced price
-- might differ (markup, fees, discount, weight variance). Until now
-- we've smashed both into `cost_lb` which forced users to overwrite
-- their target with the actual at receive-time, losing the original
-- quote.
--
-- New layout:
--   target_cost_lb  — what was on the PO (set when sending the PO)
--   cost_lb         — actual cost per lb (set on receive); unchanged
--                     for legacy / non-PO shipments
--
-- Triggers and views still consume `cost_lb` for COGS — we don't
-- propagate target into the cost chain. Target is reference-only.
-- ─────────────────────────────────────────────────────────────────────

ALTER TABLE coffee_inventory_purchased
  ADD COLUMN IF NOT EXISTS target_cost_lb numeric;

COMMENT ON COLUMN coffee_inventory_purchased.target_cost_lb IS
  'Quoted/expected cost per lb at PO send time. Reference only — does '
  'not feed COGS. cost_lb holds the actual invoiced price (set on '
  'receive). Null for shipments that were never POs.';
