-- Add optional label column to charge_weight_options
-- Allows naming charge weights (e.g. "Full Batch", "Half Batch") in addition to the numeric weight.

ALTER TABLE charge_weight_options
  ADD COLUMN IF NOT EXISTS label text;
