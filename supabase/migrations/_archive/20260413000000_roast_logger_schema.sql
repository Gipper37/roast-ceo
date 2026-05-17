-- Roast Data Logger Schema
-- Creates tables for live roast session logging:
-- roast_sessions, roast_temp_nodes, roast_events, roast_profiles, roast_profile_nodes
-- Also adds session_id FK to roast_log for post-roast linking.

-- ============================================================
-- 1. roast_sessions
--    One row per live roast logging session
-- ============================================================
CREATE TABLE roast_sessions (
  session_id          text        PRIMARY KEY DEFAULT gen_random_uuid()::text,
  roast_log_id        text        REFERENCES roast_log(roast_log_id) ON DELETE SET NULL,
  facility_id         text        NOT NULL,
  company_id          text        NOT NULL,
  roaster_unit_id     uuid        REFERENCES roaster_units(roaster_unit_id) ON DELETE SET NULL,
  status              text        NOT NULL DEFAULT 'active'
                                  CHECK (status IN ('active', 'completed', 'discarded')),
  started_at          timestamptz NOT NULL DEFAULT now(),
  ended_at            timestamptz,
  -- Weights
  green_weight_lbs    numeric,
  roasted_weight_lbs  numeric,
  -- Coffee identification
  charge_weight_id    text        REFERENCES charge_weight_options(id) ON DELETE SET NULL,
  recipe_id           text        REFERENCES roast_recipes(recipe_id) ON DELETE SET NULL,
  origin_id           text        REFERENCES coffee_inventory(origin_id) ON DELETE SET NULL,
  -- Meta
  notes               text,
  created_by          uuid        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_roast_sessions_facility   ON roast_sessions(facility_id);
CREATE INDEX idx_roast_sessions_status     ON roast_sessions(facility_id, status);
CREATE INDEX idx_roast_sessions_started_at ON roast_sessions(facility_id, started_at DESC);
CREATE INDEX idx_roast_sessions_log        ON roast_sessions(roast_log_id) WHERE roast_log_id IS NOT NULL;

-- ============================================================
-- 2. roast_temp_nodes
--    Individual temperature readings (~every 10 seconds)
-- ============================================================
CREATE TABLE roast_temp_nodes (
  node_id        bigint      PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  session_id     text        NOT NULL REFERENCES roast_sessions(session_id) ON DELETE CASCADE,
  elapsed_secs   numeric     NOT NULL,   -- seconds from session started_at
  bt_temp        numeric,               -- Bean Temperature °F (probe 1 / T1)
  et_temp        numeric,               -- Environmental/Air Temp °F (probe 2 / T2)
  bt_ror         numeric,               -- Rate of Rise for BT (°F/min, computed on write)
  et_ror         numeric,               -- Rate of Rise for ET
  facility_id    text        NOT NULL,
  recorded_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_roast_temp_nodes_session ON roast_temp_nodes(session_id, elapsed_secs);
CREATE INDEX idx_roast_temp_nodes_facility ON roast_temp_nodes(facility_id);

-- ============================================================
-- 3. roast_events
--    Milestone events during a roast (First Crack, Drop, etc.)
-- ============================================================
CREATE TABLE roast_events (
  event_id       text        PRIMARY KEY DEFAULT gen_random_uuid()::text,
  session_id     text        NOT NULL REFERENCES roast_sessions(session_id) ON DELETE CASCADE,
  elapsed_secs   numeric     NOT NULL,
  event_type     text        NOT NULL
                             CHECK (event_type IN (
                               'charge', 'turning_point', 'yellowing', 'maillard',
                               'first_crack_start', 'first_crack_end',
                               'second_crack_start', 'drop', 'cool_end', 'custom'
                             )),
  bt_at_event    numeric,    -- BT temp at time of event
  et_at_event    numeric,    -- ET temp at time of event
  label          text,       -- free text label (for 'custom' type)
  notes          text,
  facility_id    text        NOT NULL,
  recorded_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_roast_events_session ON roast_events(session_id, elapsed_secs);

-- ============================================================
-- 4. roast_profiles
--    Saved target roast curves (template for overlay during logging)
-- ============================================================
CREATE TABLE roast_profiles (
  profile_id     text        PRIMARY KEY DEFAULT gen_random_uuid()::text,
  profile_name   text        NOT NULL,
  recipe_id      text        REFERENCES roast_recipes(recipe_id) ON DELETE SET NULL,
  description    text,
  is_active      boolean     NOT NULL DEFAULT true,
  company_id     text        NOT NULL,
  facility_id    text        NOT NULL,
  created_by     uuid        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_roast_profiles_facility ON roast_profiles(facility_id, is_active);

-- ============================================================
-- 5. roast_profile_nodes
--    Data points for a saved target profile curve
-- ============================================================
CREATE TABLE roast_profile_nodes (
  node_id        bigint      PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  profile_id     text        NOT NULL REFERENCES roast_profiles(profile_id) ON DELETE CASCADE,
  elapsed_secs   numeric     NOT NULL,
  bt_temp        numeric,
  et_temp        numeric,
  bt_ror         numeric
);

CREATE INDEX idx_roast_profile_nodes_profile ON roast_profile_nodes(profile_id, elapsed_secs);

-- ============================================================
-- 6. Add session_id to roast_log for post-roast linking
-- ============================================================
ALTER TABLE roast_log
  ADD COLUMN IF NOT EXISTS session_id text REFERENCES roast_sessions(session_id) ON DELETE SET NULL;

CREATE INDEX idx_roast_log_session ON roast_log(session_id) WHERE session_id IS NOT NULL;

-- ============================================================
-- 7. updated_at triggers
-- ============================================================
CREATE TRIGGER trg_roast_sessions_updated_at
  BEFORE UPDATE ON roast_sessions
  FOR EACH ROW EXECUTE FUNCTION handle_updated_record();

CREATE TRIGGER trg_roast_profiles_updated_at
  BEFORE UPDATE ON roast_profiles
  FOR EACH ROW EXECUTE FUNCTION handle_updated_record();

-- ============================================================
-- 8. RLS
-- ============================================================
ALTER TABLE roast_sessions      ENABLE ROW LEVEL SECURITY;
ALTER TABLE roast_temp_nodes    ENABLE ROW LEVEL SECURITY;
ALTER TABLE roast_events        ENABLE ROW LEVEL SECURITY;
ALTER TABLE roast_profiles      ENABLE ROW LEVEL SECURITY;
ALTER TABLE roast_profile_nodes ENABLE ROW LEVEL SECURITY;

-- Service role bypasses RLS (used by API routes)
-- RLS policies will be added when RLS is fully rolled out across the app
-- For now, tables are accessible via service_role key (consistent with rest of app)
