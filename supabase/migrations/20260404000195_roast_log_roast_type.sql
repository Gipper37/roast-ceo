-- Add roast_type to roast_log
-- Stamped from the page-level roast type status box (Single Origin/Post-Blend or PreBlend)
ALTER TABLE roast_log
  ADD COLUMN IF NOT EXISTS roast_type text;
