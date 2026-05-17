-- New facility-level toggle: require coffee source on CHARGE.
--
-- When ON, the roast profiler's CHARGE button refuses to fire
-- without a Lot/Source picked alongside the recipe + unit + charge
-- weight. Lets roasteries that track per-lot data tightly (most
-- specialty shops) ensure every roast log entry carries its source
-- attribution, instead of relying on the roaster to remember to
-- select it.
--
-- Default: 'off' (existing behavior — Lot/Source stays optional).
-- Stored as a boolean parameter; per-facility override goes into
-- company_parameters.value (text 'on'/'off' for parity with the
-- other toggle params like roast_profiler_enabled).

BEGIN;

INSERT INTO standard_parameters (parameters_id, parameter, data_type, text_value)
VALUES (
  'require_coffee_source',
  'Require coffee source on CHARGE',
  'boolean',
  'off'
)
ON CONFLICT (parameters_id) DO NOTHING;

COMMENT ON COLUMN standard_parameters.text_value IS
  'Stored as ''on'' / ''off'' for boolean params. Per-facility override lives in company_parameters.value (same shape).';

COMMIT;
