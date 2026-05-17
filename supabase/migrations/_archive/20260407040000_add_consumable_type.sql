-- Add consumable_type to distinguish product BOM items from operational items
-- 'product' = should be linked to products (labels, bags, boxes for product packaging)
-- 'operational' = shipping supplies, barcodes, etc. — never linked to a product BOM

ALTER TABLE public.consumable_inventory
  ADD COLUMN consumable_type text NOT NULL DEFAULT 'product';

-- Tag known operational items
UPDATE consumable_inventory SET consumable_type = 'operational'
WHERE consumable_inventory_id IN (
  'cdbdf8c9',  -- Fedex Extra Large Box
  '9105ff69',  -- Fedex Large Box
  '2d7bcf2f',  -- Fedex PAK
  'b8fff59d',  -- USPS PAK
  '293eb50d',  -- Hendrix Barcode
  '9287a5e0',  -- Hon Solo 8oz Barcode
  'f99d919c',  -- Hon Solo Barcode
  '70f9ec17'   -- Vinyl Barcode
);

COMMENT ON COLUMN consumable_inventory.consumable_type IS 'product = BOM item (labels, bags); operational = shipping/misc (FedEx boxes, barcodes)';
