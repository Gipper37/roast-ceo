-- ============================================================
-- Allow 'baseline' as a valid coffee_inventory_purchased.entry_method
-- ============================================================
-- During Phase 1 backfill we synthesize a 'baseline' lot for origins
-- that have stock but no shipment history. The original Phase 1
-- migration (20260608000003) only allowed shipment/roast_quick_add/
-- manual; baseline was added directly on prod after the fact. This
-- catches staging + future fresh projects up.
-- ============================================================

ALTER TABLE public.coffee_inventory_purchased
  DROP CONSTRAINT IF EXISTS coffee_inventory_purchased_entry_method_chk;

ALTER TABLE public.coffee_inventory_purchased
  ADD CONSTRAINT coffee_inventory_purchased_entry_method_chk
  CHECK (entry_method IN ('shipment', 'roast_quick_add', 'manual', 'baseline'));

NOTIFY pgrst, 'reload schema';
