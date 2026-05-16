-- Migration 00206: Product Groups
-- Adds product_groups parent table and group_id / channel / prep_type to products.
-- All existing data is untouched by this migration (group_id nullable, channel nullable).
-- Run populate_product_groups.sql separately to back-fill existing products.

-- ── 1. product_groups table ────────────────────────────────────────────────

CREATE TABLE product_groups (
  group_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_name   text NOT NULL,
  description  text,
  company_id   text REFERENCES companies(company_id) ON DELETE CASCADE,
  facility_id  text REFERENCES facilities(facility_id) ON DELETE CASCADE,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_product_groups_company    ON product_groups(company_id);
CREATE INDEX idx_product_groups_facility   ON product_groups(facility_id);
CREATE INDEX idx_product_groups_name       ON product_groups(group_name);

-- auto-stamp updated_at
CREATE OR REPLACE FUNCTION trg_set_product_groups_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_product_groups_updated_at
  BEFORE UPDATE ON product_groups
  FOR EACH ROW EXECUTE FUNCTION trg_set_product_groups_updated_at();

-- ── 2. New columns on products ─────────────────────────────────────────────

ALTER TABLE products
  ADD COLUMN IF NOT EXISTS group_id   uuid
    REFERENCES product_groups(group_id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS channel    text
    CHECK (channel IN ('retail', 'wholesale', 'vip', 'wholesale_shipped')),
  ADD COLUMN IF NOT EXISTS prep_type  text;

CREATE INDEX idx_products_group_id ON products(group_id);
CREATE INDEX idx_products_channel  ON products(channel);

COMMENT ON COLUMN products.group_id  IS 'Parent product group (coffee name without size/channel suffix)';
COMMENT ON COLUMN products.channel   IS 'Sales channel: retail | wholesale | vip | wholesale_shipped';
COMMENT ON COLUMN products.prep_type IS 'Grind/preparation type, e.g. Whole Bean, Ground, Drip';
