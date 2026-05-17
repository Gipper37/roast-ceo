-- ============================================================
-- Equipment overhaul (Phase 10.1)
-- ============================================================
-- Per audit: programs renamed by output tier, descriptions cut to
-- just volume bracket, Light tier added, Heavy → High Output, floor
-- sweep removed (operational hygiene, not PM), chaff cleanout removed
-- from programs (already tracked in roast_log), and usage_suggested
-- columns added to maintenance_template so the cadence editor can
-- show "We suggest: every X lbs" when an operator flips a time-based
-- task to usage-based.
-- ============================================================


-- ────────────────────────────────────────────────────────────────
-- A) Suggested usage intervals on templates
-- ────────────────────────────────────────────────────────────────
ALTER TABLE public.maintenance_template
  ADD COLUMN IF NOT EXISTS usage_suggested_lbs     numeric,
  ADD COLUMN IF NOT EXISTS usage_suggested_batches numeric,
  ADD COLUMN IF NOT EXISTS usage_suggested_hours   numeric;

COMMENT ON COLUMN public.maintenance_template.usage_suggested_lbs IS
  'Hint shown in the cadence editor when an operator flips this task to lbs_processed mode. Volume-based wear estimates are industry-validated baselines; operators tune from there.';


-- Roaster usage suggestions (industry baselines)
UPDATE public.maintenance_template SET usage_suggested_lbs = 3500  WHERE template_id = 'mt_roaster_gasket_replace';
UPDATE public.maintenance_template SET usage_suggested_lbs = 3000  WHERE template_id = 'mt_roaster_bearing_grease';
UPDATE public.maintenance_template SET usage_suggested_lbs = 5000  WHERE template_id = 'mt_roaster_chain_tension';
UPDATE public.maintenance_template SET usage_suggested_lbs = 5000  WHERE template_id = 'mt_roaster_burner_clean';
UPDATE public.maintenance_template SET usage_suggested_lbs = 8000  WHERE template_id = 'mt_roaster_drum_bearing_play';
UPDATE public.maintenance_template SET usage_suggested_lbs = 10000 WHERE template_id = 'mt_roaster_full_pm';


-- ────────────────────────────────────────────────────────────────
-- B) Remove floor sweep (operational hygiene, not maintenance)
-- ────────────────────────────────────────────────────────────────
DELETE FROM public.maintenance_program_template WHERE template_id = 'mt_roaster_floor_sweep';
DELETE FROM public.maintenance_template WHERE template_id = 'mt_roaster_floor_sweep';


-- ────────────────────────────────────────────────────────────────
-- C) Remove chaff cleanout from programs (already tracked in roast_log)
-- Leave the templates in the catalog so an operator can still opt
-- in explicitly via ad-hoc add — but no program auto-stamps it.
-- ────────────────────────────────────────────────────────────────
DELETE FROM public.maintenance_program_template
 WHERE template_id IN ('mt_roaster_chaff_collector', 'mt_roaster_chaff_batches');


-- ────────────────────────────────────────────────────────────────
-- D) Rename Heavy → High Output + collapse descriptions to volume only
-- ────────────────────────────────────────────────────────────────
UPDATE public.maintenance_program
   SET name = 'Roaster — High Output PM',
       description = 'High-output wholesale operations — 100+ batches/week (~5,500+ lbs/wk).'
 WHERE program_id = 'pgm_roaster_heavy';

UPDATE public.maintenance_program
   SET description = 'Most independent roasters — 25-100 batches/week (~1,400-5,500 lbs/wk).'
 WHERE program_id = 'pgm_roaster_standard';

UPDATE public.maintenance_program
   SET description = 'Most cafes — typical single-bar shop, < 200 drinks/day.'
 WHERE program_id = 'pgm_espresso_standard';

UPDATE public.maintenance_program
   SET description = 'High-volume specialty cafes — 200+ drinks/day, multi-bar or competition-level shops.'
 WHERE program_id = 'pgm_espresso_premium';

UPDATE public.maintenance_program
   SET description = 'Commercial grinders, all volumes. Burr replacement scales with lbs ground.'
 WHERE program_id = 'pgm_grinder_standard';


-- ────────────────────────────────────────────────────────────────
-- E) NEW: Light roaster program
-- For sample roasters, micro shops, and occasional production
-- (< 25 batches/week, ~< 1,400 lbs/wk). Looser cadences on the same
-- task set; daily tasks stay daily because they happen on roast days
-- regardless of volume.
-- ────────────────────────────────────────────────────────────────
INSERT INTO public.maintenance_program (program_id, name, description, category, is_active)
VALUES
  ('pgm_roaster_light', 'Roaster — Light Use PM',
    'Sample roasters, micro shops, occasional production — under 25 batches/week (~< 1,400 lbs/wk).',
    'roaster', true)
ON CONFLICT (program_id) DO UPDATE
  SET name = EXCLUDED.name, description = EXCLUDED.description, category = EXCLUDED.category;


INSERT INTO public.maintenance_program_template (program_id, template_id, frequency_type, frequency_interval) VALUES
  -- Daily (on roast days; same as Standard for hygiene-critical tasks)
  ('pgm_roaster_light', 'mt_roaster_drum_brush',          'daily',       1),
  ('pgm_roaster_light', 'mt_roaster_cooling_tray',        'daily',       1),
  ('pgm_roaster_light', 'mt_roaster_sight_glass',         'daily',       1),
  ('pgm_roaster_light', 'mt_roaster_hopper_clean',        'daily',       1),

  -- Weekly
  ('pgm_roaster_light', 'mt_roaster_gas_pressure_check',  'weekly',      1),
  ('pgm_roaster_light', 'mt_roaster_drum_rotation',       'weekly',      1),
  ('pgm_roaster_light', 'mt_roaster_damper_actuation',    'weekly',      1),

  -- Monthly (lighter cadence — pushed out from Standard's weekly cyclone)
  ('pgm_roaster_light', 'mt_roaster_cyclone_vacuum',      'monthly',     1),
  ('pgm_roaster_light', 'mt_roaster_under_vacuum',        'monthly',     1),
  ('pgm_roaster_light', 'mt_roaster_exhaust_temp_trend',  'monthly',     1),
  ('pgm_roaster_light', 'mt_roaster_thermocouple_check',  'monthly',     1),

  -- Quarterly
  ('pgm_roaster_light', 'mt_roaster_exhaust_fan',         'quarterly',   1),
  ('pgm_roaster_light', 'mt_roaster_ductwork_inspect',    'quarterly',   1),
  ('pgm_roaster_light', 'mt_roaster_drum_entry_chute',    'quarterly',   1),

  -- Semi-annual (vs Standard's quarterly — light use = wear slower)
  ('pgm_roaster_light', 'mt_roaster_bearing_grease',      'semi_annual', 1),
  ('pgm_roaster_light', 'mt_roaster_chain_tension',       'semi_annual', 1),
  ('pgm_roaster_light', 'mt_roaster_motor_compartment',   'semi_annual', 1),
  ('pgm_roaster_light', 'mt_roaster_safety_interlocks',   'semi_annual', 1),
  ('pgm_roaster_light', 'mt_roaster_thermocouple_wire',   'semi_annual', 1),
  ('pgm_roaster_light', 'mt_roaster_flame_pattern',       'semi_annual', 1),
  ('pgm_roaster_light', 'mt_roaster_afterburner_check',   'semi_annual', 1),

  -- Annual (still annual — safety + warranty intervals are calendar-based)
  ('pgm_roaster_light', 'mt_roaster_drum_bearing_play',   'annual',      1),
  ('pgm_roaster_light', 'mt_roaster_exhaust_fan_inspect', 'annual',      1),
  ('pgm_roaster_light', 'mt_roaster_gasket_replace',      'annual',      1),
  ('pgm_roaster_light', 'mt_roaster_burner_clean',        'annual',      1),
  ('pgm_roaster_light', 'mt_roaster_electrical_inspect',  'annual',      1),
  ('pgm_roaster_light', 'mt_roaster_high_limit_test',     'annual',      1),
  ('pgm_roaster_light', 'mt_roaster_full_pm',             'annual',      1)
ON CONFLICT (program_id, template_id) DO UPDATE
  SET frequency_type = EXCLUDED.frequency_type, frequency_interval = EXCLUDED.frequency_interval;
