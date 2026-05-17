-- ============================================================
-- Equipment: global brand + model + template + tech-contact seed
-- ============================================================
-- Catalog covers the major commercial coffee equipment manufacturers
-- across espresso machines, grinders, batch brewers, roasters, and
-- packaging. Tenants can add their own brands/models via the global+
-- tenant pattern.
--
-- Sourced from industry references (SCA, Daily Coffee News, manufacturer
-- websites) as of 2026-05.
-- ============================================================

-- ------------------------------------------------------------
-- Reset only the GLOBAL catalog rows so re-running this is safe.
-- Tenant-owned rows (company_id IS NOT NULL) are untouched.
-- ------------------------------------------------------------
DELETE FROM public.maintenance_template      WHERE company_id IS NULL;
DELETE FROM public.equipment_tech_contact    WHERE company_id IS NULL;
DELETE FROM public.equipment_model           WHERE company_id IS NULL;
DELETE FROM public.equipment_brand           WHERE company_id IS NULL;


-- ============================================================
-- BRANDS
-- ============================================================
INSERT INTO public.equipment_brand (equipment_brand_id, category, name, country, support_url, support_phone) VALUES
  -- Espresso machines
  ('brand_la_marzocco',     'espresso_machine', 'La Marzocco',         'Italy',        'https://www.lamarzocco.com/support',           NULL),
  ('brand_slayer',          'espresso_machine', 'Slayer',              'USA',          'https://slayerespresso.com/support',           NULL),
  ('brand_synesso',         'espresso_machine', 'Synesso',             'USA',          'https://synesso.com/contact',                  NULL),
  ('brand_nuova_simonelli', 'espresso_machine', 'Nuova Simonelli',     'Italy',        'https://www.nuovasimonelli.it',                NULL),
  ('brand_victoria_arduino','espresso_machine', 'Victoria Arduino',    'Italy',        'https://www.victoriaarduino.com',              NULL),
  ('brand_rancilio',        'espresso_machine', 'Rancilio',            'Italy',        'https://www.ranciliogroup.com',                NULL),
  ('brand_faema',           'espresso_machine', 'Faema',               'Italy',        'https://www.faema.com',                        NULL),
  ('brand_la_cimbali',      'espresso_machine', 'La Cimbali',          'Italy',        'https://www.cimbali.com',                      NULL),
  ('brand_modbar',          'espresso_machine', 'Modbar',              'USA',          'https://modbar.com',                           NULL),
  ('brand_kees_vdw',        'espresso_machine', 'Kees van der Westen', 'Netherlands',  'https://keesvanderwesten.com',                 NULL),
  ('brand_sanremo',         'espresso_machine', 'Sanremo',             'Italy',        'https://www.sanremocoffeemachines.com',        NULL),
  ('brand_wega',            'espresso_machine', 'Wega',                'Italy',        'https://www.wega.it',                          NULL),
  ('brand_ecm',             'espresso_machine', 'ECM',                 'Germany',      'https://www.ecm.de',                           NULL),
  ('brand_profitec',        'espresso_machine', 'Profitec',            'Germany',      'https://www.profitec-espresso.com',            NULL),
  ('brand_lelit',           'espresso_machine', 'Lelit',               'Italy',        'https://www.lelit.com',                        NULL),
  ('brand_bezzera',         'espresso_machine', 'Bezzera',             'Italy',        'https://www.bezzera.it',                       NULL),

  -- Grinders
  ('brand_mahlkonig',       'grinder',          'Mahlkönig',           'Germany',      'https://www.mahlkoenig.de',                    NULL),
  ('brand_mazzer',          'grinder',          'Mazzer',              'Italy',        'https://www.mazzer.com',                       NULL),
  ('brand_eureka',          'grinder',          'Eureka',              'Italy',        'https://www.eureka.co.it',                     NULL),
  ('brand_ditting',         'grinder',          'Ditting',             'Switzerland',  'https://www.dittingswiss.ch',                  NULL),
  ('brand_anfim',           'grinder',          'Anfim',               'Italy',        'https://www.anfim.it',                         NULL),
  ('brand_compak',          'grinder',          'Compak',              'Spain',        'https://www.compakcoffee.com',                 NULL),
  ('brand_fiorenzato',      'grinder',          'Fiorenzato',          'Italy',        'https://www.fiorenzato.com',                   NULL),
  ('brand_macap',           'grinder',          'Macap',               'Italy',        'https://www.macap.it',                         NULL),
  ('brand_versalab',        'grinder',          'Versalab',            'USA',          'https://versalab.com',                         NULL),
  ('brand_niche',           'grinder',          'Niche',               'UK',           'https://nichecoffee.co.uk',                    NULL),
  ('brand_baratza',         'grinder',          'Baratza',             'USA',          'https://baratza.com',                          NULL),

  -- Batch brewers
  ('brand_curtis',          'brewer',           'Wilbur Curtis',       'USA',          'https://wilburcurtis.com',                     NULL),
  ('brand_bunn',            'brewer',           'BUNN',                'USA',          'https://www.bunn.com',                         NULL),
  ('brand_fetco',           'brewer',           'Fetco',               'USA',          'https://www.fetco.com',                        NULL),
  ('brand_marco',           'brewer',           'Marco Beverage Systems','Ireland',    'https://marcobeveragesystems.com',             NULL),
  ('brand_newco',           'brewer',           'Newco',               'USA',          'https://www.newcocoffee.com',                  NULL),
  ('brand_bravilor',        'brewer',           'Bravilor Bonamat',    'Netherlands',  'https://www.bravilor.com',                     NULL),

  -- Roasters (the operator's own equipment)
  ('brand_probat',          'roaster',          'Probat',              'Germany',      'https://www.probat.com',                       NULL),
  ('brand_loring',          'roaster',          'Loring',              'USA',          'https://loring.com',                           NULL),
  ('brand_diedrich',        'roaster',          'Diedrich',            'USA',          'https://diedrichroasters.com',                 NULL),
  ('brand_mill_city',       'roaster',          'Mill City',           'USA',          'https://millcityroasters.com',                 NULL),
  ('brand_san_franciscan',  'roaster',          'San Franciscan',      'USA',          'https://sanfranciscanroaster.com',             NULL),
  ('brand_giesen',          'roaster',          'Giesen',              'Netherlands',  'https://giesencoffeeroasters.com',             NULL),
  ('brand_imf',             'roaster',          'IMF',                 'Italy',        'https://www.imfsrl.com',                       NULL),
  ('brand_stronghold',      'roaster',          'Stronghold',          'South Korea',  'https://strongholdtech.com',                   NULL),
  ('brand_aillio',          'roaster',          'Aillio',              'Denmark',      'https://aillio.com',                           NULL),
  ('brand_ikawa',           'roaster',          'Ikawa',               'UK',           'https://www.ikawa.com',                        NULL),
  ('brand_petroncini',      'roaster',          'Petroncini',          'Italy',        'https://www.petroncini.com',                   NULL),
  ('brand_buhler',          'roaster',          'Bühler',              'Switzerland',  'https://www.buhlergroup.com',                  NULL),
  ('brand_toper',           'roaster',          'Toper',               'Turkey',       'https://www.toper.com',                        NULL),
  ('brand_north_tj',        'roaster',          'North',               'China',        'https://www.northroaster.com',                 NULL),

  -- Packaging (less brand recognition in coffee — generic global pouch/bag fillers)
  ('brand_goglio',          'packaging',        'Goglio',              'Italy',        'https://www.goglio.it',                        NULL),
  ('brand_bossar',          'packaging',        'Bossar',              'Spain',        'https://www.bossar.com',                       NULL),
  ('brand_pfm',             'packaging',        'PFM',                 'Italy',        'https://www.pfm.it',                           NULL),
  ('brand_hayssen',         'packaging',        'Hayssen Sandiacre',   'UK',           'https://www.hayssen.com',                      NULL),

  -- Water treatment
  ('brand_everpure',        'water_treatment',  'Everpure',            'USA',          'https://www.everpure.com',                     NULL),
  ('brand_bwt',             'water_treatment',  'BWT',                 'Austria',      'https://www.bwt.com',                          NULL),
  ('brand_3m',              'water_treatment',  '3M Water Filtration', 'USA',          'https://www.3m.com',                           NULL),
  ('brand_pentair',         'water_treatment',  'Pentair',             'USA',          'https://www.pentair.com',                      NULL);


-- ============================================================
-- MODELS — top 2-4 per major brand. The "generation" column captures
-- ambiguous variants (PB v1 vs PB v2). typical_lifespan_lbs/hours
-- populated where industry-standard figures exist.
-- ============================================================
INSERT INTO public.equipment_model (equipment_model_id, brand_id, category, model_name, generation, typical_lifespan_lbs, typical_lifespan_hours, notes) VALUES
  -- La Marzocco
  ('model_la_marzocco_linea_pb',  'brand_la_marzocco',     'espresso_machine', 'Linea PB',        NULL, NULL, 8000, 'Cafe staple, paddle group, dual boiler'),
  ('model_la_marzocco_linea_mini','brand_la_marzocco',     'espresso_machine', 'Linea Mini',      NULL, NULL, 6000, 'Prosumer/light commercial'),
  ('model_la_marzocco_kb90',      'brand_la_marzocco',     'espresso_machine', 'KB90',            NULL, NULL, 10000, 'High-volume saturated group'),
  ('model_la_marzocco_gb5',       'brand_la_marzocco',     'espresso_machine', 'GB5 S',           NULL, NULL, 8000, NULL),
  ('model_la_marzocco_strada_ep', 'brand_la_marzocco',     'espresso_machine', 'Strada EP',       NULL, NULL, 8000, 'Electronic paddle'),

  -- Slayer
  ('model_slayer_espresso',       'brand_slayer',          'espresso_machine', 'Espresso',        '3-group', NULL, 8000, 'Manual paddle, pre-brew'),
  ('model_slayer_steam_lp',       'brand_slayer',          'espresso_machine', 'Steam LP',        NULL, NULL, 8000, 'Low-pressure steam variant'),
  ('model_slayer_single_group',   'brand_slayer',          'espresso_machine', 'Single Group',    NULL, NULL, 6000, NULL),

  -- Synesso
  ('model_synesso_mvp_hydra',     'brand_synesso',         'espresso_machine', 'MVP Hydra',       NULL, NULL, 8000, 'Per-group temperature control'),
  ('model_synesso_s_series',      'brand_synesso',         'espresso_machine', 'S-Series',        NULL, NULL, 8000, NULL),

  -- Nuova Simonelli + Victoria Arduino (same group)
  ('model_ns_aurelia_wave',       'brand_nuova_simonelli', 'espresso_machine', 'Aurelia Wave',    'T3', NULL, 8000, 'World barista champ machine'),
  ('model_ns_appia_life',         'brand_nuova_simonelli', 'espresso_machine', 'Appia Life',      NULL, NULL, 7000, NULL),
  ('model_va_black_eagle',        'brand_victoria_arduino','espresso_machine', 'Black Eagle',     'VA388', NULL, 10000, 'High-end competition machine'),
  ('model_va_eagle_one',          'brand_victoria_arduino','espresso_machine', 'Eagle One',       NULL, NULL, 8000, 'Lower-energy successor'),
  ('model_va_white_eagle',        'brand_victoria_arduino','espresso_machine', 'White Eagle',     NULL, NULL, 8000, NULL),

  -- Rancilio
  ('model_rancilio_classe_11',    'brand_rancilio',        'espresso_machine', 'Classe 11',       NULL, NULL, 8000, NULL),
  ('model_rancilio_classe_7',     'brand_rancilio',        'espresso_machine', 'Classe 7',        NULL, NULL, 7000, NULL),
  ('model_rancilio_silvia_pro',   'brand_rancilio',        'espresso_machine', 'Silvia Pro',      NULL, NULL, 4000, 'Prosumer dual-boiler'),

  -- Faema
  ('model_faema_e71e',            'brand_faema',           'espresso_machine', 'E71E',            NULL, NULL, 8000, NULL),
  ('model_faema_e61_legend',      'brand_faema',           'espresso_machine', 'E61 Legend',      NULL, NULL, 8000, 'Group head namesake'),

  -- La Cimbali
  ('model_cimbali_m100',          'brand_la_cimbali',      'espresso_machine', 'M100',            NULL, NULL, 8000, NULL),
  ('model_cimbali_m26',           'brand_la_cimbali',      'espresso_machine', 'M26',             NULL, NULL, 7000, NULL),

  -- Modbar
  ('model_modbar_espresso',       'brand_modbar',          'espresso_machine', 'Espresso AV',     NULL, NULL, 7000, 'Under-counter modular bar'),
  ('model_modbar_steam',          'brand_modbar',          'espresso_machine', 'Steam Module',    NULL, NULL, 7000, NULL),

  -- Kees van der Westen
  ('model_kees_speedster',        'brand_kees_vdw',        'espresso_machine', 'Speedster',       NULL, NULL, 8000, 'Single group, sat group'),
  ('model_kees_spirit',           'brand_kees_vdw',        'espresso_machine', 'Spirit',          NULL, NULL, 8000, NULL),

  -- Sanremo
  ('model_sanremo_cafe_racer',    'brand_sanremo',         'espresso_machine', 'Cafe Racer',      NULL, NULL, 8000, NULL),
  ('model_sanremo_opera',         'brand_sanremo',         'espresso_machine', 'Opera 2.0',       NULL, NULL, 9000, 'Pressure profiling'),

  -- ECM, Profitec, Lelit, Bezzera (prosumer)
  ('model_ecm_synchronika',       'brand_ecm',             'espresso_machine', 'Synchronika',     NULL, NULL, 5000, NULL),
  ('model_profitec_pro_700',      'brand_profitec',        'espresso_machine', 'Pro 700',         NULL, NULL, 5000, NULL),
  ('model_lelit_bianca',          'brand_lelit',           'espresso_machine', 'Bianca',          'v3', NULL, 4000, NULL),
  ('model_bezzera_strega',        'brand_bezzera',         'espresso_machine', 'Strega',          NULL, NULL, 4000, 'Lever machine'),

  -- ============================================================
  -- GRINDERS — typical_lifespan_lbs = burr life (volume-dependent)
  -- ============================================================
  ('model_mahlkonig_ek43',        'brand_mahlkonig',       'grinder',          'EK43',            NULL, 1500, NULL, 'Flat 98mm burrs; cafe + brew bar staple'),
  ('model_mahlkonig_ek43s',       'brand_mahlkonig',       'grinder',          'EK43 S',          NULL, 1500, NULL, NULL),
  ('model_mahlkonig_e80',         'brand_mahlkonig',       'grinder',          'E80 Supreme',     NULL, 2000, NULL, 'Espresso, 80mm flat'),
  ('model_mahlkonig_e65s',        'brand_mahlkonig',       'grinder',          'E65S',            NULL, 1200, NULL, NULL),
  ('model_mahlkonig_peak',        'brand_mahlkonig',       'grinder',          'Peak',            NULL, 1200, NULL, NULL),

  ('model_mazzer_robur',          'brand_mazzer',          'grinder',          'Robur',           'S',   1800, NULL, 'Conical 71mm'),
  ('model_mazzer_kony',           'brand_mazzer',          'grinder',          'Kony',            'S',   1500, NULL, NULL),
  ('model_mazzer_major',          'brand_mazzer',          'grinder',          'Major',           'V',   1200, NULL, 'Flat 83mm'),
  ('model_mazzer_super_jolly',    'brand_mazzer',          'grinder',          'Super Jolly',     'V',   1000, NULL, NULL),
  ('model_mazzer_zm',             'brand_mazzer',          'grinder',          'ZM Filter',       NULL,  1500, NULL, 'Filter/brew grinder'),

  ('model_eureka_mignon',         'brand_eureka',          'grinder',          'Mignon Specialita', NULL, 800, NULL, 'Prosumer espresso'),
  ('model_eureka_atom_75',        'brand_eureka',          'grinder',          'Atom 75',         NULL, 1500, NULL, NULL),
  ('model_eureka_zenith_65',      'brand_eureka',          'grinder',          'Zenith 65 Neo',   NULL, 1200, NULL, NULL),

  ('model_ditting_kr804',         'brand_ditting',         'grinder',          'KR804',           NULL, 3500, NULL, 'High-output retail/brew'),
  ('model_ditting_807',           'brand_ditting',         'grinder',          '807',             NULL, 4500, NULL, NULL),

  ('model_anfim_pratica',         'brand_anfim',           'grinder',          'Pratica',         NULL, 1000, NULL, NULL),
  ('model_anfim_sp_ii',           'brand_anfim',           'grinder',          'SP II',           NULL, 1200, NULL, NULL),

  ('model_compak_e10',            'brand_compak',          'grinder',          'E10 Master Conic',NULL, 1500, NULL, NULL),
  ('model_compak_pkf',            'brand_compak',          'grinder',          'PKF',             NULL, 1000, NULL, NULL),

  ('model_fiorenzato_f64',        'brand_fiorenzato',      'grinder',          'F64 Evo',         NULL, 1200, NULL, NULL),
  ('model_fiorenzato_f83',        'brand_fiorenzato',      'grinder',          'F83 Evo',         NULL, 1500, NULL, NULL),

  ('model_versalab_m3',           'brand_versalab',        'grinder',          'M3',              NULL, 800,  NULL, NULL),
  ('model_niche_zero',            'brand_niche',           'grinder',          'Zero',            NULL, 500,  NULL, 'Prosumer single-dose'),
  ('model_baratza_forte_bg',      'brand_baratza',         'grinder',          'Forte BG',        NULL, 800,  NULL, NULL),

  -- ============================================================
  -- BREWERS
  -- ============================================================
  ('model_curtis_g4_thermopro',   'brand_curtis',          'brewer',           'G4 ThermoPro',    NULL, NULL, 8000, NULL),
  ('model_curtis_seraphim',       'brand_curtis',          'brewer',           'Seraphim',        NULL, NULL, 6000, 'Single-cup'),
  ('model_curtis_alpha_3gt',      'brand_curtis',          'brewer',           'Alpha 3GT',       NULL, NULL, 8000, NULL),

  ('model_bunn_iced_tea_coffee',  'brand_bunn',            'brewer',           'ITCB Twin',       NULL, NULL, 8000, NULL),
  ('model_bunn_axiom',            'brand_bunn',            'brewer',           'Axiom',           NULL, NULL, 8000, NULL),
  ('model_bunn_trifecta',         'brand_bunn',            'brewer',           'Trifecta MB',     NULL, NULL, 6000, 'Single-cup'),

  ('model_fetco_cbs_2131xts',     'brand_fetco',           'brewer',           'CBS-2131XTS',     NULL, NULL, 8000, NULL),
  ('model_fetco_cbs_1131',        'brand_fetco',           'brewer',           'CBS-1131-V+',     NULL, NULL, 7000, NULL),

  ('model_marco_jet6',            'brand_marco',           'brewer',           'JET6',            NULL, NULL, 7000, NULL),
  ('model_marco_uber',            'brand_marco',           'brewer',           'Uber Boiler',     NULL, NULL, 7000, NULL),

  ('model_newco_lcd2',            'brand_newco',           'brewer',           'LCD-2',           NULL, NULL, 7000, NULL),

  -- ============================================================
  -- ROASTERS — the operator's own equipment, more detailed lifecycle
  -- ============================================================
  ('model_probat_l5',             'brand_probat',          'roaster',          'L5',              NULL, NULL, NULL, '5kg sample / light production'),
  ('model_probat_l12',            'brand_probat',          'roaster',          'L12',             NULL, NULL, NULL, '12kg shop roaster'),
  ('model_probat_l25',            'brand_probat',          'roaster',          'L25',             NULL, NULL, NULL, '25kg production'),
  ('model_probat_p25',            'brand_probat',          'roaster',          'P25',             NULL, NULL, NULL, '25kg drum, smart series'),
  ('model_probat_g75',            'brand_probat',          'roaster',          'G75',             NULL, NULL, NULL, '75kg production'),

  ('model_loring_s7_nighthawk',   'brand_loring',          'roaster',          'S7 Nighthawk',    NULL, NULL, NULL, '7kg recirculating'),
  ('model_loring_s15_falcon',     'brand_loring',          'roaster',          'S15 Falcon',      NULL, NULL, NULL, '15kg flagship'),
  ('model_loring_s35_kestrel',    'brand_loring',          'roaster',          'S35 Kestrel',     NULL, NULL, NULL, '35kg high-output'),
  ('model_loring_s70_peregrine',  'brand_loring',          'roaster',          'S70 Peregrine',   NULL, NULL, NULL, '70kg production'),

  ('model_diedrich_ir5',          'brand_diedrich',        'roaster',          'IR-5',            NULL, NULL, NULL, '5kg shop roaster'),
  ('model_diedrich_ir12',         'brand_diedrich',        'roaster',          'IR-12',           NULL, NULL, NULL, '12kg'),
  ('model_diedrich_ir24',         'brand_diedrich',        'roaster',          'IR-24',           NULL, NULL, NULL, '24kg production'),
  ('model_diedrich_ir70',         'brand_diedrich',        'roaster',          'IR-70',           NULL, NULL, NULL, '70kg high-output'),

  ('model_mill_city_1k',          'brand_mill_city',       'roaster',          'North TJ-067 (1kg)',NULL, NULL, NULL, '1kg sample roaster'),
  ('model_mill_city_2k',          'brand_mill_city',       'roaster',          'North TJ-2 (2kg)',NULL, NULL, NULL, NULL),
  ('model_mill_city_6k',          'brand_mill_city',       'roaster',          '6kg',             NULL, NULL, NULL, NULL),
  ('model_mill_city_15k',         'brand_mill_city',       'roaster',          '15kg',            NULL, NULL, NULL, NULL),
  ('model_mill_city_22k',         'brand_mill_city',       'roaster',          '22kg',            NULL, NULL, NULL, NULL),

  ('model_san_franciscan_sf6',    'brand_san_franciscan',  'roaster',          'SF-6',            NULL, NULL, NULL, '6lb shop roaster'),
  ('model_san_franciscan_sf25',   'brand_san_franciscan',  'roaster',          'SF-25',           NULL, NULL, NULL, '25lb'),
  ('model_san_franciscan_sf75',   'brand_san_franciscan',  'roaster',          'SF-75',           NULL, NULL, NULL, '75lb'),

  ('model_giesen_w1',             'brand_giesen',          'roaster',          'W1A',             NULL, NULL, NULL, '1kg sample'),
  ('model_giesen_w6',             'brand_giesen',          'roaster',          'W6A',             NULL, NULL, NULL, '6kg shop'),
  ('model_giesen_w15',            'brand_giesen',          'roaster',          'W15A',            NULL, NULL, NULL, '15kg'),
  ('model_giesen_w30',            'brand_giesen',          'roaster',          'W30A',            NULL, NULL, NULL, '30kg'),

  ('model_imf_rm15',              'brand_imf',             'roaster',          'RM-15',           NULL, NULL, NULL, '15kg double-drum'),
  ('model_imf_rm30',              'brand_imf',             'roaster',          'RM-30',           NULL, NULL, NULL, NULL),

  ('model_stronghold_s7x',        'brand_stronghold',      'roaster',          'S7X',             NULL, NULL, NULL, '700g sample roaster'),
  ('model_stronghold_s9x',        'brand_stronghold',      'roaster',          'S9X',             NULL, NULL, NULL, NULL),

  ('model_aillio_bullet_r1',      'brand_aillio',          'roaster',          'Bullet R1',       'v2', NULL, NULL, '1kg sample / micro production'),
  ('model_ikawa_pro100',           'brand_ikawa',           'roaster',          'Pro100',          NULL, NULL, NULL, '100g sample'),
  ('model_petroncini_tt12',       'brand_petroncini',      'roaster',          'TT12',            NULL, NULL, NULL, NULL),
  ('model_buhler_roastmaster',    'brand_buhler',          'roaster',          'RoastMaster',     NULL, NULL, NULL, 'Industrial'),
  ('model_toper_tkmsx',           'brand_toper',           'roaster',          'TKMSX-15',        NULL, NULL, NULL, '15kg'),

  -- ============================================================
  -- WATER TREATMENT
  -- ============================================================
  ('model_everpure_4c_lm',        'brand_everpure',        'water_treatment',  '4C-LM',           NULL, NULL, NULL, 'Espresso machine inline'),
  ('model_everpure_4dc',          'brand_everpure',        'water_treatment',  '4DC',             NULL, NULL, NULL, NULL),
  ('model_bwt_bestmax',           'brand_bwt',             'water_treatment',  'Bestmax Premium', NULL, NULL, NULL, 'Mineral-balanced filter'),
  ('model_3m_hf45',               'brand_3m',              'water_treatment',  'HF45-S',          NULL, NULL, NULL, NULL),
  ('model_pentair_everpure_h300','brand_pentair',         'water_treatment',  'Everpure H-300',  NULL, NULL, NULL, NULL);


-- ============================================================
-- MAINTENANCE TEMPLATES (~30 standard tasks)
--
-- Two audiences:
--   is_recommended_only=true   → shown to operators as guidance for the
--                                client (cafe staff). Not added to the
--                                tracking schedule by default. Daily/weekly
--                                tasks for client-side equipment fall here.
--   is_recommended_only=false  → added to the schedule with next_due_at,
--                                surfaced in dashboards, logged when done.
-- ============================================================
INSERT INTO public.maintenance_template (template_id, category, task_name, description, frequency_type, frequency_interval, is_recommended_only, is_critical, estimated_minutes, parts_typically_needed) VALUES
  -- Espresso machine — client-recommended (daily/weekly)
  ('mt_espresso_backflush_water',   'espresso_machine', 'Backflush groups with water',
    'Insert blind basket, run cycle 3-5 times per group. Removes loose grounds + oils.',
    'daily', 1, true, false, 5, NULL),

  ('mt_espresso_steam_wand_purge',  'espresso_machine', 'Purge + wipe steam wand',
    'Purge each steam wand for 2 seconds, wipe with damp cloth after every drink.',
    'daily', 1, true, false, 2, NULL),

  ('mt_espresso_backflush_cafiza',  'espresso_machine', 'Backflush with detergent (Cafiza)',
    'Add ~3g detergent to blind basket, run 5 cycles, rinse with 10 water cycles. Removes oil buildup.',
    'weekly', 1, true, false, 15, '[{"name":"Cafiza or equivalent espresso detergent"}]'),

  ('mt_espresso_steam_wand_descale','espresso_machine', 'Steam wand interior descale',
    'Submerge wand in hot water + steam wand cleaner, let soak 10 min, purge thoroughly.',
    'weekly', 1, true, false, 15, '[{"name":"Rinza or equivalent steam wand cleaner"}]'),

  -- Espresso machine — operator-tracked (monthly+)
  ('mt_espresso_shower_screens',    'espresso_machine', 'Replace shower screens',
    'Replace shower screens (also called dispersion screens). Prevents uneven extraction + bitter taste.',
    'monthly', 3, false, false, 20, '[{"name":"Shower screen", "qty_per_group":1}]'),

  ('mt_espresso_group_gaskets',     'espresso_machine', 'Inspect + replace group gaskets',
    'Inspect for cracking, deformation, leaks during brew. Replace if needed.',
    'semi_annual', 1, false, true, 30, '[{"name":"Group head gasket", "qty_per_group":1}]'),

  ('mt_espresso_boiler_descale',    'espresso_machine', 'Descale boilers (water hardness dependent)',
    'Use manufacturer-approved descaler. Critical if water hardness exceeds spec. Skip if reverse-osmosis water.',
    'annual', 1, false, true, 90, '[{"name":"Manufacturer-approved descaler"}]'),

  ('mt_espresso_water_filter',      'espresso_machine', 'Replace inline water filter',
    'Replace per cartridge spec (typically 12 months, sooner in hard-water areas).',
    'annual', 1, false, true, 15, '[{"name":"Inline water filter cartridge"}]'),

  ('mt_espresso_pm_service',        'espresso_machine', 'Annual PM service',
    'Full preventive service: pump rebuild kit, all gaskets, pressure calibration, safety check. Usually outsourced to manufacturer-certified tech.',
    'annual', 1, false, true, 240, '[{"name":"Annual PM kit (varies by brand)"}]'),


  -- Grinder — client-recommended
  ('mt_grinder_hopper_doser_clean', 'grinder', 'Empty + wipe hopper and doser',
    'Empty hopper, wipe with dry cloth (no water), tap out fines from doser.',
    'daily', 1, true, false, 5, NULL),

  ('mt_grinder_burr_brush',         'grinder', 'Brush burrs dry',
    'Power off, remove top burr carrier, brush both burrs with a dedicated grinder brush. No water.',
    'weekly', 1, true, false, 10, '[{"name":"Grinder brush"}]'),

  -- Grinder — operator-tracked
  ('mt_grinder_cleaning_tablets',   'grinder', 'Burr clean with cleaning tablets (Grindz)',
    'Run 1 dose of grinder cleaning tablets through, follow with coffee purge until clean.',
    'monthly', 1, false, false, 10, '[{"name":"Grindz or equivalent grinder cleaner"}]'),

  ('mt_grinder_burr_align',         'grinder', 'Check burr alignment + zero point',
    'Re-zero burrs per manufacturer spec. Misalignment causes uneven extraction.',
    'quarterly', 1, false, false, 30, NULL),

  ('mt_grinder_burr_replace_lbs',   'grinder', 'Replace burrs (volume-based)',
    'Replace burrs based on lbs ground. Lifespan varies by model — see typical_lifespan_lbs on the model.',
    'lbs_processed', 1000, false, true, 60, '[{"name":"Burr set (model-specific)"}]'),


  -- Brewer
  ('mt_brewer_chamber_clean',       'brewer', 'Clean brew chamber + sprayhead',
    'Wipe chamber, scrub sprayhead, rinse decanters.',
    'daily', 1, true, false, 10, NULL),

  ('mt_brewer_descale_dispense',    'brewer', 'Descale dispense path',
    'Run descaling cycle per machine. Removes mineral buildup that slows flow.',
    'monthly', 1, false, false, 30, '[{"name":"Brewer descaling solution"}]'),

  ('mt_brewer_water_filter',        'brewer', 'Replace water filter',
    'Replace inline cartridge.',
    'semi_annual', 1, false, false, 15, '[{"name":"Brewer water filter cartridge"}]'),

  ('mt_brewer_full_descale',        'brewer', 'Full descale + seal inspection',
    'Full descale cycle, inspect + replace dispense valve seals if needed.',
    'annual', 1, false, true, 90, '[{"name":"Dispense seals kit"}]'),


  -- Roaster (in-house, operator-tracked from day 1)
  ('mt_roaster_chaff_collector',    'roaster', 'Empty chaff collector',
    'Empty chaff collector + cyclone. Critical for fire prevention — chaff is highly flammable.',
    'daily', 1, false, true, 5, NULL),

  ('mt_roaster_drum_brush',         'roaster', 'Brush drum interior',
    'Brush out drum with stainless wire brush. Removes sugar buildup that causes uneven roasts.',
    'daily', 1, false, false, 10, '[{"name":"Stainless drum brush"}]'),

  ('mt_roaster_cooling_tray',       'roaster', 'Clean cooling tray + sweeper',
    'Empty + wipe cooling tray. Inspect sweeper arm for chaff buildup.',
    'daily', 1, false, false, 10, NULL),

  ('mt_roaster_gas_pressure_check', 'roaster', 'Gas pressure verification',
    'Verify gas pressure at idle + during burn. Drift indicates regulator issue or supply problem.',
    'weekly', 1, false, true, 10, NULL),

  ('mt_roaster_exhaust_fan',        'roaster', 'Inspect exhaust fan + ductwork',
    'Visual inspect exhaust fan blades, ductwork joints for chaff/creosote buildup. Major fire risk.',
    'monthly', 1, false, true, 20, NULL),

  ('mt_roaster_thermocouple_check', 'roaster', 'Thermocouple calibration check',
    'Verify BT/ET probes read identically when stable. Replace if drift > 5°F.',
    'monthly', 1, false, true, 15, '[{"name":"Replacement thermocouple", "note":"Only if calibration fails"}]'),

  ('mt_roaster_bearing_grease',     'roaster', 'Lubricate drum bearings',
    'Apply high-temp bearing grease per drum manufacturer spec. Skipping causes premature bearing failure.',
    'quarterly', 1, false, true, 30, '[{"name":"High-temp bearing grease"}]'),

  ('mt_roaster_chain_tension',      'roaster', 'Drum drive chain inspection + tension',
    'Inspect chain for stretch, slack, missing links. Adjust tension per spec.',
    'quarterly', 1, false, false, 20, NULL),

  ('mt_roaster_gasket_replace',     'roaster', 'Replace drum gaskets',
    'Replace front face and rear gaskets. Leaks cause uneven airflow + smoke escape.',
    'annual', 1, false, true, 120, '[{"name":"Drum gasket kit (model-specific)"}]'),

  ('mt_roaster_burner_clean',       'roaster', 'Burner head cleaning',
    'Disassemble burner, clean ports of carbon + debris, verify flame pattern.',
    'annual', 1, false, true, 90, NULL),

  ('mt_roaster_full_pm',            'roaster', 'Annual full PM service',
    'Full preventive maintenance: gaskets, bearings, drive chain, burner, all safety interlocks, electrical inspection. Usually done by manufacturer or certified tech.',
    'annual', 1, false, true, 360, NULL),

  -- Roaster usage-based: batches since chaff cleanout (already tracked via batches_since_chaff field, this template lets it be scheduled)
  ('mt_roaster_chaff_batches',      'roaster', 'Chaff cleanout (per N batches)',
    'Empty chaff collector + cyclone every N batches. Overrides daily cadence — chaff fills fastest under high-batch days.',
    'lbs_processed', 200, false, true, 5, NULL),


  -- Water treatment
  ('mt_water_filter_replace',       'water_treatment', 'Replace water filter cartridge',
    'Replace per manufacturer-spec gallon/month rating.',
    'semi_annual', 1, false, true, 15, '[{"name":"Filter cartridge (model-specific)"}]'),

  ('mt_water_hardness_test',        'water_treatment', 'Water hardness test',
    'Test source water + softened water for hardness (TDS, calcium). Drives descale frequency.',
    'quarterly', 1, false, false, 10, '[{"name":"Water hardness test strips"}]'),


  -- Packaging
  ('mt_packaging_seal_jaws_clean',  'packaging', 'Clean sealing jaws',
    'Remove buildup, replace teflon if scorched.',
    'weekly', 1, false, false, 15, NULL),

  ('mt_packaging_full_pm',          'packaging', 'Annual PM',
    'Full PM per manufacturer schedule.',
    'annual', 1, false, true, 240, NULL);


-- ============================================================
-- TECH CONTACTS — global manufacturer support
-- ============================================================
INSERT INTO public.equipment_tech_contact (contact_id, brand_id, company_name, phone, email, website, notes) VALUES
  ('tc_la_marzocco_usa', 'brand_la_marzocco',     'La Marzocco USA',         '+1-509-922-8978', 'service@lamarzoccousa.com',  'https://lamarzoccousa.com/service/', 'Authorized service network across US'),
  ('tc_slayer_service',  'brand_slayer',          'Slayer Service',          NULL,              'service@slayerespresso.com', 'https://slayerespresso.com/support',  NULL),
  ('tc_synesso_service', 'brand_synesso',         'Synesso Service',         '+1-206-764-0600', 'support@synesso.com',         'https://synesso.com/contact',         NULL),
  ('tc_ns_usa',          'brand_nuova_simonelli', 'Nuova Distribution USA',  '+1-360-833-7140', NULL,                          'https://www.nuovasimonelli.com/contact', NULL),
  ('tc_va_service',      'brand_victoria_arduino','Victoria Arduino Service',NULL,              NULL,                          'https://www.victoriaarduino.com/contact', NULL),
  ('tc_modbar_service',  'brand_modbar',          'Modbar Service',          NULL,              'service@modbar.com',          'https://modbar.com/support',          NULL),

  ('tc_mahlkonig_us',    'brand_mahlkonig',       'Mahlkönig USA',           NULL,              NULL,                          'https://www.mahlkoenig.com/us/contact', NULL),
  ('tc_mazzer_us',       'brand_mazzer',          'Mazzer USA Distribution', NULL,              NULL,                          'https://www.mazzer.com/contact',      NULL),
  ('tc_ditting_service', 'brand_ditting',         'Ditting Service',         NULL,              NULL,                          'https://www.dittingswiss.ch/contact', NULL),
  ('tc_eureka_us',       'brand_eureka',          'Eureka USA',              NULL,              NULL,                          'https://www.eureka.co.it/contacts/',  NULL),

  ('tc_curtis_service',  'brand_curtis',          'Wilbur Curtis Service',   '+1-800-421-6150', 'service@wilburcurtis.com',    'https://wilburcurtis.com/service',    '24/7 service line'),
  ('tc_bunn_service',    'brand_bunn',            'BUNN Tech Support',       '+1-800-286-6661', NULL,                          'https://www.bunn.com/customer-service',NULL),
  ('tc_fetco_service',   'brand_fetco',           'Fetco Tech Support',      '+1-800-338-2699', NULL,                          'https://www.fetco.com/support',       NULL),
  ('tc_marco_uk',        'brand_marco',           'Marco Beverage Systems',  NULL,              NULL,                          'https://www.marcobeveragesystems.com/contact', NULL),

  ('tc_probat_us',       'brand_probat',          'Probat USA',              '+1-901-251-3033', 'service@probat-burns.com',    'https://www.probat.com/en/service.html', NULL),
  ('tc_loring_service',  'brand_loring',          'Loring Service',          '+1-707-526-7215', 'service@loring.com',          'https://loring.com/service',          NULL),
  ('tc_diedrich_service','brand_diedrich',        'Diedrich Service',        '+1-208-263-1276', NULL,                          'https://diedrichroasters.com/service', NULL),
  ('tc_mill_city_service','brand_mill_city',      'Mill City Roasters Service', NULL,           NULL,                          'https://millcityroasters.com/contact', NULL),
  ('tc_san_franciscan',  'brand_san_franciscan',  'San Franciscan Roaster Service', NULL,       NULL,                          'https://sanfranciscanroaster.com/contact', NULL),
  ('tc_giesen_service',  'brand_giesen',          'Giesen Service',          NULL,              'service@giesen.com',          'https://giesencoffeeroasters.com/service', NULL),

  ('tc_everpure_service','brand_everpure',        'Everpure Service',        '+1-800-942-1153', NULL,                          'https://www.everpure.com/support',    NULL),
  ('tc_bwt_water',       'brand_bwt',             'BWT Water Tech Support',  NULL,              NULL,                          'https://www.bwt.com/contact',         NULL);
