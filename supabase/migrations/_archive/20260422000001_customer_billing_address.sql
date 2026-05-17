-- =============================================================================
-- 20260422000001_customer_billing_address.sql
--
-- Adds a separate billing address to customers (cardholder address-on-file for
-- AVS), plus a shipping line-2 column (apartment/suite — currently missing).
--
-- Why: Activity Pay (and every gateway) keys AVS on the address the issuer has
-- on file for the cardholder. That's frequently a personal home even when the
-- shipment goes to a commercial roastery. Without it AVS can't match and we
-- lose chargeback defense + fraud signal strength.
--
-- Naming: kept consistent with existing `street`/`zip` for shipping. Billing
-- side uses `billing_address` / `billing_address_2` because it's a more
-- conventional payment-form label (and we'll likely rename the shipping side
-- to `address_line_1` later anyway, in one sweep).
--
-- Defaults: `billing_same_as_shipping = true` so existing customers don't
-- need any new data entry — checkout falls back to shipping address.
-- =============================================================================

ALTER TABLE customers
  ADD COLUMN IF NOT EXISTS street_2                 text,
  ADD COLUMN IF NOT EXISTS billing_same_as_shipping boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS billing_address          text,
  ADD COLUMN IF NOT EXISTS billing_address_2        text,
  ADD COLUMN IF NOT EXISTS billing_city             text,
  ADD COLUMN IF NOT EXISTS billing_state            text,
  ADD COLUMN IF NOT EXISTS billing_zip              text,
  ADD COLUMN IF NOT EXISTS billing_country          text NOT NULL DEFAULT 'US';

COMMENT ON COLUMN customers.street_2                 IS 'Shipping address line 2 (apt/suite/unit). Optional.';
COMMENT ON COLUMN customers.billing_same_as_shipping IS 'When true, checkout uses street/street_2/city/state/zip for AVS. When false, checkout uses billing_* fields.';
COMMENT ON COLUMN customers.billing_address          IS 'Cardholder billing address line 1 (address on file with card issuer).';
COMMENT ON COLUMN customers.billing_address_2        IS 'Cardholder billing address line 2 (apt/suite/unit).';
COMMENT ON COLUMN customers.billing_city             IS 'Cardholder billing city.';
COMMENT ON COLUMN customers.billing_state            IS 'Cardholder billing state/region.';
COMMENT ON COLUMN customers.billing_zip              IS 'Cardholder billing postal code (used in AVS check).';
COMMENT ON COLUMN customers.billing_country          IS 'Cardholder billing country (ISO 3166-1 alpha-2). Defaults to US.';
