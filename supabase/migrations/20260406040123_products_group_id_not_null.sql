-- Assign the 6 ungrouped sample products to their matching product groups
UPDATE products SET group_id = (
  SELECT group_id FROM product_groups
  WHERE group_name = 'Dawn Patrol' AND facility_id = products.facility_id LIMIT 1
) WHERE product_id = 'cf078713';

UPDATE products SET group_id = (
  SELECT group_id FROM product_groups
  WHERE group_name = 'Hendrix' AND facility_id = products.facility_id LIMIT 1
) WHERE product_id = '2b91698b';

UPDATE products SET group_id = (
  SELECT group_id FROM product_groups
  WHERE group_name = 'Nova' AND facility_id = products.facility_id LIMIT 1
) WHERE product_id = '2f407b45';

UPDATE products SET group_id = (
  SELECT group_id FROM product_groups
  WHERE group_name = 'Pohaku' AND facility_id = products.facility_id LIMIT 1
) WHERE product_id = 'e3026e07';

UPDATE products SET group_id = (
  SELECT group_id FROM product_groups
  WHERE group_name = 'Rubix' AND facility_id = products.facility_id LIMIT 1
) WHERE product_id = '0713a786';

UPDATE products SET group_id = (
  SELECT group_id FROM product_groups
  WHERE group_name = 'Vinyl' AND facility_id = products.facility_id LIMIT 1
) WHERE product_id = '800be196';

-- Verify no active products are still missing a group
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM products WHERE group_id IS NULL AND is_active = true
  ) THEN
    RAISE EXCEPTION 'Active products still missing group_id — migration aborted';
  END IF;
END $$;

-- Add NOT NULL constraint (NOT VALID — skip historical check, enforced going forward)
ALTER TABLE products
  ADD CONSTRAINT products_group_id_not_null CHECK (group_id IS NOT NULL) NOT VALID;
