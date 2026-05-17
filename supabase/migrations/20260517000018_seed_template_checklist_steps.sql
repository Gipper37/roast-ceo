-- ============================================================
-- Seed checklist steps for high-value maintenance templates
-- ============================================================
-- Picks the templates where a real checklist + measurements add the
-- most operator value: full PMs, descales, pressure tests, roaster
-- monthly+ tasks. Daily client-recommended tasks generally don't need
-- steps — they're done as a single action.
--
-- Idempotent: DELETE+INSERT scoped to steps where template is global.
-- ============================================================

DELETE FROM public.maintenance_template_step
  WHERE template_id IN (SELECT template_id FROM public.maintenance_template WHERE company_id IS NULL);


-- ============================================================
-- ESPRESSO — annual PM service (the big one)
-- ============================================================
INSERT INTO public.maintenance_template_step
  (template_id, sort_order, description, measurement_label, measurement_unit, measurement_min, measurement_max) VALUES
  ('mt_espresso_pm_service', 10, 'Turn off + lock out machine, drain boilers', NULL, NULL, NULL, NULL),
  ('mt_espresso_pm_service', 20, 'Replace pump rebuild kit (vanes + seals)', NULL, NULL, NULL, NULL),
  ('mt_espresso_pm_service', 30, 'Replace ALL group head gaskets', NULL, NULL, NULL, NULL),
  ('mt_espresso_pm_service', 40, 'Replace shower screens + dispersion screens', NULL, NULL, NULL, NULL),
  ('mt_espresso_pm_service', 50, 'Replace inline water filter cartridge', NULL, NULL, NULL, NULL),
  ('mt_espresso_pm_service', 60, 'Boiler safety: test pressure relief valve', 'Relief pressure', 'bar', 1.4, 2.0),
  ('mt_espresso_pm_service', 70, 'Boiler safety: test level probe operation', NULL, NULL, NULL, NULL),
  ('mt_espresso_pm_service', 80, 'Electrical: ground continuity test', 'Ground resistance', 'ohms', NULL, 1),
  ('mt_espresso_pm_service', 90, 'Verify brew pressure under load', 'Brew pressure', 'bar', 8.5, 9.5),
  ('mt_espresso_pm_service',100, 'Verify steam pressure at idle', 'Steam pressure', 'bar', 1.0, 1.5),
  ('mt_espresso_pm_service',110, 'Calibrate brew temperature at group', 'Brew temp', '°F', 198, 204),
  ('mt_espresso_pm_service',120, 'Test all volumetric buttons (if equipped)', NULL, NULL, NULL, NULL),
  ('mt_espresso_pm_service',130, 'Refill boilers, vent air, restart, verify operation', NULL, NULL, NULL, NULL);


-- ESPRESSO — quarterly boiler descale
INSERT INTO public.maintenance_template_step
  (template_id, sort_order, description, measurement_label, measurement_unit, measurement_min, measurement_max) VALUES
  ('mt_espresso_boiler_descale', 10, 'Verify water hardness > 50 ppm (skip if RO water)', 'Hardness', 'ppm', 0, NULL),
  ('mt_espresso_boiler_descale', 20, 'Drain boilers fully', NULL, NULL, NULL, NULL),
  ('mt_espresso_boiler_descale', 30, 'Add manufacturer-approved descaler at spec concentration', NULL, NULL, NULL, NULL),
  ('mt_espresso_boiler_descale', 40, 'Let descaler dwell (per manufacturer spec)', 'Dwell time', 'min', 20, NULL),
  ('mt_espresso_boiler_descale', 50, 'Drain + rinse boilers TWICE with fresh water', NULL, NULL, NULL, NULL),
  ('mt_espresso_boiler_descale', 60, 'Refill, vent, restart, verify clean water at all outputs', NULL, NULL, NULL, NULL),
  ('mt_espresso_boiler_descale', 70, 'Verify brew pressure post-descale', 'Brew pressure', 'bar', 8.5, 9.5);


-- ESPRESSO — quarterly shower screen replacement
INSERT INTO public.maintenance_template_step
  (template_id, sort_order, description, measurement_label, measurement_unit, measurement_min, measurement_max) VALUES
  ('mt_espresso_shower_screens', 10, 'Cool machine, depressurize groups', NULL, NULL, NULL, NULL),
  ('mt_espresso_shower_screens', 20, 'Remove old shower screens (one per group)', NULL, NULL, NULL, NULL),
  ('mt_espresso_shower_screens', 30, 'Inspect group head dispersion for buildup, clean as needed', NULL, NULL, NULL, NULL),
  ('mt_espresso_shower_screens', 40, 'Install new shower screens, torque to spec', NULL, NULL, NULL, NULL),
  ('mt_espresso_shower_screens', 50, 'Flush each group for 30 seconds; verify even spray pattern', NULL, NULL, NULL, NULL);


-- ESPRESSO — brew pressure check
INSERT INTO public.maintenance_template_step
  (template_id, sort_order, description, measurement_label, measurement_unit, measurement_min, measurement_max) VALUES
  ('mt_espresso_brew_pressure_test', 10, 'Insert blind basket into portafilter, lock into group', NULL, NULL, NULL, NULL),
  ('mt_espresso_brew_pressure_test', 20, 'Start brew + read pressure gauge after 5 seconds', 'Brew pressure', 'bar', 8.5, 9.5),
  ('mt_espresso_brew_pressure_test', 30, 'Stop brew, check for leaks at gasket', NULL, NULL, NULL, NULL),
  ('mt_espresso_brew_pressure_test', 40, 'Repeat for each group; record any drift > 0.3 bar', NULL, NULL, NULL, NULL);


-- ============================================================
-- ROASTER — annual full PM
-- ============================================================
INSERT INTO public.maintenance_template_step
  (template_id, sort_order, description, measurement_label, measurement_unit, measurement_min, measurement_max) VALUES
  ('mt_roaster_full_pm', 10, 'Cool roaster fully + lock out gas', NULL, NULL, NULL, NULL),
  ('mt_roaster_full_pm', 20, 'Replace drum face + rear gaskets', NULL, NULL, NULL, NULL),
  ('mt_roaster_full_pm', 30, 'Inspect + repack drum bearings (or replace)', NULL, NULL, NULL, NULL),
  ('mt_roaster_full_pm', 40, 'Inspect drum drive chain, replace if stretched > 3%', 'Chain stretch', '%', 0, 3),
  ('mt_roaster_full_pm', 50, 'Burner: remove + clean orifices, check pilot/spark', NULL, NULL, NULL, NULL),
  ('mt_roaster_full_pm', 60, 'Verify gas pressure at idle + under load', 'Gas pressure', 'in W.C.', NULL, NULL),
  ('mt_roaster_full_pm', 70, 'Electrical: panel cleaning + ground continuity test', NULL, NULL, NULL, NULL),
  ('mt_roaster_full_pm', 80, 'Test high-limit cutoff at spec temperature', 'High-limit setpoint', '°F', NULL, NULL),
  ('mt_roaster_full_pm', 90, 'Test drum-rotation safety interlock', NULL, NULL, NULL, NULL),
  ('mt_roaster_full_pm',100, 'Inspect exhaust ductwork for creosote, integrity', NULL, NULL, NULL, NULL),
  ('mt_roaster_full_pm',110, 'Verify exhaust fan blade balance + integrity', NULL, NULL, NULL, NULL),
  ('mt_roaster_full_pm',120, 'Recalibrate thermocouples (BT + ET)', 'BT-ET delta at room temp', '°F', -2, 2),
  ('mt_roaster_full_pm',130, 'Roast trial — verify roast quality unchanged', NULL, NULL, NULL, NULL);


-- ROASTER — gasket replacement
INSERT INTO public.maintenance_template_step (template_id, sort_order, description) VALUES
  ('mt_roaster_gasket_replace', 10, 'Cool roaster fully'),
  ('mt_roaster_gasket_replace', 20, 'Remove front face plate'),
  ('mt_roaster_gasket_replace', 30, 'Scrape + clean old face gasket residue'),
  ('mt_roaster_gasket_replace', 40, 'Install new face gasket; torque face plate to spec'),
  ('mt_roaster_gasket_replace', 50, 'Remove rear inspection plate'),
  ('mt_roaster_gasket_replace', 60, 'Replace rear gasket'),
  ('mt_roaster_gasket_replace', 70, 'Restart, verify no air leaks at face / rear');


-- ROASTER — thermocouple calibration check
INSERT INTO public.maintenance_template_step
  (template_id, sort_order, description, measurement_label, measurement_unit, measurement_min, measurement_max) VALUES
  ('mt_roaster_thermocouple_check', 10, 'Roaster idle at room temp, both probes installed', NULL, NULL, NULL, NULL),
  ('mt_roaster_thermocouple_check', 20, 'Read BT', 'Bean temp', '°F', NULL, NULL),
  ('mt_roaster_thermocouple_check', 30, 'Read ET', 'Env temp', '°F', NULL, NULL),
  ('mt_roaster_thermocouple_check', 40, 'BT - ET should be within 2°F at room temp', 'Delta', '°F', -2, 2),
  ('mt_roaster_thermocouple_check', 50, 'If delta > 5°F: replace whichever drifts (usually BT after long use)', NULL, NULL, NULL, NULL);


-- ROASTER — gas pressure verification
INSERT INTO public.maintenance_template_step
  (template_id, sort_order, description, measurement_label, measurement_unit, measurement_min, measurement_max) VALUES
  ('mt_roaster_gas_pressure_check', 10, 'Burner idle (pilot or low fire)', NULL, NULL, NULL, NULL),
  ('mt_roaster_gas_pressure_check', 20, 'Read manifold pressure at idle', 'Idle pressure', 'in W.C.', NULL, NULL),
  ('mt_roaster_gas_pressure_check', 30, 'Run burner at full output', NULL, NULL, NULL, NULL),
  ('mt_roaster_gas_pressure_check', 40, 'Read manifold pressure under load', 'Load pressure', 'in W.C.', NULL, NULL),
  ('mt_roaster_gas_pressure_check', 50, 'Drift between idle + load should be < 0.5" W.C. — flag if more', NULL, NULL, NULL, NULL);


-- ROASTER — bearing grease
INSERT INTO public.maintenance_template_step (template_id, sort_order, description) VALUES
  ('mt_roaster_bearing_grease', 10, 'Cool roaster, identify grease zerks per drum manual'),
  ('mt_roaster_bearing_grease', 20, 'Apply high-temp bearing grease at each zerk (model-spec quantity)'),
  ('mt_roaster_bearing_grease', 30, 'Run drum 30 seconds, listen for noise change'),
  ('mt_roaster_bearing_grease', 40, 'Wipe excess grease from face plate area');


-- GRINDER — burr replacement
INSERT INTO public.maintenance_template_step (template_id, sort_order, description) VALUES
  ('mt_grinder_burr_replace_lbs', 10, 'Empty hopper + purge grinder fully'),
  ('mt_grinder_burr_replace_lbs', 20, 'Power off, remove top burr carrier'),
  ('mt_grinder_burr_replace_lbs', 30, 'Vacuum chamber, brush both burr seats clean'),
  ('mt_grinder_burr_replace_lbs', 40, 'Remove old burrs (note orientation)'),
  ('mt_grinder_burr_replace_lbs', 50, 'Install new burrs in same orientation, torque to spec'),
  ('mt_grinder_burr_replace_lbs', 60, 'Reinstall carrier, re-zero per grinder procedure'),
  ('mt_grinder_burr_replace_lbs', 70, 'Season burrs (run 0.5-1 lb of throwaway coffee through)'),
  ('mt_grinder_burr_replace_lbs', 80, 'Dial in espresso to a known recipe, verify grind quality');
