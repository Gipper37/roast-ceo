-- 20260504000005_roaster_trackables_and_adjustments.sql
-- Phase 1 of the roaster-integration foundation.
--
-- WHY
--   We're adding direct integrations with commercial roasters
--   (Loring first, Probat / Giesen / others to follow). Each exposes
--   a richer signal stream than the BLE thermometer: gas %, drum
--   speed, airflow, inlet/stack temps, plus auto-detected events.
--   To support all of that without per-roaster schema branching, we
--   define a STANDARD set of trackables (continuous time-series) and
--   a STANDARD adjustment-event vocabulary (discrete operator/auto
--   actions with numeric values). Each driver maps its native
--   channels onto these standard slots.
--
-- WHAT
--   1. roast_profile_nodes: add 6 trackable columns (continuous).
--      Existing bt_temp / et_temp / bt_ror unchanged.
--   2. roast_events: add value_numeric + value_unit (carries the
--      "to what value" for adjustments — gas → 60%, drum → 5 rpm).
--   3. roast_events: add 5 at-event snapshot columns mirroring the
--      existing bt_at_event / et_at_event pattern.
--   4. New event types are NOT enumerated in a CHECK constraint
--      (event_type stays text) — we just document them here:
--        - gas_adjustment       (value_unit = '%')
--        - drum_adjustment      (value_unit = 'rpm')
--        - airflow_adjustment   (value_unit = '%')
--      Existing types (charge, drop, first_crack_start, etc.) keep
--      their meaning. value_numeric is NULL for those.
--
-- TEMPLATE EVENTS (note for future readers)
--   Roast templates and live sessions use the SAME roast_events
--   table — events are scoped by session_id. A template
--   (roast_sessions.is_profile_template = true) has its events as
--   the "planned schedule"; a live session has events as the
--   "actual timeline". The chart overlay queries both session_ids
--   and renders planned vs actual side-by-side. One source of
--   truth for events; no separate scheduled_events table.
--
-- DRUM SPEED
--   Stored as RPM (matches every controller except Loring, which
--   doesn't expose drum speed at all and leaves it NULL).
--
-- WINDOWS / MACOS
--   No platform considerations at the schema level. The Tauri
--   driver layer that writes these rows is cross-platform Rust
--   (tokio-modbus + btleplug) so both desktop targets benefit.

BEGIN;

-- ════════════════════════════════════════════════════════════════════
-- 1. Trackable columns on roast_profile_nodes
-- ════════════════════════════════════════════════════════════════════
ALTER TABLE public.roast_profile_nodes
  ADD COLUMN IF NOT EXISTS inlet_temp      numeric,
  ADD COLUMN IF NOT EXISTS stack_temp      numeric,
  ADD COLUMN IF NOT EXISTS gas_pct         numeric,
  ADD COLUMN IF NOT EXISTS drum_speed_rpm  numeric,
  ADD COLUMN IF NOT EXISTS airflow_pct     numeric,
  ADD COLUMN IF NOT EXISTS ambient_temp    numeric;

COMMENT ON COLUMN public.roast_profile_nodes.inlet_temp IS
  'Combustion inlet air temperature (°F). Loring reg 772; Probat exposes; null when driver does not report.';
COMMENT ON COLUMN public.roast_profile_nodes.stack_temp IS
  'Exhaust / stack temperature (°F). Loring exposes; null otherwise.';
COMMENT ON COLUMN public.roast_profile_nodes.gas_pct IS
  'Burner / flame level (0–100). Loring reg 770; most controllers expose this.';
COMMENT ON COLUMN public.roast_profile_nodes.drum_speed_rpm IS
  'Drum rotation speed in RPM. Probat / Giesen expose directly; Loring does not (NULL).';
COMMENT ON COLUMN public.roast_profile_nodes.airflow_pct IS
  'Fan / blower percentage (0–100). Probat / Giesen expose; Loring does not (NULL).';
COMMENT ON COLUMN public.roast_profile_nodes.ambient_temp IS
  'Ambient room temperature (°F). Optional sensor on some setups.';

-- ════════════════════════════════════════════════════════════════════
-- 2. Adjustment-event value carrier on roast_events
-- ════════════════════════════════════════════════════════════════════
ALTER TABLE public.roast_events
  ADD COLUMN IF NOT EXISTS value_numeric  numeric,
  ADD COLUMN IF NOT EXISTS value_unit     text;

COMMENT ON COLUMN public.roast_events.value_numeric IS
  'Numeric setpoint for adjustment events (e.g. 60 for gas → 60%). NULL for non-adjustment events.';
COMMENT ON COLUMN public.roast_events.value_unit IS
  'Unit for value_numeric. Conventional values: %, rpm, °F, °C. NULL when value_numeric is NULL.';

-- ════════════════════════════════════════════════════════════════════
-- 3. At-event machine-state snapshots on roast_events
-- ════════════════════════════════════════════════════════════════════
ALTER TABLE public.roast_events
  ADD COLUMN IF NOT EXISTS gas_at_event      numeric,
  ADD COLUMN IF NOT EXISTS drum_at_event     numeric,
  ADD COLUMN IF NOT EXISTS airflow_at_event  numeric,
  ADD COLUMN IF NOT EXISTS inlet_at_event    numeric,
  ADD COLUMN IF NOT EXISTS stack_at_event    numeric;

COMMENT ON COLUMN public.roast_events.gas_at_event IS
  'Snapshot of gas % at the moment of the event. Mirrors the existing bt_at_event / et_at_event pattern.';

-- ════════════════════════════════════════════════════════════════════
-- 4. Indexing — events are queried by session_id heavily on the chart
--    overlay; profile_nodes by profile_id + elapsed_secs. Existing
--    indexes already cover those, no new ones needed.
-- ════════════════════════════════════════════════════════════════════

DO $$
BEGIN
  RAISE NOTICE 'roast_profile_nodes + roast_events extended with standard trackables and adjustment values.';
END $$;

COMMIT;
