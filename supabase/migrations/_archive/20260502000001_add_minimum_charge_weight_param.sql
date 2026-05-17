-- 20260502000001_add_minimum_charge_weight_param.sql
--
-- Adds a "minimum_charge_weight" parameter so the Roast page + Load From
-- Queue can stop proposing a full batch for tiny dribs of buffer-only
-- demand (e.g. 0.07 lbs of buffer rounding up to a 25-lb charge).
--
-- Resolution order in the app (lib/roastParams.ts):
--   1. company_parameters.value_number where parameter_id = 'minimum_charge_weight'
--      (per-facility override)
--   2. standard_parameters.amount where parameters_id = 'minimum_charge_weight'
--      (system-wide default)
--   3. Fallback: 0.5 × preferred charge weight (resolved at call site)
--
-- We deliberately seed the standard_parameters row with NULL amount so
-- the fallback kicks in until an admin (or per-facility override) sets
-- a real value. Nothing in the DB hardcodes a number — the choice lives
-- in the app's resolver.
--
-- Idempotent insert — safe if the row already exists from a hand
-- create. The standard_parameters PK is `parameters_id`.

INSERT INTO standard_parameters (parameters_id, parameter, amount, data_type)
VALUES (
  'minimum_charge_weight',
  'Minimum charge weight (lbs)',
  NULL,
  'decimal'
)
ON CONFLICT (parameters_id) DO NOTHING;
