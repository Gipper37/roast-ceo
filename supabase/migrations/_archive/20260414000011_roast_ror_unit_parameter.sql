-- Add a roast_ror_unit parameter so each facility can pick how Rate of Rise
-- is displayed: per minute (industry default) or per 30 seconds (preferred by
-- some traditional roasters). Stored as a text parameter; valid values:
--   'minute' (default)
--   '30sec'
--
-- The actual calculation always happens in °/min internally; the UI just
-- divides by 2 and changes the label when '30sec' is selected. This keeps
-- stored data and downstream math unchanged.

INSERT INTO public.standard_parameters (parameters_id, parameter, text_value, data_type)
VALUES ('roast_ror_unit', 'Rate of Rise Display Unit', 'minute', 'text')
ON CONFLICT (parameters_id) DO NOTHING;

COMMENT ON COLUMN public.standard_parameters.text_value IS
  'For roast_ror_unit: ''minute'' or ''30sec''.';
