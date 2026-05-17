-- ============================================================
-- Equipment catalog expansion — full commercial model coverage
-- ============================================================
-- Initial seed (..007) covered top 2-5 models per major brand. This
-- expansion fills in the rest so picking a machine from the brand
-- dropdown doesn't lead to "model not listed" for common gear.
--
-- ON CONFLICT DO NOTHING preserves any model_id already in use by
-- existing equipment rows. Safe to re-run.
--
-- Sources: manufacturer spec sheets / current commercial lineups as
-- of 2026. Covers commercial-tier only — pure home/prosumer pieces
-- generally omitted unless they show up in serious shops.
-- ============================================================

INSERT INTO public.equipment_model
  (equipment_model_id, brand_id, category, model_name, generation, typical_lifespan_lbs, typical_lifespan_hours, notes)
VALUES

  -- ============================================================
  -- ESPRESSO MACHINES — group-count variants matter
  -- ============================================================

  -- La Marzocco (full commercial lineup)
  ('model_lm_linea_pb_2g',         'brand_la_marzocco', 'espresso_machine', 'Linea PB',         '2-group',       NULL, 8000, 'Paddle group, dual boiler'),
  ('model_lm_linea_pb_3g',         'brand_la_marzocco', 'espresso_machine', 'Linea PB',         '3-group',       NULL, 8000, 'Paddle group, dual boiler'),
  ('model_lm_linea_pb_x_2g',       'brand_la_marzocco', 'espresso_machine', 'Linea PB X',       '2-group',       NULL, 8000, 'Smart connected variant'),
  ('model_lm_linea_pb_x_3g',       'brand_la_marzocco', 'espresso_machine', 'Linea PB X',       '3-group',       NULL, 8000, 'Smart connected variant'),
  ('model_lm_linea_classic_s_2g',  'brand_la_marzocco', 'espresso_machine', 'Linea Classic S',  '2-group',       NULL, 8000, 'Refreshed Linea Classic'),
  ('model_lm_linea_classic_s_3g',  'brand_la_marzocco', 'espresso_machine', 'Linea Classic S',  '3-group',       NULL, 8000, NULL),
  ('model_lm_linea_micra',         'brand_la_marzocco', 'espresso_machine', 'Linea Micra',      NULL,            NULL, 4000, 'Compact prosumer single-boiler'),
  ('model_lm_gb5_x_2g',            'brand_la_marzocco', 'espresso_machine', 'GB5 X',            '2-group',       NULL, 8000, NULL),
  ('model_lm_gb5_x_3g',            'brand_la_marzocco', 'espresso_machine', 'GB5 X',            '3-group',       NULL, 8000, NULL),
  ('model_lm_kb90_3g',             'brand_la_marzocco', 'espresso_machine', 'KB90',             '3-group',       NULL, 10000, 'High-volume saturated group, 3-group'),
  ('model_lm_strada_mp_2g',        'brand_la_marzocco', 'espresso_machine', 'Strada MP',        '2-group',       NULL, 8000, 'Manual paddle'),
  ('model_lm_strada_mp_3g',        'brand_la_marzocco', 'espresso_machine', 'Strada MP',        '3-group',       NULL, 8000, NULL),
  ('model_lm_strada_ep_3g',        'brand_la_marzocco', 'espresso_machine', 'Strada EP',        '3-group',       NULL, 8000, NULL),
  ('model_lm_strada_av_2g',        'brand_la_marzocco', 'espresso_machine', 'Strada AV',        '2-group',       NULL, 8000, 'Automatic volumetric'),
  ('model_lm_gs3_mp',              'brand_la_marzocco', 'espresso_machine', 'GS3',              'MP',            NULL, 6000, 'Single group manual paddle, prosumer'),
  ('model_lm_gs3_av',              'brand_la_marzocco', 'espresso_machine', 'GS3',              'AV',            NULL, 6000, 'Single group automatic volumetric'),

  -- Slayer — full commercial lineup with group counts
  ('model_slayer_espresso_1g',     'brand_slayer', 'espresso_machine', 'Espresso',     '1-group',       NULL, 7000, 'Manual paddle, pre-brew, single group'),
  ('model_slayer_espresso_2g',     'brand_slayer', 'espresso_machine', 'Espresso',     '2-group',       NULL, 8000, 'Manual paddle, pre-brew'),
  ('model_slayer_steam_ep_1g',     'brand_slayer', 'espresso_machine', 'Steam EP',     '1-group',       NULL, 7000, 'Electronic paddle'),
  ('model_slayer_steam_ep_2g',     'brand_slayer', 'espresso_machine', 'Steam EP',     '2-group',       NULL, 8000, 'Electronic paddle'),
  ('model_slayer_steam_ep_3g',     'brand_slayer', 'espresso_machine', 'Steam EP',     '3-group',       NULL, 8000, 'Electronic paddle'),
  ('model_slayer_steam_lp_1g',     'brand_slayer', 'espresso_machine', 'Steam LP',     '1-group',       NULL, 7000, 'Low-pressure steam'),
  ('model_slayer_steam_lp_2g',     'brand_slayer', 'espresso_machine', 'Steam LP',     '2-group',       NULL, 8000, 'Low-pressure steam'),
  ('model_slayer_steam_x_1g',      'brand_slayer', 'espresso_machine', 'Steam X',      '1-group',       NULL, 7000, 'Entry-tier high-performance'),
  ('model_slayer_steam_x_2g',      'brand_slayer', 'espresso_machine', 'Steam X',      '2-group',       NULL, 8000, NULL),
  ('model_slayer_steam_x_3g',      'brand_slayer', 'espresso_machine', 'Steam X',      '3-group',       NULL, 8000, NULL),

  -- Synesso
  ('model_synesso_mvp_hydra_2g',   'brand_synesso', 'espresso_machine', 'MVP Hydra',   '2-group',       NULL, 8000, NULL),
  ('model_synesso_mvp_hydra_3g',   'brand_synesso', 'espresso_machine', 'MVP Hydra',   '3-group',       NULL, 8000, NULL),
  ('model_synesso_s100',           'brand_synesso', 'espresso_machine', 'S100',        '1-group',       NULL, 7000, 'S-Series single group'),
  ('model_synesso_s200',           'brand_synesso', 'espresso_machine', 'S200',        '2-group',       NULL, 8000, NULL),
  ('model_synesso_s300',           'brand_synesso', 'espresso_machine', 'S300',        '3-group',       NULL, 8000, NULL),
  ('model_synesso_cyncra_2g',      'brand_synesso', 'espresso_machine', 'Cyncra',      '2-group',       NULL, 8000, 'Discontinued — still common in shops'),
  ('model_synesso_cyncra_3g',      'brand_synesso', 'espresso_machine', 'Cyncra',      '3-group',       NULL, 8000, NULL),
  ('model_synesso_sabre_2g',       'brand_synesso', 'espresso_machine', 'Sabre',       '2-group',       NULL, 8000, 'Volumetric'),

  -- Nuova Simonelli
  ('model_ns_aurelia_wave_ux_t3_2g','brand_nuova_simonelli','espresso_machine','Aurelia Wave UX','T3 2-group', NULL, 8000, NULL),
  ('model_ns_aurelia_wave_ux_t3_3g','brand_nuova_simonelli','espresso_machine','Aurelia Wave UX','T3 3-group', NULL, 8000, NULL),
  ('model_ns_aurelia_wave_t3_2g',  'brand_nuova_simonelli', 'espresso_machine', 'Aurelia Wave', 'T3 2-group',  NULL, 8000, NULL),
  ('model_ns_aurelia_wave_t3_3g',  'brand_nuova_simonelli', 'espresso_machine', 'Aurelia Wave', 'T3 3-group',  NULL, 8000, NULL),
  ('model_ns_aurelia_ii_2g',       'brand_nuova_simonelli', 'espresso_machine', 'Aurelia II',   '2-group',     NULL, 7000, 'Discontinued — still common'),
  ('model_ns_aurelia_ii_3g',       'brand_nuova_simonelli', 'espresso_machine', 'Aurelia II',   '3-group',     NULL, 7000, NULL),
  ('model_ns_appia_life_xt_2g',    'brand_nuova_simonelli', 'espresso_machine', 'Appia Life XT','2-group',     NULL, 7000, NULL),
  ('model_ns_appia_life_xt_3g',    'brand_nuova_simonelli', 'espresso_machine', 'Appia Life XT','3-group',     NULL, 7000, NULL),
  ('model_ns_appia_life_compact',  'brand_nuova_simonelli', 'espresso_machine', 'Appia Life Compact', '1-group', NULL, 6000, NULL),
  ('model_ns_musica',              'brand_nuova_simonelli', 'espresso_machine', 'Musica',       NULL,          NULL, 4000, 'Prosumer'),
  ('model_ns_oscar_ii',            'brand_nuova_simonelli', 'espresso_machine', 'Oscar II',     NULL,          NULL, 4000, 'Prosumer'),

  -- Victoria Arduino
  ('model_va_black_eagle_va388_3g','brand_victoria_arduino','espresso_machine','Black Eagle',  'VA388 3-group',NULL, 10000, NULL),
  ('model_va_black_eagle_maverick','brand_victoria_arduino','espresso_machine','Black Eagle Maverick',NULL,    NULL, 10000, NULL),
  ('model_va_white_eagle_v2_2g',   'brand_victoria_arduino','espresso_machine','White Eagle V2','2-group',     NULL, 8000, NULL),
  ('model_va_white_eagle_v2_3g',   'brand_victoria_arduino','espresso_machine','White Eagle V2','3-group',     NULL, 8000, NULL),
  ('model_va_eagle_one_2g',        'brand_victoria_arduino','espresso_machine','Eagle One',    '2-group',     NULL, 8000, NULL),
  ('model_va_eagle_one_prima',     'brand_victoria_arduino','espresso_machine','Eagle One Prima EXP', '1-group', NULL, 6000, NULL),
  ('model_va_e1_prima',            'brand_victoria_arduino','espresso_machine','E1 Prima',     '1-group',     NULL, 6000, NULL),
  ('model_va_theresia',            'brand_victoria_arduino','espresso_machine','Theresia',     '1-group',     NULL, 6000, NULL),

  -- Rancilio
  ('model_rancilio_classe_11_xc_2g','brand_rancilio', 'espresso_machine', 'Classe 11 XCelsius','2-group',     NULL, 8000, NULL),
  ('model_rancilio_classe_11_xc_3g','brand_rancilio', 'espresso_machine', 'Classe 11 XCelsius','3-group',     NULL, 8000, NULL),
  ('model_rancilio_classe_9_2g',   'brand_rancilio',  'espresso_machine', 'Classe 9',      '2-group',         NULL, 7000, NULL),
  ('model_rancilio_classe_9_3g',   'brand_rancilio',  'espresso_machine', 'Classe 9',      '3-group',         NULL, 7000, NULL),
  ('model_rancilio_classe_7_2g',   'brand_rancilio',  'espresso_machine', 'Classe 7',      '2-group',         NULL, 7000, NULL),
  ('model_rancilio_classe_5_1g',   'brand_rancilio',  'espresso_machine', 'Classe 5',      '1-group',         NULL, 6000, NULL),

  -- Faema, La Cimbali (2-group, 3-group variants)
  ('model_faema_e71e_2g',          'brand_faema',     'espresso_machine', 'E71E',          '2-group',         NULL, 8000, NULL),
  ('model_faema_e71e_3g',          'brand_faema',     'espresso_machine', 'E71E',          '3-group',         NULL, 8000, NULL),
  ('model_faema_e98_re_2g',        'brand_faema',     'espresso_machine', 'E98 RE',        '2-group',         NULL, 8000, NULL),
  ('model_faema_e98_re_3g',        'brand_faema',     'espresso_machine', 'E98 RE',        '3-group',         NULL, 8000, NULL),

  ('model_cimbali_m100_2g',        'brand_la_cimbali','espresso_machine', 'M100',          '2-group',         NULL, 8000, NULL),
  ('model_cimbali_m100_3g',        'brand_la_cimbali','espresso_machine', 'M100',          '3-group',         NULL, 8000, NULL),
  ('model_cimbali_m200_2g',        'brand_la_cimbali','espresso_machine', 'M200',          '2-group',         NULL, 8000, NULL),
  ('model_cimbali_m200_3g',        'brand_la_cimbali','espresso_machine', 'M200',          '3-group',         NULL, 8000, NULL),
  ('model_cimbali_m39_dosatron_2g','brand_la_cimbali','espresso_machine', 'M39 Dosatron',  '2-group',         NULL, 8000, NULL),

  -- Modbar (modular under-counter)
  ('model_modbar_espresso_2g',     'brand_modbar',    'espresso_machine', 'Espresso AV',    '2-group',         NULL, 7000, NULL),
  ('model_modbar_steam_2g',        'brand_modbar',    'espresso_machine', 'Steam Module',   '2-wand',          NULL, 7000, NULL),
  ('model_modbar_pour_over',       'brand_modbar',    'espresso_machine', 'Pour-Over',      NULL,              NULL, 7000, 'Under-counter pour-over module'),

  -- Kees van der Westen
  ('model_kees_mirage_idrocompresso_2g','brand_kees_vdw','espresso_machine','Mirage Idrocompresso','2-group',  NULL, 8000, NULL),
  ('model_kees_mirage_triplette',  'brand_kees_vdw',  'espresso_machine', 'Mirage Triplette','3-group',        NULL, 8000, NULL),
  ('model_kees_spirit_duette',     'brand_kees_vdw',  'espresso_machine', 'Spirit',         'Duette 2-group',  NULL, 8000, NULL),
  ('model_kees_spirit_triplette',  'brand_kees_vdw',  'espresso_machine', 'Spirit',         'Triplette 3-group', NULL, 8000, NULL),

  -- Sanremo (group variants)
  ('model_sanremo_cafe_racer_2g',  'brand_sanremo',   'espresso_machine', 'Cafe Racer',    '2-group',          NULL, 8000, NULL),
  ('model_sanremo_cafe_racer_3g',  'brand_sanremo',   'espresso_machine', 'Cafe Racer',    '3-group',          NULL, 8000, NULL),
  ('model_sanremo_opera_2_0_2g',   'brand_sanremo',   'espresso_machine', 'Opera 2.0',     '2-group',          NULL, 9000, NULL),
  ('model_sanremo_opera_2_0_3g',   'brand_sanremo',   'espresso_machine', 'Opera 2.0',     '3-group',          NULL, 9000, NULL),
  ('model_sanremo_zoe_2g',         'brand_sanremo',   'espresso_machine', 'Zoe',           '2-group',          NULL, 7000, NULL),
  ('model_sanremo_verona_2g',      'brand_sanremo',   'espresso_machine', 'Verona',        '2-group',          NULL, 7000, NULL),

  -- Wega (commonly under-the-radar but common in independent shops)
  ('model_wega_polaris_2g',        'brand_wega',      'espresso_machine', 'Polaris EVD',   '2-group',          NULL, 7000, NULL),
  ('model_wega_polaris_3g',        'brand_wega',      'espresso_machine', 'Polaris EVD',   '3-group',          NULL, 7000, NULL),
  ('model_wega_vela_evd_2g',       'brand_wega',      'espresso_machine', 'Vela EVD',      '2-group',          NULL, 7000, NULL),
  ('model_wega_vela_evd_3g',       'brand_wega',      'espresso_machine', 'Vela EVD',      '3-group',          NULL, 7000, NULL),

  -- ECM, Profitec, Lelit, Bezzera (mostly prosumer, included for completeness)
  ('model_ecm_mechanika_v_slim',   'brand_ecm',       'espresso_machine', 'Mechanika V Slim', NULL,            NULL, 5000, NULL),
  ('model_ecm_synchronika_dual',   'brand_ecm',       'espresso_machine', 'Synchronika',   'Dual Boiler',      NULL, 5000, NULL),
  ('model_profitec_pro_700',       'brand_profitec',  'espresso_machine', 'Pro 700',       NULL,               NULL, 5000, NULL),
  ('model_profitec_pro_800',       'brand_profitec',  'espresso_machine', 'Pro 800',       NULL,               NULL, 5000, 'Lever'),
  ('model_profitec_pro_300',       'brand_profitec',  'espresso_machine', 'Pro 300',       NULL,               NULL, 4000, NULL),
  ('model_lelit_elizabeth',        'brand_lelit',     'espresso_machine', 'Elizabeth',     NULL,               NULL, 4000, NULL),
  ('model_lelit_bianca_v3',        'brand_lelit',     'espresso_machine', 'Bianca',        'v3',               NULL, 4000, NULL),


  -- ============================================================
  -- GRINDERS — burr life is volume-dependent (lifespan_lbs)
  -- ============================================================

  ('model_mahlkonig_ek_omnia',     'brand_mahlkonig', 'grinder', 'EK Omnia',         NULL, 1500, NULL, 'EK43 successor for all brew methods'),
  ('model_mahlkonig_ek43_t',       'brand_mahlkonig', 'grinder', 'EK43 T',           NULL, 1500, NULL, 'Turkish-fine variant'),
  ('model_mahlkonig_e80_supreme_gbw','brand_mahlkonig','grinder', 'E80 Supreme GBW', NULL, 2000, NULL, 'Grind-by-weight'),
  ('model_mahlkonig_e65s_gbw',     'brand_mahlkonig', 'grinder', 'E65S GBW',         NULL, 1200, NULL, 'Grind-by-weight'),
  ('model_mahlkonig_k30_vario',    'brand_mahlkonig', 'grinder', 'K30 Vario',        NULL, 1500, NULL, NULL),
  ('model_mahlkonig_x54',          'brand_mahlkonig', 'grinder', 'X54',              NULL, 900,  NULL, 'Home single-dose'),

  ('model_mazzer_robur_e',         'brand_mazzer', 'grinder', 'Robur',         'E electronic',    1800, NULL, NULL),
  ('model_mazzer_kony_e',          'brand_mazzer', 'grinder', 'Kony',          'E electronic',    1500, NULL, NULL),
  ('model_mazzer_major_electronic','brand_mazzer', 'grinder', 'Major',         'Electronic',      1200, NULL, NULL),
  ('model_mazzer_mini_e',          'brand_mazzer', 'grinder', 'Mini',          'E electronic',     900, NULL, NULL),
  ('model_mazzer_super_jolly_e',   'brand_mazzer', 'grinder', 'Super Jolly',   'Electronic',      1000, NULL, NULL),
  ('model_mazzer_philos',          'brand_mazzer', 'grinder', 'Philos',        NULL,              1500, NULL, 'Brew-focused'),
  ('model_mazzer_lux_d',           'brand_mazzer', 'grinder', 'Lux D',         NULL,              1200, NULL, NULL),

  ('model_eureka_mignon_silenzio', 'brand_eureka', 'grinder', 'Mignon Silenzio',  NULL,           800, NULL, NULL),
  ('model_eureka_mignon_xl',       'brand_eureka', 'grinder', 'Mignon XL',         NULL,           800, NULL, NULL),
  ('model_eureka_atom_specialty_65','brand_eureka','grinder', 'Atom Specialty 65', NULL,          1200, NULL, NULL),
  ('model_eureka_atom_specialty_75','brand_eureka','grinder', 'Atom Specialty 75', NULL,          1500, NULL, NULL),
  ('model_eureka_olympus_75e',     'brand_eureka', 'grinder', 'Olympus 75E',       NULL,          1800, NULL, NULL),
  ('model_eureka_helios_75',       'brand_eureka', 'grinder', 'Helios 75',         NULL,          1500, NULL, NULL),

  ('model_ditting_kr1203',         'brand_ditting','grinder', 'KR1203',            NULL,          3500, NULL, NULL),
  ('model_ditting_kr1403',         'brand_ditting','grinder', 'KR1403',            NULL,          4500, NULL, 'High-throughput retail'),
  ('model_ditting_kfa1403',        'brand_ditting','grinder', 'KFA1403',           NULL,          4500, NULL, 'Filter grinder'),

  ('model_anfim_sp_ii_plus',       'brand_anfim',  'grinder', 'SP II Plus',        NULL,          1200, NULL, NULL),
  ('model_anfim_pratica_a',        'brand_anfim',  'grinder', 'Pratica A',         'Auto',        1000, NULL, NULL),
  ('model_anfim_caimano_on_demand','brand_anfim',  'grinder', 'Caimano OD',        NULL,          1200, NULL, NULL),

  ('model_compak_e8',              'brand_compak', 'grinder', 'E8',                NULL,          1200, NULL, NULL),
  ('model_compak_e10_essential',   'brand_compak', 'grinder', 'E10 Essential',     NULL,          1500, NULL, NULL),
  ('model_compak_pk100',           'brand_compak', 'grinder', 'PK100',             NULL,          1200, NULL, NULL),

  ('model_fiorenzato_f64evo_gbw',  'brand_fiorenzato','grinder','F64 Evo XGi',     NULL,          1200, NULL, 'Grind-by-weight'),
  ('model_fiorenzato_f83evo_gbw',  'brand_fiorenzato','grinder','F83 Evo XGi',     NULL,          1500, NULL, NULL),
  ('model_fiorenzato_allground',   'brand_fiorenzato','grinder','AllGround',       NULL,          1200, NULL, 'On-demand consumer/light commercial'),

  ('model_macap_mxa',              'brand_macap',  'grinder', 'MXA',               NULL,          1000, NULL, 'Auto on-demand'),
  ('model_macap_m4d',              'brand_macap',  'grinder', 'M4D Digital',       NULL,           900, NULL, NULL),


  -- ============================================================
  -- BREWERS — single + dual variants
  -- ============================================================

  ('model_curtis_alpha_1gt',       'brand_curtis', 'brewer', 'Alpha 1GT',        NULL, NULL, 7000, NULL),
  ('model_curtis_alpha_2gt',       'brand_curtis', 'brewer', 'Alpha 2GT',        NULL, NULL, 8000, 'Twin warmer'),
  ('model_curtis_g4_tps_2t10',     'brand_curtis', 'brewer', 'G4 TPS 2T10',      NULL, NULL, 8000, 'Thermal pourover'),
  ('model_curtis_thermopro_twin',  'brand_curtis', 'brewer', 'G4 ThermoPro Twin', NULL, NULL, 8000, NULL),
  ('model_curtis_g4_pp1s',         'brand_curtis', 'brewer', 'G4 PP1S Pour Over', NULL, NULL, 7000, NULL),

  ('model_bunn_icb_dv_single',     'brand_bunn',   'brewer', 'ICB-DV',           'Single',  NULL, 7000, NULL),
  ('model_bunn_icb_dv_twin',       'brand_bunn',   'brewer', 'ICB-DV',           'Twin',    NULL, 8000, NULL),
  ('model_bunn_axiom_dv_3',        'brand_bunn',   'brewer', 'Axiom DV-3',       NULL,      NULL, 7000, NULL),
  ('model_bunn_trifecta_mb',       'brand_bunn',   'brewer', 'Trifecta MB',      NULL,      NULL, 6000, 'Single-cup'),

  ('model_fetco_cbs_2161xts',      'brand_fetco',  'brewer', 'CBS-2161XTS',      NULL, NULL, 8000, NULL),
  ('model_fetco_cbs_2231xts',      'brand_fetco',  'brewer', 'CBS-2231XTS',      NULL, NULL, 8000, NULL),
  ('model_fetco_xts_single',       'brand_fetco',  'brewer', 'XTS Single',       NULL, NULL, 7000, NULL),
  ('model_fetco_xts_twin',         'brand_fetco',  'brewer', 'XTS Twin',         NULL, NULL, 8000, NULL),

  ('model_marco_sp9',              'brand_marco',  'brewer', 'SP9',              NULL, NULL, 7000, 'Single-cup'),
  ('model_marco_mix_pb',           'brand_marco',  'brewer', 'MIX-PB',           NULL, NULL, 7000, 'Pourover bench'),

  ('model_bravilor_bonomat_bolero','brand_bravilor','brewer','Bolero',           NULL, NULL, 7000, 'Bean-to-cup'),
  ('model_bravilor_aurora',        'brand_bravilor','brewer','Aurora',           NULL, NULL, 7000, NULL),


  -- ============================================================
  -- ROASTERS — full Loring / Probat / Diedrich / Mill City lineups
  -- ============================================================

  -- Loring (complete)
  ('model_loring_s140_falcon',     'brand_loring', 'roaster', 'S140 Falcon',     NULL, NULL, NULL, '140kg, large production'),

  -- Probat (more sizes + smart series)
  ('model_probat_p5',              'brand_probat', 'roaster', 'P5',              NULL, NULL, NULL, '5kg smart series'),
  ('model_probat_p12',             'brand_probat', 'roaster', 'P12',             NULL, NULL, NULL, '12kg smart series'),
  ('model_probat_g45',             'brand_probat', 'roaster', 'G45',             NULL, NULL, NULL, '45kg production'),
  ('model_probat_g60',             'brand_probat', 'roaster', 'G60',             NULL, NULL, NULL, '60kg production'),
  ('model_probat_g90',             'brand_probat', 'roaster', 'G90',             NULL, NULL, NULL, '90kg production'),
  ('model_probat_g120',            'brand_probat', 'roaster', 'G120',            NULL, NULL, NULL, '120kg production'),
  ('model_probat_sample_pro',      'brand_probat', 'roaster', 'Sample Pro',      NULL, NULL, NULL, 'Sample roaster'),
  ('model_probat_ug22',            'brand_probat', 'roaster', 'UG22',            NULL, NULL, NULL, 'Older 22kg, common in shops'),

  -- Diedrich (full lineup)
  ('model_diedrich_ir1',           'brand_diedrich','roaster','IR-1',            NULL, NULL, NULL, '1lb sample'),
  ('model_diedrich_ir25',          'brand_diedrich','roaster','IR-2.5',          NULL, NULL, NULL, '2.5kg small shop'),
  ('model_diedrich_ir3',           'brand_diedrich','roaster','IR-3',            NULL, NULL, NULL, '3kg'),
  ('model_diedrich_ir7',           'brand_diedrich','roaster','IR-7',            NULL, NULL, NULL, '7kg'),

  -- Mill City + North additional sizes
  ('model_mill_city_3k',           'brand_mill_city','roaster','North TJ-3 (3kg)', NULL, NULL, NULL, NULL),
  ('model_mill_city_12k',          'brand_mill_city','roaster','12kg',             NULL, NULL, NULL, NULL),
  ('model_mill_city_35k',          'brand_mill_city','roaster','35kg',             NULL, NULL, NULL, NULL),
  ('model_mill_city_70k',          'brand_mill_city','roaster','70kg',             NULL, NULL, NULL, NULL),

  -- San Franciscan (complete)
  ('model_san_franciscan_sf1',     'brand_san_franciscan','roaster','SF-1',       NULL, NULL, NULL, '1lb sample'),
  ('model_san_franciscan_sf10',    'brand_san_franciscan','roaster','SF-10',      NULL, NULL, NULL, '10lb'),
  ('model_san_franciscan_sf100',   'brand_san_franciscan','roaster','SF-100',     NULL, NULL, NULL, '100lb high-output'),

  -- Giesen (complete)
  ('model_giesen_w45',             'brand_giesen', 'roaster', 'W45A',            NULL, NULL, NULL, '45kg'),
  ('model_giesen_w60',             'brand_giesen', 'roaster', 'W60A',            NULL, NULL, NULL, '60kg'),
  ('model_giesen_w120',            'brand_giesen', 'roaster', 'W120A',           NULL, NULL, NULL, '120kg, top of the line'),

  -- IMF additional sizes
  ('model_imf_rm5',                'brand_imf',    'roaster', 'RM-5',            NULL, NULL, NULL, '5kg'),
  ('model_imf_rm60',               'brand_imf',    'roaster', 'RM-60',           NULL, NULL, NULL, '60kg'),

  -- Stronghold
  ('model_stronghold_s7p',         'brand_stronghold','roaster','S7P',           NULL, NULL, NULL, 'Production 7kg'),

  -- Bühler (industrial)
  ('model_buhler_kdg400',          'brand_buhler', 'roaster', 'KDG 400',         NULL, NULL, NULL, '400kg industrial'),

  -- Toper additional sizes
  ('model_toper_tkmsx5',           'brand_toper',  'roaster', 'TKMSX-5',         NULL, NULL, NULL, '5kg shop'),
  ('model_toper_tkmsx30',          'brand_toper',  'roaster', 'TKMSX-30',        NULL, NULL, NULL, '30kg')

ON CONFLICT (brand_id, COALESCE(company_id, ''), lower(model_name), COALESCE(generation, '')) DO NOTHING;
