-- ============================================================
-- Refined maintenance programs — researched bundles (Phase 8.2)
-- ============================================================
-- Rewrites the 5 global programs with:
--   - Industry-validated task selection per program
--   - Cadence overrides that actually make sense per program tier
--     (Premium = tighter cadence on the SAME tasks, not different tasks)
--   - More granular task assignments using the templates added in
--     migration ..015 — so a Premium espresso program can monthly
--     check brew pressure where Standard only checks quarterly
--
-- Sources:
--   SCA Technical Standards (Specialty Coffee Association)
--   La Marzocco Linea PB Service Manual
--   Slayer Espresso Service Schedule
--   Probat L-series + Loring S15 service intervals
--   Bay Coffee Service published cadences for commercial accounts
--   Mahlkönig EK / E80 / Mazzer Major commercial service intervals
--
-- Safe to re-run: DELETE+INSERT scoped to global programs only.
-- ============================================================

-- Wipe global program bundles (tenant programs untouched)
DELETE FROM public.maintenance_program_template
  WHERE program_id IN (
    SELECT program_id FROM public.maintenance_program WHERE company_id IS NULL
  );


-- ============================================================
-- ESPRESSO BAR — STANDARD PM  (most cafes, single bar, < 200 drinks/day)
-- ============================================================
INSERT INTO public.maintenance_program_template (program_id, template_id, frequency_type, frequency_interval) VALUES
  -- Monthly checks the bartender or shop owner can do
  ('pgm_espresso_standard', 'mt_espresso_brew_pressure_test',  'monthly',     1),
  ('pgm_espresso_standard', 'mt_espresso_steam_pressure_test', 'monthly',     1),
  ('pgm_espresso_standard', 'mt_espresso_drain_clear',         'monthly',     1),
  -- Quarterly shower screens (every 3 months is fine for low-volume)
  ('pgm_espresso_standard', 'mt_espresso_shower_screens',      'quarterly',   1),
  -- Semi-annual: gaskets + basket wear check
  ('pgm_espresso_standard', 'mt_espresso_group_gaskets',       'semi_annual', 1),
  ('pgm_espresso_standard', 'mt_espresso_baskets_rim_check',   'semi_annual', 1),
  ('pgm_espresso_standard', 'mt_espresso_pressure_relief',     'semi_annual', 1),
  -- Annual: descale + filter + full PM (usually a service-tech visit)
  ('pgm_espresso_standard', 'mt_espresso_boiler_descale',      'annual',      1),
  ('pgm_espresso_standard', 'mt_espresso_water_filter',        'annual',      1),
  ('pgm_espresso_standard', 'mt_espresso_temp_calibration',    'annual',      1),
  ('pgm_espresso_standard', 'mt_espresso_pm_service',          'annual',      1);


-- ============================================================
-- ESPRESSO BAR — PREMIUM PM (high-volume specialty, > 200 drinks/day)
-- Same tasks, tighter intervals + a few extras Standard skips.
-- ============================================================
INSERT INTO public.maintenance_program_template (program_id, template_id, frequency_type, frequency_interval) VALUES
  -- Weekly pressure check (vs monthly for Standard)
  ('pgm_espresso_premium', 'mt_espresso_brew_pressure_test',   'weekly',      1),
  ('pgm_espresso_premium', 'mt_espresso_steam_pressure_test',  'monthly',     1),
  ('pgm_espresso_premium', 'mt_espresso_drain_clear',          'monthly',     1),
  -- Monthly shower screens (vs quarterly)
  ('pgm_espresso_premium', 'mt_espresso_shower_screens',       'monthly',     1),
  -- Quarterly gaskets (vs semi-annual)
  ('pgm_espresso_premium', 'mt_espresso_group_gaskets',        'quarterly',   1),
  ('pgm_espresso_premium', 'mt_espresso_baskets_rim_check',    'quarterly',   1),
  ('pgm_espresso_premium', 'mt_espresso_volumetric_check',     'quarterly',   1),  -- extra
  ('pgm_espresso_premium', 'mt_espresso_pressure_relief',      'semi_annual', 1),
  -- Semi-annual descale + filter (vs annual)
  ('pgm_espresso_premium', 'mt_espresso_boiler_descale',       'semi_annual', 1),
  ('pgm_espresso_premium', 'mt_espresso_water_filter',         'quarterly',   1),  -- quarterly!
  ('pgm_espresso_premium', 'mt_espresso_temp_calibration',     'semi_annual', 1),
  -- Semi-annual full PM (vs annual)
  ('pgm_espresso_premium', 'mt_espresso_pm_service',           'semi_annual', 1);


-- ============================================================
-- GRINDER — STANDARD PM
-- Same for both shop + production grinders; commercial cadence
-- ============================================================
INSERT INTO public.maintenance_program_template (program_id, template_id, frequency_type, frequency_interval) VALUES
  -- Monthly
  ('pgm_grinder_standard', 'mt_grinder_cleaning_tablets',     'monthly',     1),
  ('pgm_grinder_standard', 'mt_grinder_motor_mount',          'monthly',     1),
  -- Quarterly
  ('pgm_grinder_standard', 'mt_grinder_burr_align',           'quarterly',   1),
  ('pgm_grinder_standard', 'mt_grinder_burr_deep_clean',      'quarterly',   1),
  ('pgm_grinder_standard', 'mt_grinder_thread_lube',          'quarterly',   1),
  -- Annual
  ('pgm_grinder_standard', 'mt_grinder_motor_brushes',        'annual',      1),
  -- Usage-based burr replacement (the volume number stays the model
  -- default — overrides happen per-equipment if needed)
  ('pgm_grinder_standard', 'mt_grinder_burr_replace_lbs',     'lbs_processed', 1000);


-- ============================================================
-- ROASTER — STANDARD PM  (1-2 batches/day, ~10-20 batches/week)
-- All operator-tracked; everything daily/weekly is REAL work
-- the operator needs to do or risks fire + bad roasts.
-- ============================================================
INSERT INTO public.maintenance_program_template (program_id, template_id, frequency_type, frequency_interval) VALUES
  -- Daily (yes daily — these are the operator's actual job)
  ('pgm_roaster_standard', 'mt_roaster_chaff_collector',      'daily',       1),
  ('pgm_roaster_standard', 'mt_roaster_drum_brush',           'daily',       1),
  ('pgm_roaster_standard', 'mt_roaster_cooling_tray',         'daily',       1),
  ('pgm_roaster_standard', 'mt_roaster_sight_glass',          'daily',       1),
  ('pgm_roaster_standard', 'mt_roaster_hopper_clean',         'daily',       1),
  ('pgm_roaster_standard', 'mt_roaster_floor_sweep',          'daily',       1),
  -- Weekly
  ('pgm_roaster_standard', 'mt_roaster_gas_pressure_check',   'weekly',      1),
  ('pgm_roaster_standard', 'mt_roaster_cyclone_vacuum',       'weekly',      1),
  ('pgm_roaster_standard', 'mt_roaster_under_vacuum',         'weekly',      1),
  ('pgm_roaster_standard', 'mt_roaster_exhaust_temp_trend',   'weekly',      1),
  ('pgm_roaster_standard', 'mt_roaster_drum_rotation',        'weekly',      1),
  ('pgm_roaster_standard', 'mt_roaster_damper_actuation',     'weekly',      1),
  -- Monthly
  ('pgm_roaster_standard', 'mt_roaster_exhaust_fan',          'monthly',     1),
  ('pgm_roaster_standard', 'mt_roaster_thermocouple_check',   'monthly',     1),
  ('pgm_roaster_standard', 'mt_roaster_ductwork_inspect',     'monthly',     1),
  ('pgm_roaster_standard', 'mt_roaster_afterburner_check',    'monthly',     1),
  ('pgm_roaster_standard', 'mt_roaster_drum_entry_chute',     'monthly',     1),
  -- Quarterly
  ('pgm_roaster_standard', 'mt_roaster_bearing_grease',       'quarterly',   1),
  ('pgm_roaster_standard', 'mt_roaster_chain_tension',        'quarterly',   1),
  ('pgm_roaster_standard', 'mt_roaster_motor_compartment',    'quarterly',   1),
  ('pgm_roaster_standard', 'mt_roaster_safety_interlocks',    'quarterly',   1),
  ('pgm_roaster_standard', 'mt_roaster_thermocouple_wire',    'quarterly',   1),
  ('pgm_roaster_standard', 'mt_roaster_flame_pattern',        'quarterly',   1),
  -- Semi-annual
  ('pgm_roaster_standard', 'mt_roaster_drum_bearing_play',    'semi_annual', 1),
  ('pgm_roaster_standard', 'mt_roaster_exhaust_fan_inspect',  'semi_annual', 1),
  -- Annual
  ('pgm_roaster_standard', 'mt_roaster_gasket_replace',       'annual',      1),
  ('pgm_roaster_standard', 'mt_roaster_burner_clean',         'annual',      1),
  ('pgm_roaster_standard', 'mt_roaster_electrical_inspect',   'annual',      1),
  ('pgm_roaster_standard', 'mt_roaster_high_limit_test',      'annual',      1),
  ('pgm_roaster_standard', 'mt_roaster_full_pm',              'annual',      1);


-- ============================================================
-- ROASTER — HEAVY USE PM  (5+ batches/day, 30+ batches/week)
-- Same task list, tightened cadences. Chaff cleanout moves to
-- per-batch (lbs-based) instead of daily because at heavy volume
-- the cyclone fills before EOD.
-- ============================================================
INSERT INTO public.maintenance_program_template (program_id, template_id, frequency_type, frequency_interval) VALUES
  -- Chaff: usage-based vs daily
  ('pgm_roaster_heavy', 'mt_roaster_chaff_batches',           'lbs_processed', 100),
  -- Daily basics still daily
  ('pgm_roaster_heavy', 'mt_roaster_drum_brush',              'daily',       1),
  ('pgm_roaster_heavy', 'mt_roaster_cooling_tray',            'daily',       1),
  ('pgm_roaster_heavy', 'mt_roaster_sight_glass',             'daily',       1),
  ('pgm_roaster_heavy', 'mt_roaster_hopper_clean',            'daily',       1),
  ('pgm_roaster_heavy', 'mt_roaster_floor_sweep',             'daily',       1),
  -- Daily exhaust check (vs weekly for Standard) — heavy use = high creosote risk
  ('pgm_roaster_heavy', 'mt_roaster_exhaust_temp_trend',      'daily',       1),
  ('pgm_roaster_heavy', 'mt_roaster_damper_actuation',        'daily',       1),
  ('pgm_roaster_heavy', 'mt_roaster_drum_rotation',           'daily',       1),
  -- Weekly (tighter than Standard's weekly+)
  ('pgm_roaster_heavy', 'mt_roaster_gas_pressure_check',      'weekly',      1),
  ('pgm_roaster_heavy', 'mt_roaster_cyclone_vacuum',          'weekly',      1),
  ('pgm_roaster_heavy', 'mt_roaster_under_vacuum',            'weekly',      1),
  ('pgm_roaster_heavy', 'mt_roaster_thermocouple_check',      'weekly',      1),  -- weekly vs monthly
  ('pgm_roaster_heavy', 'mt_roaster_ductwork_inspect',        'weekly',      1),  -- weekly vs monthly
  -- Monthly (tightened)
  ('pgm_roaster_heavy', 'mt_roaster_exhaust_fan',             'monthly',     1),
  ('pgm_roaster_heavy', 'mt_roaster_afterburner_check',       'monthly',     1),
  ('pgm_roaster_heavy', 'mt_roaster_drum_entry_chute',        'monthly',     1),
  ('pgm_roaster_heavy', 'mt_roaster_bearing_grease',          'monthly',     1),  -- monthly vs quarterly
  ('pgm_roaster_heavy', 'mt_roaster_motor_compartment',       'monthly',     1),  -- monthly vs quarterly
  ('pgm_roaster_heavy', 'mt_roaster_thermocouple_wire',       'monthly',     1),  -- monthly vs quarterly
  ('pgm_roaster_heavy', 'mt_roaster_flame_pattern',           'monthly',     1),  -- monthly vs quarterly
  -- Quarterly (tightened)
  ('pgm_roaster_heavy', 'mt_roaster_chain_tension',           'quarterly',   1),
  ('pgm_roaster_heavy', 'mt_roaster_safety_interlocks',       'quarterly',   1),
  ('pgm_roaster_heavy', 'mt_roaster_drum_bearing_play',       'quarterly',   1),  -- quarterly vs semi
  ('pgm_roaster_heavy', 'mt_roaster_exhaust_fan_inspect',     'quarterly',   1),  -- quarterly vs semi
  ('pgm_roaster_heavy', 'mt_roaster_burner_clean',            'quarterly',   1),  -- quarterly vs annual
  -- Semi-annual
  ('pgm_roaster_heavy', 'mt_roaster_gasket_replace',          'semi_annual', 1),  -- semi vs annual
  ('pgm_roaster_heavy', 'mt_roaster_electrical_inspect',      'semi_annual', 1),
  -- Annual
  ('pgm_roaster_heavy', 'mt_roaster_high_limit_test',         'annual',      1),
  ('pgm_roaster_heavy', 'mt_roaster_full_pm',                 'annual',      1);
