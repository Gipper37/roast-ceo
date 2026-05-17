-- 20260504000006_trackables_on_roast_temp_nodes.sql
-- Fixup: the previous migration (000005) added trackable columns to
-- `roast_profile_nodes`, but the LIVE trace table is actually
-- `roast_temp_nodes` (563k rows). `roast_profile_nodes` (0 rows) is
-- unused legacy. Mirror the same trackable columns onto roast_temp_nodes
-- so the live driver can persist them.
--
-- The columns on roast_profile_nodes from 000005 stay (harmless on an
-- unused table; rolling back would just be churn). When/if profile_nodes
-- gets put back into use, the columns are already there.

BEGIN;

ALTER TABLE public.roast_temp_nodes
  ADD COLUMN IF NOT EXISTS inlet_temp      numeric,
  ADD COLUMN IF NOT EXISTS stack_temp      numeric,
  ADD COLUMN IF NOT EXISTS gas_pct         numeric,
  ADD COLUMN IF NOT EXISTS drum_speed_rpm  numeric,
  ADD COLUMN IF NOT EXISTS airflow_pct     numeric,
  ADD COLUMN IF NOT EXISTS ambient_temp    numeric;

COMMENT ON COLUMN public.roast_temp_nodes.inlet_temp IS
  'Combustion inlet air temperature (°F). Loring exposes; Probat exposes; null when driver does not report.';
COMMENT ON COLUMN public.roast_temp_nodes.stack_temp IS
  'Exhaust / stack temperature (°F). Loring exposes; null otherwise.';
COMMENT ON COLUMN public.roast_temp_nodes.gas_pct IS
  'Burner / flame level (0–100). Loring reg 770; most controllers expose this.';
COMMENT ON COLUMN public.roast_temp_nodes.drum_speed_rpm IS
  'Drum rotation speed in RPM. Probat / Giesen expose directly; Loring does not (NULL).';
COMMENT ON COLUMN public.roast_temp_nodes.airflow_pct IS
  'Fan / blower percentage (0–100). Probat / Giesen expose; Loring does not (NULL).';
COMMENT ON COLUMN public.roast_temp_nodes.ambient_temp IS
  'Ambient room temperature (°F). Optional sensor on some setups.';

COMMIT;
