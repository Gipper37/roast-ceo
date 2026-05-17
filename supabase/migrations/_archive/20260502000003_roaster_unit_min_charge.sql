-- ============================================================================
-- Add per-roaster minimum charge weight.
--
-- Today the minimum-charge-weight floor is a facility-wide parameter
-- (`company_parameters.minimum_charge_weight`). Roasteries with multiple
-- roasters of different sizes (e.g. a 23-lb production roaster + a 1-lb
-- sample roaster) need per-roaster minimums — the production roaster's
-- floor doesn't apply to the sampler and vice versa.
--
-- Resolution priority (after this migration):
--   1. roaster_units.min_charge_weight_id   ← per-roaster (this migration)
--   2. company_parameters.minimum_charge_weight (facility-wide)
--   3. standard_parameters.amount               (system default)
--   4. fallback: 0.5 × roaster's preferred charge weight
-- ============================================================================

BEGIN;

ALTER TABLE roaster_units
  ADD COLUMN IF NOT EXISTS min_charge_weight_id text
  REFERENCES charge_weight_options(id);

COMMENT ON COLUMN roaster_units.min_charge_weight_id IS
  'Optional FK to charge_weight_options for the smallest charge this roaster '
  'will fire. Overrides the facility-wide minimum_charge_weight parameter. '
  'NULL falls back to the facility/system defaults. See lib/roastParams.ts '
  'getMinChargeWeight() for the full resolution chain.';

COMMIT;
