-- ============================================================================
-- Consumable preferred supplier (parity with coffee_inventory.supplier_id)
-- ============================================================================
-- consumable_inventory had no supplier column, so the inventory supplier
-- filter had to derive each item's supplier from purchase history. Add a real
-- preferred-supplier column (like coffee), backfilled from each item's most
-- recent purchase, and maintained by the order flow going forward.
-- ============================================================================

ALTER TABLE public.consumable_inventory
  ADD COLUMN IF NOT EXISTS supplier_id text;

-- Backfill: most recent purchase's supplier for each consumable.
WITH latest AS (
  SELECT DISTINCT ON (cip.consumable_inventory_item)
         cip.consumable_inventory_item AS cid,
         sr.supplier_id
    FROM public.consumable_inventory_purchased cip
    JOIN public.shipment_received sr ON sr.shipment_id = cip.shipment_id
   WHERE sr.supplier_id IS NOT NULL
   ORDER BY cip.consumable_inventory_item,
            COALESCE(sr.date_received, sr.order_date) DESC NULLS LAST
)
UPDATE public.consumable_inventory ci
   SET supplier_id = latest.supplier_id
  FROM latest
 WHERE ci.consumable_inventory_id = latest.cid
   AND ci.supplier_id IS NULL;
