-- Backfill: facilities currently displaying weights in kg were also seeing
-- temperatures in °C (the roast pages used `units === 'kg' ? 'C' : 'F'` as a
-- shortcut). Now that roast_temp_unit is a real param, seed it to 'C' for those
-- facilities so they don't suddenly flip to °F.
-- Skip audit trigger (manual backfill, no need to bump updated_at).

SET LOCAL app.skip_audit = 'true';

INSERT INTO company_parameters (parameter_id, company_id, facility_id, value)
SELECT 'roast_temp_unit', units_row.company_id, units_row.facility_id, 'C'
FROM company_parameters units_row
WHERE units_row.parameter_id = 'units'
  AND units_row.value = 'kg'
  AND NOT EXISTS (
    SELECT 1
    FROM company_parameters existing
    WHERE existing.parameter_id = 'roast_temp_unit'
      AND existing.company_id = units_row.company_id
      AND (
        existing.facility_id = units_row.facility_id
        OR (existing.facility_id IS NULL AND units_row.facility_id IS NULL)
      )
  );
