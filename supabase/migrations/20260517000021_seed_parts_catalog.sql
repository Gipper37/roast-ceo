-- ============================================================
-- Seed global parts catalog + template→part links
-- ============================================================
-- ~60 commonly-replaced parts across espresso machine / grinder /
-- brewer / roaster categories, with default prices sourced from
-- Espresso Parts + WLL Inc + manufacturer parts lists (mid-2026
-- street prices). Tenants override pricing via per-tenant rows.
--
-- maintenance_template_part rows wire the catalog into the existing
-- templates so the parts picker at log-time auto-suggests "you'll
-- probably need these".
--
-- Idempotent: DELETE+INSERT scoped to global rows.
-- ============================================================

DELETE FROM public.maintenance_template_part
  WHERE template_id IN (SELECT template_id FROM public.maintenance_template WHERE company_id IS NULL)
    AND part_id IN (SELECT part_id FROM public.parts_catalog WHERE company_id IS NULL);
DELETE FROM public.parts_catalog WHERE company_id IS NULL;


-- ============================================================
-- ESPRESSO MACHINE parts
-- ============================================================
INSERT INTO public.parts_catalog (part_id, part_name, part_number, category, default_unit_cost, default_markup_pct, supplier, notes) VALUES
  -- Universal / generic
  ('part_grouphead_gasket_e61',   'Group head gasket — E61 (8.5mm)', 'GASK-E61-8.5', 'espresso_machine',  4.50,  60, 'Espresso Parts', '8.5mm thick E61-style; most common'),
  ('part_grouphead_gasket_8mm',   'Group head gasket — 8mm',         'GASK-8MM',     'espresso_machine',  4.25,  60, 'Espresso Parts', NULL),
  ('part_shower_screen_e61',      'Shower screen — E61',             'SHWR-E61',     'espresso_machine',  6.50,  50, 'Espresso Parts', NULL),
  ('part_dispersion_screen_e61',  'Dispersion screen — E61',         'DISP-E61',     'espresso_machine',  8.00,  50, 'Espresso Parts', NULL),
  ('part_steam_wand_tip_4hole',   'Steam wand tip (4-hole)',         'STM-TIP-4',    'espresso_machine', 12.00,  50, 'Espresso Parts', 'Standard 4-hole tip; most cafes'),
  ('part_steam_wand_oring',       'Steam wand O-ring',               'OR-STM',       'espresso_machine',  1.50,  60, 'Espresso Parts', NULL),
  ('part_water_filter_cuno',      'Water filter cartridge — Everpure 4C-LM', 'EVP-4C-LM','espresso_machine', 95.00, 25, 'Everpure',  NULL),
  ('part_water_filter_bwt',       'Water filter cartridge — BWT Bestmax',    'BWT-BMX-P','espresso_machine',125.00, 25, 'BWT',       NULL),
  ('part_descaler_puly',          'Descaler — Puly Cleaner (1kg)',   'PULY-DSCL-1KG','espresso_machine', 35.00,  30, 'Puly',      NULL),
  ('part_cafiza_bottle',          'Cafiza espresso machine detergent (570g)', 'CAFZ-570','espresso_machine', 22.00, 30, 'Urnex', NULL),
  ('part_rinza_bottle',           'Rinza steam wand cleaner (1L)',   'RINZ-1L',      'espresso_machine', 28.00,  30, 'Urnex', NULL),
  ('part_blind_basket_58',        'Blind basket (58mm)',             'BLND-58',      'espresso_machine',  9.50,  50, 'Espresso Parts', NULL),
  ('part_filter_basket_18g',      'Filter basket (18g, 58mm)',       'BSKT-18G',     'espresso_machine', 14.00,  50, 'IMS', NULL),
  ('part_filter_basket_22g',      'Filter basket (22g, 58mm)',       'BSKT-22G',     'espresso_machine', 14.50,  50, 'IMS', NULL),
  ('part_portafilter_spout_dbl',  'Portafilter spout — double',      'PF-SPT-DBL',   'espresso_machine', 18.00,  50, 'Generic', NULL),
  ('part_pump_rebuild_procon',    'Pump rebuild kit — Procon rotary','PROCN-RBLD',   'espresso_machine', 65.00,  40, 'Procon', NULL),
  ('part_pressure_gauge_brew',    'Brew pressure gauge (0-16 bar)',  'GAUGE-BREW',   'espresso_machine', 45.00,  40, 'Generic', NULL),
  ('part_pressure_gauge_steam',   'Steam pressure gauge (0-3 bar)',  'GAUGE-STM',    'espresso_machine', 38.00,  40, 'Generic', NULL),
  ('part_expansion_valve',        'Expansion valve (12 bar)',        'EXP-12BAR',    'espresso_machine', 42.00,  40, 'Generic', NULL),
  ('part_solenoid_3way',          '3-way solenoid valve',            'SOLN-3W',      'espresso_machine', 75.00,  40, 'Lucifer / Parker', NULL),
  ('part_heating_element_3000w',  'Heating element (3000W, 240V)',   'HEAT-3000-240','espresso_machine',195.00,  35, 'Generic', NULL);


-- ============================================================
-- GRINDER parts
-- ============================================================
INSERT INTO public.parts_catalog (part_id, part_name, part_number, category, applies_to_brand_id, default_unit_cost, default_markup_pct, supplier, notes) VALUES
  ('part_burrs_ek43_98mm',        'Burrs — EK43 (98mm flat)',         'EK43-BURR',    'grinder', 'brand_mahlkonig', 175.00, 30, 'Mahlkönig', '98mm flat burr set'),
  ('part_burrs_e80_80mm',         'Burrs — E80 (80mm flat)',          'E80-BURR',     'grinder', 'brand_mahlkonig', 135.00, 30, 'Mahlkönig', NULL),
  ('part_burrs_e65_64mm',         'Burrs — E65 (64mm flat)',          'E65-BURR',     'grinder', 'brand_mahlkonig',  95.00, 30, 'Mahlkönig', NULL),
  ('part_burrs_robur_71mm',       'Burrs — Robur (71mm conical)',     'ROB-BURR',     'grinder', 'brand_mazzer',    155.00, 30, 'Mazzer', NULL),
  ('part_burrs_major_83mm',       'Burrs — Major (83mm flat)',        'MJR-BURR',     'grinder', 'brand_mazzer',     85.00, 30, 'Mazzer', NULL),
  ('part_burrs_kony_71mm',        'Burrs — Kony (71mm conical)',      'KNY-BURR',     'grinder', 'brand_mazzer',    135.00, 30, 'Mazzer', NULL),
  ('part_burrs_super_jolly',      'Burrs — Super Jolly (64mm flat)',  'SJ-BURR',      'grinder', 'brand_mazzer',     58.00, 30, 'Mazzer', NULL),
  ('part_burrs_atom_75',          'Burrs — Atom 75 (75mm flat)',      'AT75-BURR',    'grinder', 'brand_eureka',     85.00, 30, 'Eureka', NULL);

INSERT INTO public.parts_catalog (part_id, part_name, part_number, category, default_unit_cost, default_markup_pct, supplier, notes) VALUES
  ('part_grindz_jar',             'Grindz grinder cleaning tablets (430g)', 'GRINDZ-430', 'grinder', 22.00, 35, 'Urnex', NULL),
  ('part_motor_brushes_pair',     'Motor brushes (pair, commercial grinder)','MTR-BR-PR',  'grinder', 18.00, 40, 'Generic', NULL),
  ('part_burr_carrier_oring',     'Burr carrier O-ring',                    'OR-BURR',    'grinder',  2.50, 60, 'Generic', NULL),
  ('part_food_grease_h1',         'NSF H1 food-grade grease (4oz)',         'NSF-H1-4OZ', 'grinder', 15.00, 35, 'Magnalube G', NULL),
  ('part_hopper_assembly_universal','Hopper assembly (universal 1.5lb)',    'HOP-1.5LB',  'grinder', 45.00, 40, 'Generic', NULL);


-- ============================================================
-- BREWER parts
-- ============================================================
INSERT INTO public.parts_catalog (part_id, part_name, part_number, category, default_unit_cost, default_markup_pct, supplier, notes) VALUES
  ('part_brewer_filter_curtis',   'Brewer water filter — Curtis',     'CRT-FLTR',     'brewer', 65.00, 30, 'Wilbur Curtis', NULL),
  ('part_brewer_filter_bunn',     'Brewer water filter — BUNN',       'BUNN-FLTR',    'brewer', 58.00, 30, 'BUNN', NULL),
  ('part_brewer_spray_head',      'Spray head assembly',              'SPRY-HD',      'brewer', 38.00, 40, 'Generic', NULL),
  ('part_brewer_dispense_valve',  'Dispense valve seals kit',         'DSP-SEALS',    'brewer', 28.00, 40, 'Generic', NULL),
  ('part_brewer_descaler',        'Brewer descaling solution (1gal)', 'BRW-DSCL-1GAL','brewer', 38.00, 30, 'CafiBlu', NULL),
  ('part_brewer_decanter_glass',  'Decanter — glass (64oz)',          'DEC-GL-64',    'brewer', 18.00, 50, 'Generic', NULL),
  ('part_brewer_decanter_thermal','Decanter — thermal carafe (2.5L)', 'DEC-TH-2.5L',  'brewer',125.00, 40, 'Curtis', NULL);


-- ============================================================
-- ROASTER parts (in-house, operator-managed)
-- ============================================================
INSERT INTO public.parts_catalog (part_id, part_name, part_number, category, applies_to_brand_id, default_unit_cost, default_markup_pct, supplier, notes) VALUES
  ('part_drum_gasket_loring_s15', 'Drum face gasket — Loring S15',    'LOR-S15-GSK',  'roaster', 'brand_loring',   145.00, 25, 'Loring', NULL),
  ('part_drum_gasket_probat_l12', 'Drum gasket kit — Probat L12',     'PRO-L12-GSK',  'roaster', 'brand_probat',   175.00, 25, 'Probat', NULL),
  ('part_drum_gasket_diedrich',   'Drum gasket — Diedrich IR-12',     'DDR-IR12-GSK', 'roaster', 'brand_diedrich', 115.00, 25, 'Diedrich', NULL);

INSERT INTO public.parts_catalog (part_id, part_name, part_number, category, default_unit_cost, default_markup_pct, supplier, notes) VALUES
  ('part_thermocouple_k_24in',    'Thermocouple K-type (24" probe)',     'TC-K-24',     'roaster', 38.00, 35, 'Omega Engineering', NULL),
  ('part_thermocouple_k_36in',    'Thermocouple K-type (36" probe)',     'TC-K-36',     'roaster', 48.00, 35, 'Omega Engineering', NULL),
  ('part_thermocouple_j_24in',    'Thermocouple J-type (24" probe)',     'TC-J-24',     'roaster', 35.00, 35, 'Omega Engineering', NULL),
  ('part_drum_chain_60_link',     'Drum drive chain (60-link)',          'CHN-60',      'roaster', 65.00, 30, 'Generic', NULL),
  ('part_bearing_grease_hi_temp', 'High-temp bearing grease (16oz)',     'GRS-HT-16',   'roaster', 28.00, 35, 'Mobiltemp SHC 32', NULL),
  ('part_drum_bearing_set',       'Drum bearing set (front + rear)',     'BRG-DRM-SET', 'roaster',285.00, 30, 'Generic SKF / NTN', NULL),
  ('part_sight_glass',            'Sight glass (round, gasketed)',       'SG-RND',      'roaster', 45.00, 40, 'Generic', NULL),
  ('part_burner_orifice_set',     'Burner orifice set (replacement)',    'BRN-ORF-SET', 'roaster',125.00, 30, 'Generic', NULL),
  ('part_exhaust_fan_motor',      'Exhaust fan motor (1/3 HP, 1725rpm)', 'EXH-FAN-MTR', 'roaster',225.00, 30, 'Dayton / similar', NULL),
  ('part_drum_brush_stainless',   'Drum brush — stainless wire',         'DRM-BRUSH-SS','roaster', 32.00, 35, 'Generic', NULL),
  ('part_chaff_collector_bag',    'Chaff collector bag — replacement',   'CHAFF-BAG',   'roaster', 18.00, 40, 'Generic', NULL),
  ('part_door_seal_gasket',       'Roaster door seal gasket',            'DOOR-SEAL',   'roaster', 38.00, 30, 'Generic', NULL),
  ('part_high_limit_switch',      'High-limit safety switch',            'HL-SW',       'roaster', 65.00, 35, 'Honeywell', NULL),
  ('part_gas_valve_24v',          'Gas safety valve (24V)',              'GAS-VLV-24',  'roaster',185.00, 30, 'Honeywell', NULL);


-- ============================================================
-- WATER TREATMENT parts (reused on espresso side)
-- ============================================================
INSERT INTO public.parts_catalog (part_id, part_name, part_number, category, applies_to_brand_id, default_unit_cost, default_markup_pct, supplier, notes) VALUES
  ('part_wf_3m_hf45',             'Water filter — 3M HF45-S',         '3M-HF45-S',    'water_treatment', 'brand_3m',      105.00, 25, '3M Water', NULL),
  ('part_wf_pentair_h300',        'Water filter — Pentair H-300',     'PNT-H300',     'water_treatment', 'brand_pentair',  88.00, 25, 'Pentair', NULL),
  ('part_water_hardness_strips',  'Water hardness test strips (50)',  'TDS-STRIPS-50','water_treatment', NULL,             18.00, 35, 'Generic', NULL);


-- ============================================================
-- maintenance_template_part — link standard parts to templates
-- ============================================================

-- Shower screen replacement — 1 per group (per_group flag for future
-- multiplication when equipment.group_count is set)
INSERT INTO public.maintenance_template_part (template_id, part_id, quantity, per_group, is_required) VALUES
  ('mt_espresso_shower_screens',  'part_shower_screen_e61',     1, true,  true);

-- Group head gaskets — 1 per group
INSERT INTO public.maintenance_template_part (template_id, part_id, quantity, per_group, is_required) VALUES
  ('mt_espresso_group_gaskets',   'part_grouphead_gasket_e61',  1, true,  true);

-- Boiler descale — descaler consumable
INSERT INTO public.maintenance_template_part (template_id, part_id, quantity, per_group, is_required) VALUES
  ('mt_espresso_boiler_descale',  'part_descaler_puly',         1, false, true);

-- Water filter swap
INSERT INTO public.maintenance_template_part (template_id, part_id, quantity, per_group, is_required) VALUES
  ('mt_espresso_water_filter',    'part_water_filter_cuno',     1, false, true);

-- Annual PM service — multiple consumables + group gaskets + screens
INSERT INTO public.maintenance_template_part (template_id, part_id, quantity, per_group, is_required) VALUES
  ('mt_espresso_pm_service',      'part_pump_rebuild_procon',   1, false, true),
  ('mt_espresso_pm_service',      'part_grouphead_gasket_e61',  1, true,  true),
  ('mt_espresso_pm_service',      'part_shower_screen_e61',     1, true,  true),
  ('mt_espresso_pm_service',      'part_dispersion_screen_e61', 1, true,  true),
  ('mt_espresso_pm_service',      'part_water_filter_cuno',     1, false, true),
  ('mt_espresso_pm_service',      'part_steam_wand_oring',      2, false, false),
  ('mt_espresso_pm_service',      'part_cafiza_bottle',         1, false, false);

-- Baskets check — replacement parts if needed
INSERT INTO public.maintenance_template_part (template_id, part_id, quantity, per_group, is_required) VALUES
  ('mt_espresso_baskets_rim_check','part_filter_basket_18g',    1, true,  false);

-- Weekly detergent backflush (recommended) — consumes detergent
INSERT INTO public.maintenance_template_part (template_id, part_id, quantity, per_group, is_required) VALUES
  ('mt_espresso_backflush_cafiza', 'part_cafiza_bottle',        1, false, false),
  ('mt_espresso_steam_wand_descale','part_rinza_bottle',        1, false, false);

-- Pressure-test uses blind basket
INSERT INTO public.maintenance_template_part (template_id, part_id, quantity, per_group, is_required) VALUES
  ('mt_espresso_brew_pressure_test', 'part_blind_basket_58',    1, false, false);


-- ===== GRINDERS =====
-- Burr cleaning tablets
INSERT INTO public.maintenance_template_part (template_id, part_id, quantity, per_group, is_required) VALUES
  ('mt_grinder_cleaning_tablets', 'part_grindz_jar',            1, false, true);

-- Burr replacement (template-level — actual part picked at log time
-- based on which burr the equipment uses; here we mark the most
-- common as the suggestion)
INSERT INTO public.maintenance_template_part (template_id, part_id, quantity, per_group, is_required) VALUES
  ('mt_grinder_burr_replace_lbs', 'part_burrs_major_83mm',      1, false, false);

-- Thread lube uses food-safe grease
INSERT INTO public.maintenance_template_part (template_id, part_id, quantity, per_group, is_required) VALUES
  ('mt_grinder_thread_lube',      'part_food_grease_h1',        1, false, false);

-- Motor brush replacement
INSERT INTO public.maintenance_template_part (template_id, part_id, quantity, per_group, is_required) VALUES
  ('mt_grinder_motor_brushes',    'part_motor_brushes_pair',    1, false, true);


-- ===== ROASTERS =====
-- Gasket replacement
INSERT INTO public.maintenance_template_part (template_id, part_id, quantity, per_group, is_required) VALUES
  ('mt_roaster_gasket_replace',   'part_drum_gasket_probat_l12',1, false, true);

-- Bearing grease
INSERT INTO public.maintenance_template_part (template_id, part_id, quantity, per_group, is_required) VALUES
  ('mt_roaster_bearing_grease',   'part_bearing_grease_hi_temp',1, false, true);

-- Drum brush as a consumable
INSERT INTO public.maintenance_template_part (template_id, part_id, quantity, per_group, is_required) VALUES
  ('mt_roaster_drum_brush',       'part_drum_brush_stainless',  1, false, false);

-- Thermocouple check (replacement if drift) — both BT + ET
INSERT INTO public.maintenance_template_part (template_id, part_id, quantity, per_group, is_required) VALUES
  ('mt_roaster_thermocouple_check', 'part_thermocouple_k_24in', 1, false, false);

-- Full PM uses many parts
INSERT INTO public.maintenance_template_part (template_id, part_id, quantity, per_group, is_required) VALUES
  ('mt_roaster_full_pm', 'part_drum_gasket_probat_l12',  1, false, true),
  ('mt_roaster_full_pm', 'part_bearing_grease_hi_temp',  1, false, true),
  ('mt_roaster_full_pm', 'part_door_seal_gasket',        1, false, false),
  ('mt_roaster_full_pm', 'part_thermocouple_k_24in',     2, false, false),
  ('mt_roaster_full_pm', 'part_burner_orifice_set',      1, false, false),
  ('mt_roaster_full_pm', 'part_high_limit_switch',       1, false, false);

-- Chaff cleanout uses replacement bag
INSERT INTO public.maintenance_template_part (template_id, part_id, quantity, per_group, is_required) VALUES
  ('mt_roaster_chaff_collector',  'part_chaff_collector_bag',   1, false, false);


-- ===== WATER TREATMENT =====
INSERT INTO public.maintenance_template_part (template_id, part_id, quantity, per_group, is_required) VALUES
  ('mt_water_filter_replace',     'part_wf_3m_hf45',            1, false, true),
  ('mt_water_hardness_test',      'part_water_hardness_strips', 1, false, true);
