-- =============================================================================
-- Shop: exclusive product group visibility + shop-assets storage bucket
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. product_groups — exclusive customer scoping
-- -----------------------------------------------------------------------------
-- If exclusive_to_customer_ids IS NULL → visible to all approved shop customers.
-- If set → only those customer IDs can see this product group in the shop.
ALTER TABLE product_groups
  ADD COLUMN IF NOT EXISTS exclusive_to_customer_ids text[];

COMMENT ON COLUMN product_groups.exclusive_to_customer_ids IS
  'If NULL, product group is visible to all approved shop customers. '
  'If set, only listed customer_ids can see it (e.g. custom blends for a single account).';

CREATE INDEX IF NOT EXISTS idx_product_groups_exclusive_customers
  ON product_groups USING gin (exclusive_to_customer_ids)
  WHERE exclusive_to_customer_ids IS NOT NULL;

-- -----------------------------------------------------------------------------
-- 2. shop-assets storage bucket (public read, PNG only, 1MB limit)
-- -----------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('shop-assets', 'shop-assets', true, 1048576, '{image/png}')
ON CONFLICT (id) DO NOTHING;

-- Allow authenticated users (internal team) to upload/update
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'shop_assets_auth_upload'
  ) THEN
    CREATE POLICY "shop_assets_auth_upload"
      ON storage.objects FOR INSERT TO authenticated
      WITH CHECK (bucket_id = 'shop-assets');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'shop_assets_auth_update'
  ) THEN
    CREATE POLICY "shop_assets_auth_update"
      ON storage.objects FOR UPDATE TO authenticated
      USING (bucket_id = 'shop-assets');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'shop_assets_public_read'
  ) THEN
    CREATE POLICY "shop_assets_public_read"
      ON storage.objects FOR SELECT TO public
      USING (bucket_id = 'shop-assets');
  END IF;
END;
$$;
