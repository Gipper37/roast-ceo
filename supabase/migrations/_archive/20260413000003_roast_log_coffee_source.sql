-- Add coffee_source_id to roast_log for lot-level traceability
ALTER TABLE roast_log
  ADD COLUMN IF NOT EXISTS coffee_source_id text REFERENCES coffee_source(coffee_source_id) ON DELETE SET NULL;
