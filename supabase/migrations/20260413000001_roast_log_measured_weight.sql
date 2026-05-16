-- Add measured_roasted_weight to roast_log
-- Stores the actual roasted weight recorded by the Profile Logger.
-- Does NOT conflict with the trigger-computed roasted_weight (used for cost calculations).
ALTER TABLE roast_log
  ADD COLUMN IF NOT EXISTS measured_roasted_weight numeric;

COMMENT ON COLUMN roast_log.measured_roasted_weight IS
  'Actual roasted weight (lbs) measured by the Profile Logger. Separate from trigger-computed roasted_weight which is used for COGS calculations.';
