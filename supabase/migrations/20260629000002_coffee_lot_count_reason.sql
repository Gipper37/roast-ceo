-- Optional adjustment reason on a coffee lot count, so the count ledger reads
-- like an inventory-adjustment journal: Found / Shrinkage / Spoilage / Correction
-- (free text tolerated). NULL = a routine count with no special reason.
-- coffee_lot_count is already the per-lot count journal; this just categorizes it.
ALTER TABLE public.coffee_lot_count
  ADD COLUMN IF NOT EXISTS reason text;

COMMENT ON COLUMN public.coffee_lot_count.reason IS
  'Optional adjustment reason for a count (Found / Shrinkage / Spoilage / Correction). NULL for routine counts.';
