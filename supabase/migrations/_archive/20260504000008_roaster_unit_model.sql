-- 20260504000008_roaster_unit_model.sql
-- Add model column to roaster_units. Brand identifies the manufacturer
-- (Loring, Probat, …); model identifies the specific machine (S15, P25,
-- W6A, …). Model is informational + future-proofing for model-specific
-- quirks; brand still gates the driver picker.
--
-- BACKWARDS COMPATIBLE
--   Nullable. Existing units stay functional with no model set.

BEGIN;

ALTER TABLE public.roaster_units
  ADD COLUMN IF NOT EXISTS model text;

COMMENT ON COLUMN public.roaster_units.model IS
  'Roaster model (e.g. ''S15'', ''P25'', ''W6A''). Free-text but the form offers a brand-aware dropdown of known models. Not used for driver selection — brand handles that.';

COMMIT;
