-- =============================================================================
-- Wholesale Shop Foundation
-- =============================================================================
-- 1. Add shop fields to product_groups (image, is_visible, sort_order)
-- 2. Add shop fields to customers (shop_access, resale_cert_received, auth_user_id)
-- 3. Add shop fields to orders (shop_order_id, tax_rate, tax_amount)
-- 4. Add stripe_connect_account_id to companies
-- 5. Create shop_config table
-- 6. Remove wholesale_shipped channel + its 42 products (0 order history)
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. product_groups — shop display fields
-- -----------------------------------------------------------------------------
ALTER TABLE product_groups
  ADD COLUMN IF NOT EXISTS image        text,
  ADD COLUMN IF NOT EXISTS is_visible   boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS sort_order   integer;

COMMENT ON COLUMN product_groups.image      IS 'Shop display image URL (Supabase storage path or external URL)';
COMMENT ON COLUMN product_groups.is_visible IS 'Show this product group in the wholesale shop';
COMMENT ON COLUMN product_groups.sort_order IS 'Display order in shop — lower numbers first. NULL sorts last.';


-- -----------------------------------------------------------------------------
-- 2. customers — shop access + auth link
-- -----------------------------------------------------------------------------
ALTER TABLE customers
  ADD COLUMN IF NOT EXISTS shop_access           text[],
  ADD COLUMN IF NOT EXISTS resale_cert_received  boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS auth_user_id          uuid;

COMMENT ON COLUMN customers.shop_access          IS 'Shop portals this customer can access. Values: ''wholesale'', ''vip''. NULL = no shop access.';
COMMENT ON COLUMN customers.resale_cert_received IS 'Roaster has received resale certificate from this customer. Defaults true — flip off to track explicitly.';
COMMENT ON COLUMN customers.auth_user_id         IS 'Links to auth.users for shop login. Set when customer is invited to the shop.';

-- Index for auth lookup (shop login resolves customer by auth_user_id)
CREATE INDEX IF NOT EXISTS idx_customers_auth_user_id ON customers (auth_user_id);

-- Index for filtering shop customers per company
CREATE INDEX IF NOT EXISTS idx_customers_shop_access ON customers USING gin (shop_access);


-- -----------------------------------------------------------------------------
-- 3. orders — shop origin tracking + tax
-- -----------------------------------------------------------------------------
ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS shop_order_id text,
  ADD COLUMN IF NOT EXISTS tax_rate      numeric,
  ADD COLUMN IF NOT EXISTS tax_amount    numeric;

COMMENT ON COLUMN orders.shop_order_id IS 'Set when order originates from the wholesale shop. NULL = internal STRATA order.';
COMMENT ON COLUMN orders.tax_rate      IS 'Tax rate applied at time of order (0 for wholesale, state rate for VIP).';
COMMENT ON COLUMN orders.tax_amount    IS 'Computed tax amount. Stored at order time so it survives rate changes.';

-- Unique per facility (same pattern as shopify_order_id)
CREATE UNIQUE INDEX IF NOT EXISTS idx_orders_shop_order_id
  ON orders (facility_id, shop_order_id)
  WHERE shop_order_id IS NOT NULL;

-- Fast lookup by shop_order_id alone
CREATE INDEX IF NOT EXISTS idx_orders_shop_order_id_lookup
  ON orders (shop_order_id)
  WHERE shop_order_id IS NOT NULL;


-- -----------------------------------------------------------------------------
-- 4. companies — Stripe Connect
-- -----------------------------------------------------------------------------
ALTER TABLE companies
  ADD COLUMN IF NOT EXISTS stripe_connect_account_id text;

COMMENT ON COLUMN companies.stripe_connect_account_id IS 'Stripe Connect Express account ID (acct_XXXX) for shop payout routing.';

CREATE UNIQUE INDEX IF NOT EXISTS idx_companies_stripe_connect
  ON companies (stripe_connect_account_id)
  WHERE stripe_connect_account_id IS NOT NULL;


-- -----------------------------------------------------------------------------
-- 5. shop_config — per-company shop settings
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS shop_config (
  id                        uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id                text        NOT NULL UNIQUE REFERENCES companies (company_id) ON DELETE CASCADE,
  facility_id               text        REFERENCES facilities (facility_id) ON DELETE SET NULL,
  slug                      text        NOT NULL UNIQUE,
  is_enabled                boolean     NOT NULL DEFAULT false,

  -- Branding
  shop_name                 text,
  tagline                   text,
  logo_url                  text,
  accent_color              text,          -- hex, e.g. '#1E0E00'
  welcome_message           text,

  -- Fulfillment
  shipping_enabled          boolean     NOT NULL DEFAULT false,
  shipping_rate_per_lb      numeric,       -- charge per lb/kg; NULL = free shipping
  shipping_rate_unit        text         DEFAULT 'lb',   -- 'lb' | 'kg'
  free_shipping_threshold   numeric,       -- order total above which shipping is free

  -- Wholesale access settings
  wholesale_enabled         boolean     NOT NULL DEFAULT true,
  vip_enabled               boolean     NOT NULL DEFAULT false,

  -- Stripe Connect (copied from companies for quick access, kept in sync)
  stripe_connect_account_id text,

  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  created_by  text,
  updated_by  text
);

COMMENT ON TABLE  shop_config                              IS 'One row per company. Controls the wholesale shop portal.';
COMMENT ON COLUMN shop_config.slug                        IS 'URL slug: strataroast.com/{slug}. Chosen by company admin, must be unique globally.';
COMMENT ON COLUMN shop_config.shipping_rate_per_lb        IS 'Flat rate per unit weight added to order total for shipped orders. NULL = free.';
COMMENT ON COLUMN shop_config.free_shipping_threshold     IS 'Orders at or above this total get free shipping.';
COMMENT ON COLUMN shop_config.stripe_connect_account_id  IS 'Mirror of companies.stripe_connect_account_id — updated together.';

CREATE INDEX IF NOT EXISTS idx_shop_config_company     ON shop_config (company_id);
CREATE INDEX IF NOT EXISTS idx_shop_config_facility    ON shop_config (facility_id);
CREATE INDEX IF NOT EXISTS idx_shop_config_slug        ON shop_config (slug);     -- slug lookup on every shop page load

-- Keep updated_at current
CREATE OR REPLACE FUNCTION trg_set_shop_config_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_shop_config_updated_at
  BEFORE UPDATE ON shop_config
  FOR EACH ROW EXECUTE FUNCTION trg_set_shop_config_updated_at();

-- Audit hooks (matches rest of app)
CREATE TRIGGER trg_audit_insert
  BEFORE INSERT ON shop_config
  FOR EACH ROW EXECUTE FUNCTION handle_new_record();

CREATE TRIGGER trg_audit_update
  BEFORE UPDATE ON shop_config
  FOR EACH ROW EXECUTE FUNCTION handle_updated_record();


-- -----------------------------------------------------------------------------
-- 6. Remove wholesale_shipped channel and its products
-- -----------------------------------------------------------------------------
-- Null out FK on the 42 products first (FK is ON DELETE SET NULL anyway,
-- but we're going the other direction — archiving products then channel)

-- Hard delete the 42 wholesale_shipped products (confirmed 0 order history)
-- Using session_replication_role to skip audit triggers on bulk delete
SET session_replication_role = replica;

DELETE FROM products
  WHERE channel = 'a8ce7352-6f01-4600-b4d0-009f0880b9a8';

-- Remove the channel row (global, company_id IS NULL)
DELETE FROM channel
  WHERE channel_id = 'a8ce7352-6f01-4600-b4d0-009f0880b9a8';

SET session_replication_role = DEFAULT;
