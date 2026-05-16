SET statement_timeout = '120s';

-- Create lookup tables for product_type, channel, and consumable_type
-- These were previously free-text fields; now proper reference tables with FKs

-- ─── product_type ───────────────────────────────────────────────────
CREATE TABLE public.product_type (
  product_type_id text NOT NULL DEFAULT gen_random_uuid()::text,
  product_type    text NOT NULL,
  company_id      text NOT NULL,
  created_at      timestamptz DEFAULT now(),
  updated_at      timestamptz DEFAULT now(),
  created_by      text,
  updated_by      text,
  is_active       boolean NOT NULL DEFAULT true,
  CONSTRAINT product_type_pkey PRIMARY KEY (product_type_id),
  CONSTRAINT product_type_company_id_fkey FOREIGN KEY (company_id)
    REFERENCES public.companies(company_id)
);

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.product_type
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();
CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.product_type
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();

ALTER TABLE public.product_type ENABLE ROW LEVEL SECURITY;

-- Seed from existing distinct product_type values
INSERT INTO public.product_type (product_type_id, product_type, company_id)
SELECT gen_random_uuid()::text, pt, company_id
FROM (
  SELECT DISTINCT product_type AS pt, company_id
  FROM public.products
  WHERE product_type IS NOT NULL AND product_type != ''
) sub;

-- ─── channel ────────────────────────────────────────────────────────
CREATE TABLE public.channel (
  channel_id  text NOT NULL DEFAULT gen_random_uuid()::text,
  channel     text NOT NULL,
  company_id  text NOT NULL,
  created_at  timestamptz DEFAULT now(),
  updated_at  timestamptz DEFAULT now(),
  created_by  text,
  updated_by  text,
  is_active   boolean NOT NULL DEFAULT true,
  CONSTRAINT channel_pkey PRIMARY KEY (channel_id),
  CONSTRAINT channel_company_id_fkey FOREIGN KEY (company_id)
    REFERENCES public.companies(company_id)
);

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.channel
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();
CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.channel
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();

ALTER TABLE public.channel ENABLE ROW LEVEL SECURITY;

-- Seed from existing distinct channel values + add known channels from AppSheet
-- First insert distinct values that exist in products
INSERT INTO public.channel (channel_id, channel, company_id)
SELECT gen_random_uuid()::text, ch, company_id
FROM (
  SELECT DISTINCT channel AS ch, company_id
  FROM public.products
  WHERE channel IS NOT NULL AND channel != ''
) sub;

-- Add missing channels that exist in AppSheet but not yet in products data
-- (vip, wholesale_shipped, sample)
INSERT INTO public.channel (channel_id, channel, company_id)
SELECT gen_random_uuid()::text, ch, c.company_id
FROM (VALUES ('vip'), ('wholesale_shipped'), ('sample')) v(ch)
CROSS JOIN (SELECT DISTINCT company_id FROM public.products WHERE company_id IS NOT NULL) c
WHERE NOT EXISTS (
  SELECT 1 FROM public.channel
  WHERE channel.channel = v.ch AND channel.company_id = c.company_id
);

-- ─── consumable_type (table) ────────────────────────────────────────
-- The column already exists on consumable_inventory; now make a proper lookup table
CREATE TABLE public.consumable_type (
  consumable_type_id text NOT NULL DEFAULT gen_random_uuid()::text,
  consumable_type    text NOT NULL,
  company_id         text NOT NULL,
  created_at         timestamptz DEFAULT now(),
  updated_at         timestamptz DEFAULT now(),
  created_by         text,
  updated_by         text,
  is_active          boolean NOT NULL DEFAULT true,
  CONSTRAINT consumable_type_pkey PRIMARY KEY (consumable_type_id),
  CONSTRAINT consumable_type_company_id_fkey FOREIGN KEY (company_id)
    REFERENCES public.companies(company_id)
);

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.consumable_type
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();
CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.consumable_type
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();

ALTER TABLE public.consumable_type ENABLE ROW LEVEL SECURITY;

-- Seed from existing distinct consumable_type values
INSERT INTO public.consumable_type (consumable_type_id, consumable_type, company_id)
SELECT gen_random_uuid()::text, ct, company_id
FROM (
  SELECT DISTINCT consumable_type AS ct, company_id
  FROM public.consumable_inventory
  WHERE consumable_type IS NOT NULL AND consumable_type != ''
) sub;

-- ─── Migrate existing text values to IDs ────────────────────────────
-- Disable triggers on products and consumable_inventory to avoid
-- audit/check constraint issues during bulk ID migration
ALTER TABLE public.products DISABLE TRIGGER USER;
-- Drop check constraints that conflict with ID migration
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_group_id_not_null;
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_channel_check;
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_company_id_not_null;
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_price_nonnegative;
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_weight_lbs_positive;
ALTER TABLE public.consumable_inventory DISABLE TRIGGER USER;

-- products.product_type: text name → product_type_id
UPDATE public.products p
SET product_type = pt.product_type_id
FROM public.product_type pt
WHERE p.product_type = pt.product_type
  AND p.company_id = pt.company_id;

-- products.channel: text name → channel_id
UPDATE public.products p
SET channel = ch.channel_id
FROM public.channel ch
WHERE p.channel = ch.channel
  AND p.company_id = ch.company_id;

-- Re-enable triggers on products
ALTER TABLE public.products ENABLE TRIGGER USER;
-- Re-add check constraints (except channel_check which is replaced by FK)
ALTER TABLE public.products ADD CONSTRAINT products_group_id_not_null CHECK (group_id IS NOT NULL) NOT VALID;
ALTER TABLE public.products ADD CONSTRAINT products_company_id_not_null CHECK (company_id IS NOT NULL) NOT VALID;
ALTER TABLE public.products ADD CONSTRAINT products_price_nonnegative CHECK (price >= 0) NOT VALID;
ALTER TABLE public.products ADD CONSTRAINT products_weight_lbs_positive CHECK (weight_lbs > 0) NOT VALID;

-- consumable_inventory.consumable_type: text name → consumable_type_id
UPDATE public.consumable_inventory ci
SET consumable_type = ct.consumable_type_id
FROM public.consumable_type ct
WHERE ci.consumable_type = ct.consumable_type
  AND ci.company_id = ct.company_id;

-- Re-enable triggers on consumable_inventory
ALTER TABLE public.consumable_inventory ENABLE TRIGGER USER;

-- ─── Fix consumable_type default and NOT NULL ───────────────────────
-- The old default was 'product' (text name); now needs to be NULL or a valid ID
ALTER TABLE public.consumable_inventory
  ALTER COLUMN consumable_type DROP NOT NULL,
  ALTER COLUMN consumable_type DROP DEFAULT;

-- ─── Add FKs ────────────────────────────────────────────────────────
ALTER TABLE public.products
  ADD CONSTRAINT products_product_type_fkey
  FOREIGN KEY (product_type) REFERENCES public.product_type(product_type_id)
  ON DELETE SET NULL;

ALTER TABLE public.products
  ADD CONSTRAINT products_channel_fkey
  FOREIGN KEY (channel) REFERENCES public.channel(channel_id)
  ON DELETE SET NULL;

ALTER TABLE public.consumable_inventory
  ADD CONSTRAINT consumable_inventory_consumable_type_fkey
  FOREIGN KEY (consumable_type) REFERENCES public.consumable_type(consumable_type_id)
  ON DELETE SET NULL;
