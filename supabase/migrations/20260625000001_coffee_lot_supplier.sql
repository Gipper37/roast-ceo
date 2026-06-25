-- Per-lot supplier on coffee_inventory_purchased.
--
-- Until now supplier lived only on the GROUP (coffee_inventory.supplier_id),
-- the SOURCE (coffee_source.supplier_id), or a SHIPMENT (shipment_received).
-- That can't express "same source, different supplier for THIS lot" — a real
-- case when a roaster buys the same coffee from a second importer. The lot is
-- the natural home for "where this batch actually came from", and it's the
-- direction lot-precise COGS / HACCP lot tracking already points.
--
-- Nullable: when null, readers fall back to the source's (then group's)
-- supplier. Set at count-add time (addSourceLot) or when a receipt is recorded.
ALTER TABLE public.coffee_inventory_purchased
  ADD COLUMN IF NOT EXISTS supplier_id text
    REFERENCES public.supplier(supplier_id) ON DELETE SET NULL;

COMMENT ON COLUMN public.coffee_inventory_purchased.supplier_id IS
  'Per-lot supplier — where THIS lot was bought from. Nullable; falls back to the source/group supplier when null. Set at count-add (addSourceLot) or receipt time.';
