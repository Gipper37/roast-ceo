-- ============================================================
-- Seed 5 global maintenance programs + their template bundles
-- ============================================================
-- A program = curated bundle of templates. Subscribing equipment to
-- a program is a one-click way to apply an industry-standard cadence
-- without picking individual tasks.
--
-- Programs seeded (5):
--   1. Espresso Bar — Standard PM   (most cafes)
--   2. Espresso Bar — Premium PM    (high-volume / specialty)
--   3. Grinder — Standard PM
--   4. Roaster — Standard PM        (operator's own roaster)
--   5. Roaster — Heavy Use PM       (5+ batches/day operations)
--
-- Safe to re-run: DELETE+INSERT pattern, scoped to globals only.
-- ============================================================

-- Reset global programs (tenant-owned ones are untouched)
DELETE FROM public.maintenance_program_template
  WHERE program_id IN (
    SELECT program_id FROM public.maintenance_program WHERE company_id IS NULL
  );
DELETE FROM public.maintenance_program WHERE company_id IS NULL;

INSERT INTO public.maintenance_program (program_id, name, description, category) VALUES
  ('pgm_espresso_standard', 'Espresso Bar — Standard PM',
    'Monthly shower screens, semi-annual gaskets, annual full PM. The baseline for most cafes.',
    'espresso_machine'),
  ('pgm_espresso_premium', 'Espresso Bar — Premium PM',
    'Tighter cadence for high-volume specialty shops: quarterly gaskets, quarterly water filter, semi-annual full PM.',
    'espresso_machine'),
  ('pgm_grinder_standard', 'Grinder — Standard PM',
    'Monthly burr cleaning, quarterly alignment check, burr replacement at lifespan.',
    'grinder'),
  ('pgm_roaster_standard', 'Roaster — Standard PM',
    'Operator''s own roaster, normal production (1-2 batches/day). Daily chaff + drum, weekly gas, monthly exhaust/thermo, quarterly bearings, annual gaskets + full PM.',
    'roaster'),
  ('pgm_roaster_heavy', 'Roaster — Heavy Use PM',
    'High-output roasters (5+ batches/day). Per-batch chaff cleanout, weekly thermo check, quarterly exhaust, semi-annual gaskets + bearings, annual full PM.',
    'roaster');


-- ────────────────────────────────────────────────────────────────
-- Espresso Bar — Standard PM
-- ────────────────────────────────────────────────────────────────
INSERT INTO public.maintenance_program_template (program_id, template_id)
SELECT 'pgm_espresso_standard', template_id
FROM public.maintenance_template
WHERE template_id IN (
  'mt_espresso_shower_screens',
  'mt_espresso_group_gaskets',
  'mt_espresso_boiler_descale',
  'mt_espresso_water_filter',
  'mt_espresso_pm_service'
);

-- Espresso Premium — same templates but with tightened intervals via override
INSERT INTO public.maintenance_program_template
  (program_id, template_id, frequency_type, frequency_interval)
VALUES
  ('pgm_espresso_premium', 'mt_espresso_shower_screens', 'monthly',     1),  -- monthly instead of every-3-months
  ('pgm_espresso_premium', 'mt_espresso_group_gaskets',  'quarterly',   1),  -- quarterly instead of semi-annual
  ('pgm_espresso_premium', 'mt_espresso_boiler_descale', 'semi_annual', 1),  -- 2x/year instead of annual
  ('pgm_espresso_premium', 'mt_espresso_water_filter',   'quarterly',   1),  -- quarterly instead of annual
  ('pgm_espresso_premium', 'mt_espresso_pm_service',     'semi_annual', 1);  -- 2x/year instead of annual


-- ────────────────────────────────────────────────────────────────
-- Grinder — Standard PM
-- ────────────────────────────────────────────────────────────────
INSERT INTO public.maintenance_program_template (program_id, template_id)
SELECT 'pgm_grinder_standard', template_id
FROM public.maintenance_template
WHERE template_id IN (
  'mt_grinder_cleaning_tablets',
  'mt_grinder_burr_align',
  'mt_grinder_burr_replace_lbs'
);


-- ────────────────────────────────────────────────────────────────
-- Roaster — Standard PM (in-house, operator-tracked)
-- ────────────────────────────────────────────────────────────────
INSERT INTO public.maintenance_program_template (program_id, template_id)
SELECT 'pgm_roaster_standard', template_id
FROM public.maintenance_template
WHERE template_id IN (
  'mt_roaster_chaff_collector',
  'mt_roaster_drum_brush',
  'mt_roaster_cooling_tray',
  'mt_roaster_gas_pressure_check',
  'mt_roaster_exhaust_fan',
  'mt_roaster_thermocouple_check',
  'mt_roaster_bearing_grease',
  'mt_roaster_chain_tension',
  'mt_roaster_gasket_replace',
  'mt_roaster_burner_clean',
  'mt_roaster_full_pm'
);


-- ────────────────────────────────────────────────────────────────
-- Roaster — Heavy Use PM (tightened cadences)
-- ────────────────────────────────────────────────────────────────
INSERT INTO public.maintenance_program_template
  (program_id, template_id, frequency_type, frequency_interval)
VALUES
  -- Chaff: use the lbs-based template instead of daily, every 100 lbs (twice/day for a heavy shop)
  ('pgm_roaster_heavy', 'mt_roaster_chaff_batches',      'lbs_processed', 100),
  ('pgm_roaster_heavy', 'mt_roaster_drum_brush',         'daily',         1),
  ('pgm_roaster_heavy', 'mt_roaster_cooling_tray',       'daily',         1),
  ('pgm_roaster_heavy', 'mt_roaster_gas_pressure_check', 'weekly',        1),
  ('pgm_roaster_heavy', 'mt_roaster_thermocouple_check', 'weekly',        1),  -- weekly (vs monthly)
  ('pgm_roaster_heavy', 'mt_roaster_exhaust_fan',        'quarterly',     1),  -- quarterly (vs monthly)
  ('pgm_roaster_heavy', 'mt_roaster_bearing_grease',     'semi_annual',   1),  -- 2x/year
  ('pgm_roaster_heavy', 'mt_roaster_chain_tension',      'quarterly',     1),
  ('pgm_roaster_heavy', 'mt_roaster_gasket_replace',     'semi_annual',   1),  -- 2x/year
  ('pgm_roaster_heavy', 'mt_roaster_burner_clean',       'semi_annual',   1),
  ('pgm_roaster_heavy', 'mt_roaster_full_pm',            'annual',        1);
