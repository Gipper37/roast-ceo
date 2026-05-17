-- Migration 00118: Drop size_lbs from bag_sizes
--
-- size_lbs is redundant — it holds the same value as bag_size_id (numeric vs text).
-- No function or trigger reads it; all 9 calculation functions cast bag_size_id::numeric
-- directly from the coffee_inventory.bag_size text column.
-- The label column handles display; AppSheet appends the correct unit via dependent
-- display formula. size_lbs also bakes in lbs as the canonical unit, which is wrong
-- for metric/international facilities.

ALTER TABLE public.bag_sizes DROP COLUMN size_lbs;
