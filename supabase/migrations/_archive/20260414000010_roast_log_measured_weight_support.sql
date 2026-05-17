-- Support the Profile Logger end-weight workflow:
--   1. `actual_retention_factor` — generated column showing the real retention
--      based on measured weight when available, otherwise the trigger-computed
--      roasted weight. Lets reports surface how close each roast was to its
--      configured retention factor.
--   2. `set_roast_measured_weight(roast_log_id, measured_weight)` — RPC that
--      writes the measured weight to both roast_log.measured_roasted_weight and
--      roast_sessions.roasted_weight_lbs atomically, keeping the two tables in
--      sync. UI callers use this instead of bare table updates so the logic
--      stays in the database.

-- 1. Generated column -------------------------------------------------------
-- Actual retention = (measured_roasted_weight ?? roasted_weight) / charge_weight_lbs
-- roasted_weight itself is stamped by trg_stamp_roasted_weight as
-- charge_weight_lbs * retention_factor, so when there's no measurement the
-- generated value equals the configured retention factor. When a measurement
-- exists, the generated value reflects reality.
ALTER TABLE public.roast_log
  ADD COLUMN IF NOT EXISTS actual_retention_factor numeric
  GENERATED ALWAYS AS (
    CASE
      WHEN charge_weight_lbs IS NULL OR charge_weight_lbs <= 0 THEN NULL
      ELSE COALESCE(measured_roasted_weight, roasted_weight) / charge_weight_lbs
    END
  ) STORED;

COMMENT ON COLUMN public.roast_log.actual_retention_factor IS
  'Actual retention factor: COALESCE(measured_roasted_weight, roasted_weight) / charge_weight_lbs. Equals the configured retention factor when no post-roast measurement exists.';

-- 2. RPC to record measured weight -----------------------------------------
CREATE OR REPLACE FUNCTION public.set_roast_measured_weight(
  p_roast_log_id text,
  p_measured_weight numeric
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session_id text;
BEGIN
  -- Update the log row
  UPDATE public.roast_log
     SET measured_roasted_weight = p_measured_weight
   WHERE roast_log_id = p_roast_log_id
  RETURNING session_id INTO v_session_id;

  -- Mirror onto the linked session so downstream queries that read from
  -- roast_sessions (reports, AppSheet, etc.) see the same value.
  IF v_session_id IS NOT NULL THEN
    UPDATE public.roast_sessions
       SET roasted_weight_lbs = p_measured_weight
     WHERE session_id = v_session_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_roast_measured_weight(text, numeric) TO authenticated;

-- Accept NULL (clear the measurement)
-- Note: numeric param accepts NULL, the function will just write NULL to both
-- columns. That's desirable if the user wants to remove a measurement.
