-- Add a roast_profiler_enabled parameter so each facility can choose whether
-- the in-app live roast profiler (right-hand pane on the roast page) appears.
-- Roasters who only use the queue/log workflow can hide the profiler entirely.
--
-- Stored as a text parameter; valid values:
--   'on'  — profiler pane is shown on the roast page (default)
--   'off' — profiler pane is hidden; only the roast log shows
INSERT INTO public.standard_parameters (parameters_id, parameter, text_value, data_type)
VALUES ('roast_profiler_enabled', 'STRATA Roast Profiler', 'on', 'text')
ON CONFLICT (parameters_id) DO NOTHING;
