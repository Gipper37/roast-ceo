-- Distinguish profile templates from regular roast sessions.
-- In Roastmaster (and Artisan/Cropster), profiles are standalone template curves
-- that a roaster follows as a guide. They are NOT sessions — they're separate entities.
-- A session REFERENCES a profile (via reference_profile_id), but is not itself a profile.
--
-- is_profile_template = true  → this is a reference curve (imported from ZROASTERPROFILE)
-- is_profile_template = false → this is a regular roast session (imported from ZROAST or logged live)

ALTER TABLE roast_sessions
  ADD COLUMN IF NOT EXISTS is_profile_template boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN roast_sessions.is_profile_template
  IS 'True = standalone profile template (ideal reference curve). False = actual roast session.';

-- Index for fast profile template lookups (reference profile picker in logger)
CREATE INDEX IF NOT EXISTS idx_roast_sessions_profile_templates
  ON roast_sessions (facility_id)
  WHERE is_profile_template = true;
