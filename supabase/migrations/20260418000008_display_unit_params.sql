-- Display unit parameters: roast temperature unit (F/C) and time format (12hr/24hr)
-- Both are facility-level UI display preferences with system defaults.

INSERT INTO standard_parameters (parameters_id, parameter, text_value, data_type)
VALUES
  ('roast_temp_unit', 'Roast Temperature Unit', 'F', 'text'),
  ('time_display',    'Time Display Format',    '12', 'text')
ON CONFLICT (parameters_id) DO NOTHING;
