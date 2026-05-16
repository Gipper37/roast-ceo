-- ============================================================================
-- Bump the system default for backstock_buffer_pct from 0 to 20.
--
-- Previously the standard_parameters default was 0, meaning new facilities
-- (and any facility that never set a per-facility override) would treat
-- buffer as "roast exactly to demand". 20% is a more sensible default —
-- gives a small cushion against stockouts without blowing up green
-- consumption.
--
-- Per-facility overrides (company_parameters with parameter_id =
-- 'backstock_buffer_pct') are NOT touched — facilities that have
-- explicitly set their own value keep it.
-- ============================================================================

BEGIN;

UPDATE standard_parameters
SET amount = 20
WHERE parameters_id = 'backstock_buffer_pct';

DO $$
DECLARE
  v numeric;
BEGIN
  SELECT amount INTO v FROM standard_parameters WHERE parameters_id = 'backstock_buffer_pct';
  RAISE NOTICE 'standard_parameters.backstock_buffer_pct = %', v;
END $$;

COMMIT;
