-- ============================================================
-- Refined + expanded maintenance templates (Phase 8.1)
-- ============================================================
-- Adds ~25 more granular templates so programs can subscribe to the
-- specific tasks that match their cadence vs lumping things together.
--
-- Research base: SCA Technical Standards, manufacturer service
-- intervals (La Marzocco PB / Slayer / Probat L / Loring S15 manuals),
-- Specialty Coffee Forum + Home-Barista commercial threads, Bay Coffee
-- Service published intervals.
--
-- Key principle: client-side daily/weekly tasks are
-- is_recommended_only=true (shown as guidance to operators, not
-- scheduled). Operator-tracked tasks start at monthly+ for shop gear
-- but at daily for in-house roasters (where the operator IS doing
-- those checks).
--
-- Safe to re-run — uses ON CONFLICT DO NOTHING on template_id.
-- ============================================================

INSERT INTO public.maintenance_template
  (template_id, category, task_name, description, frequency_type, frequency_interval,
   is_recommended_only, is_critical, estimated_minutes, parts_typically_needed, tools_needed)
VALUES

  -- ============================================================
  -- ESPRESSO MACHINE — added granularity
  -- ============================================================
  ('mt_espresso_drip_tray',          'espresso_machine', 'Empty + scrub drip tray',
    'End-of-day: pull drip tray, scrub grates, flush drain, sanitize.',
    'daily', 1, true, false, 5, NULL, NULL),

  ('mt_espresso_portafilter_soak',   'espresso_machine', 'Soak portafilters in detergent',
    'Remove baskets + spouts. Soak in hot water + Cafiza for 30 min. Rinse + dry.',
    'weekly', 1, true, false, 35,
    '[{"name":"Cafiza or equivalent espresso machine detergent"}]'::jsonb,
    '[{"name":"Soaking container"}]'::jsonb),

  ('mt_espresso_grouphead_brush',    'espresso_machine', 'Brush group head + screws',
    'Remove shower screen, brush group head interior + screw threads with group brush.',
    'weekly', 1, true, false, 10, NULL,
    '[{"name":"Group brush (one per group)"}]'::jsonb),

  ('mt_espresso_brew_pressure_test', 'espresso_machine', 'Verify brew pressure (9 bar)',
    'With blind basket, lock + start brew. Pressure gauge should sit at 9 bar steady. Adjust pump if drift > 0.3 bar.',
    'monthly', 1, false, false, 10, NULL,
    '[{"name":"Blind basket"}]'::jsonb),

  ('mt_espresso_steam_pressure_test','espresso_machine', 'Verify steam pressure (1-1.5 bar)',
    'Check boiler steam pressure at idle. Within 1.0-1.5 bar for most machines. Adjust pressurestat if off.',
    'monthly', 1, false, false, 10, NULL, NULL),

  ('mt_espresso_drain_clear',        'espresso_machine', 'Clear drip tray drain',
    'Inspect drain for scale buildup. Flush with descaler if slow flow.',
    'monthly', 1, false, false, 15, NULL, NULL),

  ('mt_espresso_baskets_rim_check',  'espresso_machine', 'Inspect baskets for rim wear',
    'Check basket rims for deformation (worn rim = bad seal = side channeling). Replace if visibly worn.',
    'semi_annual', 1, false, false, 10,
    '[{"name":"Replacement baskets if needed"}]'::jsonb, NULL),

  ('mt_espresso_pressure_relief',    'espresso_machine', 'Test pressure relief valve',
    'Verify expansion valve releases at spec pressure. Critical for boiler safety.',
    'semi_annual', 1, false, true, 15, NULL, NULL),

  ('mt_espresso_volumetric_check',   'espresso_machine', 'Calibrate volumetric flow meters',
    'For machines with volumetric buttons: verify each button delivers consistent shot weight. Recalibrate as needed.',
    'semi_annual', 1, false, false, 30, NULL,
    '[{"name":"Scale"}]'::jsonb),

  ('mt_espresso_temp_calibration',   'espresso_machine', 'Calibrate brew temperature',
    'Use a temperature device in the basket. Should match displayed setpoint ± 1°F. Adjust PID if drift.',
    'annual', 1, false, false, 30, NULL,
    '[{"name":"Scace device or thermometer with basket adapter"}]'::jsonb),


  -- ============================================================
  -- GRINDER — added granularity
  -- ============================================================
  ('mt_grinder_static_clean',        'grinder', 'Clean static reducer / RDT',
    'Wipe down any static reducer plate. If using RDT (water spray), clean nozzle + reservoir.',
    'weekly', 1, true, false, 5, NULL, NULL),

  ('mt_grinder_motor_mount',         'grinder', 'Inspect motor mount + vibration',
    'Run motor unloaded. Listen for new noise, feel for unusual vibration. Tighten mount bolts if loose.',
    'monthly', 1, false, false, 10, NULL, NULL),

  ('mt_grinder_burr_deep_clean',     'grinder', 'Disassemble + deep clean burrs',
    'Remove top burr carrier, vacuum + brush both burrs, clean threads, inspect edges for chipping.',
    'quarterly', 1, false, false, 30, NULL,
    '[{"name":"Vacuum"}, {"name":"Burr brush"}]'::jsonb),

  ('mt_grinder_thread_lube',         'grinder', 'Lubricate burr adjustment threads',
    'Apply food-safe grease to upper burr carrier threads. Sticky threads = wandering grind size.',
    'quarterly', 1, false, false, 10,
    '[{"name":"Food-safe grease (NSF H1)"}]'::jsonb, NULL),

  ('mt_grinder_motor_brushes',       'grinder', 'Inspect / replace motor brushes',
    'Commercial brushed motors: pull caps, measure brush length. Replace if < 5mm remaining.',
    'annual', 1, false, false, 30,
    '[{"name":"Motor brushes (model-specific)"}]'::jsonb, NULL),


  -- ============================================================
  -- ROASTER — added daily/weekly OPERATOR-tracked tasks
  -- (different from espresso side: these ARE tracked because the
  -- operator is the one doing them; client-recommended doesn't apply)
  -- ============================================================
  ('mt_roaster_sight_glass',         'roaster', 'Wipe sight glass / trier',
    'Wipe interior of sight glass with dry cloth at start + end of session. Pull trier, brush, replace.',
    'daily', 1, false, false, 3, NULL, NULL),

  ('mt_roaster_hopper_clean',        'roaster', 'Empty + wipe loading hopper',
    'Empty residual greens, wipe out chaff/fines that fall back into the hopper from the drum entry.',
    'daily', 1, false, false, 5, NULL, NULL),

  ('mt_roaster_floor_sweep',         'roaster', 'Sweep floor around roaster',
    'Chaff + bean fragments accumulate beneath. Sweep daily — chaff on floor + heat source = fire risk.',
    'daily', 1, false, true, 5, NULL, NULL),

  ('mt_roaster_cyclone_vacuum',      'roaster', 'Vacuum chaff cyclone interior',
    'Daily empty isn''t enough — chaff sticks to cyclone walls. Vacuum the interior thoroughly. CRITICAL.',
    'weekly', 1, false, true, 15, NULL,
    '[{"name":"Shop vacuum"}]'::jsonb),

  ('mt_roaster_under_vacuum',        'roaster', 'Vacuum under + behind roaster',
    'Pull roaster forward if accessible. Vacuum chaff, beans, dust. Inspect floor for scorching.',
    'weekly', 1, false, true, 20, NULL,
    '[{"name":"Shop vacuum"}]'::jsonb),

  ('mt_roaster_exhaust_temp_trend',  'roaster', 'Compare exhaust temp to baseline',
    'Note ET trend across the week. Rising trend at same charge weight = chaff buildup in exhaust = clean ductwork sooner.',
    'weekly', 1, false, false, 5, NULL, NULL),

  ('mt_roaster_drum_rotation',       'roaster', 'Check drum rotation (no wobble)',
    'Run drum unloaded with cover off. Watch for wobble, listen for bearing noise. Smooth + quiet = healthy.',
    'weekly', 1, false, true, 5, NULL, NULL),

  ('mt_roaster_damper_actuation',    'roaster', 'Test damper full-range actuation',
    'Cycle damper from full open to full closed. Should move smoothly with no stops. Sticky damper = uneven airflow.',
    'weekly', 1, false, false, 5, NULL, NULL),

  ('mt_roaster_ductwork_inspect',    'roaster', 'Visual inspect exhaust ductwork joints',
    'Walk the duct path looking for sagging, gaps, or visible chaff accumulation at joints. FIRE RISK.',
    'monthly', 1, false, true, 15, NULL, NULL),

  ('mt_roaster_afterburner_check',   'roaster', 'Afterburner inspection (if equipped)',
    'Visual inspection of afterburner refractory + ignition. Critical for emissions compliance + fire prevention.',
    'monthly', 1, false, true, 20, NULL, NULL),

  ('mt_roaster_drum_entry_chute',    'roaster', 'Clean drum entry chute',
    'Brush + vacuum the chute between hopper and drum. Buildup causes uneven feed.',
    'monthly', 1, false, false, 10, NULL, NULL),

  ('mt_roaster_motor_compartment',   'roaster', 'Vacuum motor compartment',
    'Open motor cover, vacuum dust + chaff. Dust on hot motor = fire risk + premature failure.',
    'quarterly', 1, false, true, 15, NULL, NULL),

  ('mt_roaster_safety_interlocks',   'roaster', 'Test safety interlocks',
    'Door switch should cut drum motor when opened. Drum rotation safety should cut gas if drum stops.',
    'quarterly', 1, false, true, 15, NULL, NULL),

  ('mt_roaster_thermocouple_wire',   'roaster', 'Check thermocouple wire integrity',
    'Inspect TC wire insulation for cracks, melted spots. Wire failure = bad temp readings = bad roasts.',
    'quarterly', 1, false, false, 10, NULL, NULL),

  ('mt_roaster_drum_bearing_play',   'roaster', 'Check drum bearings for play',
    'With drum off, grip face plate + try to rock drum axially + radially. Any noticeable play = bearings due.',
    'semi_annual', 1, false, true, 15, NULL, NULL),

  ('mt_roaster_exhaust_fan_inspect', 'roaster', 'Inspect exhaust fan blade',
    'Pull access cover. Look for chaff buildup on blade (causes imbalance + vibration), check blade integrity.',
    'semi_annual', 1, false, true, 30, NULL,
    '[{"name":"Vacuum"}, {"name":"Brush"}]'::jsonb),

  ('mt_roaster_flame_pattern',       'roaster', 'Verify burner flame pattern',
    'With burner running mid-cycle, look at flame: clear blue cones with sharp tips. Yellow tips = dirty orifice or air supply issue.',
    'quarterly', 1, false, true, 10, NULL, NULL),

  ('mt_roaster_electrical_inspect',  'roaster', 'Electrical panel inspection',
    'Check for loose lugs, corrosion, signs of arcing. Verify ground continuity. Typically done by certified tech.',
    'annual', 1, false, true, 60, NULL, NULL),

  ('mt_roaster_high_limit_test',     'roaster', 'Test high-limit safety',
    'Verify high-limit shuts gas valve at spec temperature. Critical safety device.',
    'annual', 1, false, true, 15, NULL, NULL)

ON CONFLICT (template_id) DO NOTHING;
