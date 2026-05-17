-- =============================================================================
-- 20260423000001_orders_address_snapshot.sql
--
-- Snapshot the shipping + billing addresses on every shop order at the moment
-- of checkout. This is critical because:
--
--   1. Receipts / order-confirmation pages / email confirmations need to show
--      the address that was actually used, NOT whatever the customer's saved
--      default happens to be at the time the page is rendered. (A customer
--      who later updates their saved address shouldn't retroactively change
--      what last month's invoice says.)
--
--   2. Wholesale buyers frequently override the default per order ("ship this
--      one to our second cafe", "bill the LLC instead of me personally"). We
--      need to capture that override on the order itself.
--
--   3. AVS / chargeback evidence relies on knowing exactly which billing
--      address was sent to the gateway for each charge.
--
-- All columns are nullable. Backfill is intentionally skipped — pre-existing
-- staff-entered orders never had this data and trying to derive it from
-- customers risks misattribution. Only newly-placed shop orders will carry it.
--
-- Naming on shipping side mirrors `customers` (street/street_2/city/state/zip)
-- so the write-time mapping is a 1:1 copy. Billing side mirrors customers'
-- billing_* (which uses `address`/`address_2`) for the same reason — we
-- prefix with bill_to_ for clarity at the order level.
-- =============================================================================

ALTER TABLE orders
  -- Shipping snapshot (where the goods physically go)
  ADD COLUMN IF NOT EXISTS ship_to_name      text,
  ADD COLUMN IF NOT EXISTS ship_to_phone     text,
  ADD COLUMN IF NOT EXISTS ship_to_email     text,
  ADD COLUMN IF NOT EXISTS ship_to_street    text,
  ADD COLUMN IF NOT EXISTS ship_to_street_2  text,
  ADD COLUMN IF NOT EXISTS ship_to_city      text,
  ADD COLUMN IF NOT EXISTS ship_to_state     text,
  ADD COLUMN IF NOT EXISTS ship_to_zip       text,
  ADD COLUMN IF NOT EXISTS ship_to_country   text,
  -- Billing snapshot (the cardholder address, used for AVS on card orders;
  -- on net-terms orders this is whoever the invoice should be made out to)
  ADD COLUMN IF NOT EXISTS bill_to_name      text,
  ADD COLUMN IF NOT EXISTS bill_to_phone     text,
  ADD COLUMN IF NOT EXISTS bill_to_email     text,
  ADD COLUMN IF NOT EXISTS bill_to_address   text,
  ADD COLUMN IF NOT EXISTS bill_to_address_2 text,
  ADD COLUMN IF NOT EXISTS bill_to_city      text,
  ADD COLUMN IF NOT EXISTS bill_to_state     text,
  ADD COLUMN IF NOT EXISTS bill_to_zip       text,
  ADD COLUMN IF NOT EXISTS bill_to_country   text;

COMMENT ON COLUMN orders.ship_to_name      IS 'Snapshot of shipping recipient name at checkout. Often customer.name_company but may be overridden per-order.';
COMMENT ON COLUMN orders.ship_to_phone     IS 'Snapshot of shipping contact phone at checkout. For carrier delivery contact.';
COMMENT ON COLUMN orders.ship_to_email     IS 'Snapshot of shipping contact email at checkout. For shipment notifications.';
COMMENT ON COLUMN orders.ship_to_street    IS 'Snapshot of shipping street address line 1 at checkout.';
COMMENT ON COLUMN orders.ship_to_street_2  IS 'Snapshot of shipping street address line 2 (apt/suite) at checkout.';
COMMENT ON COLUMN orders.ship_to_city      IS 'Snapshot of shipping city at checkout.';
COMMENT ON COLUMN orders.ship_to_state     IS 'Snapshot of shipping state/region at checkout.';
COMMENT ON COLUMN orders.ship_to_zip       IS 'Snapshot of shipping postal code at checkout.';
COMMENT ON COLUMN orders.ship_to_country   IS 'Snapshot of shipping country (ISO 3166-1 alpha-2) at checkout.';
COMMENT ON COLUMN orders.bill_to_name      IS 'Snapshot of cardholder / bill-to name at checkout. Used for AVS and the printed invoice.';
COMMENT ON COLUMN orders.bill_to_phone     IS 'Snapshot of bill-to phone at checkout.';
COMMENT ON COLUMN orders.bill_to_email     IS 'Snapshot of bill-to email at checkout.';
COMMENT ON COLUMN orders.bill_to_address   IS 'Snapshot of cardholder billing address line 1 at checkout. Used for AVS.';
COMMENT ON COLUMN orders.bill_to_address_2 IS 'Snapshot of cardholder billing address line 2 at checkout.';
COMMENT ON COLUMN orders.bill_to_city      IS 'Snapshot of cardholder billing city at checkout.';
COMMENT ON COLUMN orders.bill_to_state     IS 'Snapshot of cardholder billing state at checkout.';
COMMENT ON COLUMN orders.bill_to_zip       IS 'Snapshot of cardholder billing postal code at checkout. Primary AVS field.';
COMMENT ON COLUMN orders.bill_to_country   IS 'Snapshot of cardholder billing country (ISO 3166-1 alpha-2) at checkout.';
