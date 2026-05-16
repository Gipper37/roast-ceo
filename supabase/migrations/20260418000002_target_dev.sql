-- 00217: Optional per-roast development target
--
-- Lets a roaster set a target development time (seconds) OR target
-- development percentage when adding a roast. The roast profiler renders
-- a live progress bar after first crack that fills toward this target so
-- the user can pace the development phase visually.
--
-- Storage:
--   roast_log.target_dev_secs (numeric, nullable)  — absolute time target
--   roast_log.target_dev_pct  (numeric, nullable)  — percentage target
--   Same two columns on roast_sessions so loaded sessions know the target.
--
-- Both nullable; only one is meant to be set per roast (UI toggles between
-- them). The target is OPTIONAL — when both are null the profiler hides
-- the progress bar entirely.

BEGIN;

ALTER TABLE roast_log
  ADD COLUMN IF NOT EXISTS target_dev_secs numeric,
  ADD COLUMN IF NOT EXISTS target_dev_pct  numeric;

ALTER TABLE roast_sessions
  ADD COLUMN IF NOT EXISTS target_dev_secs numeric,
  ADD COLUMN IF NOT EXISTS target_dev_pct  numeric;

COMMENT ON COLUMN roast_log.target_dev_secs IS
  'Optional target development time in seconds. When set, the live profiler renders a progress bar after first crack. Mutually exclusive with target_dev_pct in the UI but DB allows both.';
COMMENT ON COLUMN roast_log.target_dev_pct IS
  'Optional target development percentage (0-100). Same render behavior as target_dev_secs.';

COMMIT;
