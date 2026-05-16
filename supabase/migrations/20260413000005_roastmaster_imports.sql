-- Track Roastmaster import batches for history, revert, and resume
CREATE TABLE IF NOT EXISTS roastmaster_imports (
  import_id text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  facility_id text NOT NULL REFERENCES facilities(facility_id),
  company_id text NOT NULL,
  import_mode text NOT NULL DEFAULT 'new',             -- 'new' | 'link_and_new' | 'link_only'
  status text NOT NULL DEFAULT 'running',              -- 'running' | 'completed' | 'failed' | 'reverted'
  total_in_file integer NOT NULL DEFAULT 0,            -- roasts found in file
  sessions_imported integer NOT NULL DEFAULT 0,
  sessions_linked integer NOT NULL DEFAULT 0,
  sessions_skipped integer NOT NULL DEFAULT 0,         -- duplicates skipped
  profiles_imported integer NOT NULL DEFAULT 0,
  profiles_skipped integer NOT NULL DEFAULT 0,
  error_count integer NOT NULL DEFAULT 0,
  errors jsonb DEFAULT '[]'::jsonb,
  session_ids text[] DEFAULT '{}',                     -- for revert
  created_log_ids text[] DEFAULT '{}',                 -- for revert
  imported_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  reverted_at timestamptz
);

CREATE INDEX idx_roastmaster_imports_facility ON roastmaster_imports(facility_id);
