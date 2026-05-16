-- Reference profile name on roast_sessions
-- Any session with temp nodes can be used as a reference profile
ALTER TABLE roast_sessions
  ADD COLUMN IF NOT EXISTS profile_name text;

COMMENT ON COLUMN roast_sessions.profile_name IS
  'Optional display name for this session when used as a reference profile (e.g. "Kenya Natural – Jun Best")';

-- Link a staged roast_log entry to a reference profile session
-- session_id is text on roast_sessions so we match the type
ALTER TABLE roast_log
  ADD COLUMN IF NOT EXISTS reference_profile_id text
    REFERENCES roast_sessions(session_id) ON DELETE SET NULL;

COMMENT ON COLUMN roast_log.reference_profile_id IS
  'Optional reference session whose temperature curve is overlaid as a ghost in the Profile Log';
