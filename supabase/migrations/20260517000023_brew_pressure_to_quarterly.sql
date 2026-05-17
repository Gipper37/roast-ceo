-- ============================================================
-- Move "Verify brew pressure (9 bar)" from monthly → quarterly
-- ============================================================
-- Updates three layers in sync:
--   1. maintenance_template default (the template's intrinsic cadence)
--   2. pgm_espresso_standard program override (so Standard inherits)
--   3. Live equipment_schedule rows whose cadence still matches the
--      OLD monthly+1 default — meaning the operator hadn't customized
--      it, so it's safe to propagate. Customized rows are left alone.
--
-- Espresso Premium is intentionally NOT moved — Premium PM keeps the
-- weekly cadence on this task as the differentiator.
-- ============================================================

-- 1. Template default
UPDATE public.maintenance_template
   SET frequency_type     = 'quarterly',
       frequency_interval = 1,
       updated_at         = now()
 WHERE template_id = 'mt_espresso_brew_pressure_test';

-- 2. Standard program override
UPDATE public.maintenance_program_template
   SET frequency_type     = 'quarterly',
       frequency_interval = 1
 WHERE program_id  = 'pgm_espresso_standard'
   AND template_id = 'mt_espresso_brew_pressure_test';

-- 3. Live schedules still on the old default — bump them in place.
-- Schedules where the operator changed cadence (anything other than
-- monthly+1) get LEFT ALONE so user customization is preserved.
UPDATE public.equipment_schedule
   SET frequency_type     = 'quarterly',
       frequency_interval = 1,
       updated_at         = now()
 WHERE template_id        = 'mt_espresso_brew_pressure_test'
   AND frequency_type     = 'monthly'
   AND frequency_interval = 1;
