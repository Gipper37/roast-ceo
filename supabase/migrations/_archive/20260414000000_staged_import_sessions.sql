-- Temporary staging table for Roastmaster import sessions.
-- Client uploads extracted sessions here in small chunks,
-- then kicks off server-side processing that reads from this table.
-- This avoids the 4.5MB Vercel payload limit.

CREATE TABLE IF NOT EXISTS staged_import_sessions (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  import_id text NOT NULL REFERENCES roastmaster_imports(import_id) ON DELETE CASCADE,
  payload jsonb NOT NULL,  -- single session as JSON
  processed boolean NOT NULL DEFAULT false
);

CREATE INDEX idx_staged_import_sessions_import ON staged_import_sessions(import_id, processed);
