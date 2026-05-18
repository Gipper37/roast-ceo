-- ============================================================
-- Restore default_unit_cost + default_markup_pct on global parts
-- ============================================================
-- Walkback of the pricing wipe in 00027. Pricing stays (rough but
-- directional starting point for new tenants) — only the unverifiable
-- identity fields (part_number, retailer supplier names) remain
-- stripped from that migration.
--
-- Values restored from the original 00021 seed.
-- ============================================================

UPDATE public.parts_catalog SET default_unit_cost =   4.50, default_markup_pct = 60 WHERE company_id IS NULL AND part_id = 'part_grouphead_gasket_e61';
UPDATE public.parts_catalog SET default_unit_cost =   4.25, default_markup_pct = 60 WHERE company_id IS NULL AND part_id = 'part_grouphead_gasket_8mm';
UPDATE public.parts_catalog SET default_unit_cost =   6.50, default_markup_pct = 50 WHERE company_id IS NULL AND part_id = 'part_shower_screen_e61';
UPDATE public.parts_catalog SET default_unit_cost =   8.00, default_markup_pct = 50 WHERE company_id IS NULL AND part_id = 'part_dispersion_screen_e61';
UPDATE public.parts_catalog SET default_unit_cost =  12.00, default_markup_pct = 50 WHERE company_id IS NULL AND part_id = 'part_steam_wand_tip_4hole';
UPDATE public.parts_catalog SET default_unit_cost =   1.50, default_markup_pct = 60 WHERE company_id IS NULL AND part_id = 'part_steam_wand_oring';
UPDATE public.parts_catalog SET default_unit_cost =  95.00, default_markup_pct = 25 WHERE company_id IS NULL AND part_id = 'part_water_filter_cuno';
UPDATE public.parts_catalog SET default_unit_cost = 125.00, default_markup_pct = 25 WHERE company_id IS NULL AND part_id = 'part_water_filter_bwt';
UPDATE public.parts_catalog SET default_unit_cost =  35.00, default_markup_pct = 30 WHERE company_id IS NULL AND part_id = 'part_descaler_puly';
UPDATE public.parts_catalog SET default_unit_cost =  22.00, default_markup_pct = 30 WHERE company_id IS NULL AND part_id = 'part_cafiza_bottle';
UPDATE public.parts_catalog SET default_unit_cost =  28.00, default_markup_pct = 30 WHERE company_id IS NULL AND part_id = 'part_rinza_bottle';
UPDATE public.parts_catalog SET default_unit_cost =   9.50, default_markup_pct = 50 WHERE company_id IS NULL AND part_id = 'part_blind_basket_58';
UPDATE public.parts_catalog SET default_unit_cost =  14.00, default_markup_pct = 50 WHERE company_id IS NULL AND part_id = 'part_filter_basket_18g';
UPDATE public.parts_catalog SET default_unit_cost =  14.50, default_markup_pct = 50 WHERE company_id IS NULL AND part_id = 'part_filter_basket_22g';
UPDATE public.parts_catalog SET default_unit_cost =  18.00, default_markup_pct = 50 WHERE company_id IS NULL AND part_id = 'part_portafilter_spout_dbl';
UPDATE public.parts_catalog SET default_unit_cost =  65.00, default_markup_pct = 40 WHERE company_id IS NULL AND part_id = 'part_pump_rebuild_procon';
UPDATE public.parts_catalog SET default_unit_cost =  45.00, default_markup_pct = 40 WHERE company_id IS NULL AND part_id = 'part_pressure_gauge_brew';
UPDATE public.parts_catalog SET default_unit_cost =  38.00, default_markup_pct = 40 WHERE company_id IS NULL AND part_id = 'part_pressure_gauge_steam';
UPDATE public.parts_catalog SET default_unit_cost =  42.00, default_markup_pct = 40 WHERE company_id IS NULL AND part_id = 'part_expansion_valve';
UPDATE public.parts_catalog SET default_unit_cost =  75.00, default_markup_pct = 40 WHERE company_id IS NULL AND part_id = 'part_solenoid_3way';
UPDATE public.parts_catalog SET default_unit_cost = 195.00, default_markup_pct = 35 WHERE company_id IS NULL AND part_id = 'part_heating_element_3000w';

-- Grinder burrs
UPDATE public.parts_catalog SET default_unit_cost = 175.00, default_markup_pct = 30 WHERE company_id IS NULL AND part_id = 'part_burrs_ek43_98mm';
UPDATE public.parts_catalog SET default_unit_cost = 135.00, default_markup_pct = 30 WHERE company_id IS NULL AND part_id = 'part_burrs_e80_80mm';
UPDATE public.parts_catalog SET default_unit_cost =  95.00, default_markup_pct = 30 WHERE company_id IS NULL AND part_id = 'part_burrs_e65_64mm';
UPDATE public.parts_catalog SET default_unit_cost = 155.00, default_markup_pct = 30 WHERE company_id IS NULL AND part_id = 'part_burrs_robur_71mm';
UPDATE public.parts_catalog SET default_unit_cost =  85.00, default_markup_pct = 30 WHERE company_id IS NULL AND part_id = 'part_burrs_major_83mm';
UPDATE public.parts_catalog SET default_unit_cost = 135.00, default_markup_pct = 30 WHERE company_id IS NULL AND part_id = 'part_burrs_kony_71mm';
UPDATE public.parts_catalog SET default_unit_cost =  58.00, default_markup_pct = 30 WHERE company_id IS NULL AND part_id = 'part_burrs_super_jolly';
UPDATE public.parts_catalog SET default_unit_cost =  85.00, default_markup_pct = 30 WHERE company_id IS NULL AND part_id = 'part_burrs_atom_75';

-- Grinder consumables
UPDATE public.parts_catalog SET default_unit_cost =  22.00, default_markup_pct = 35 WHERE company_id IS NULL AND part_id = 'part_grindz_jar';
UPDATE public.parts_catalog SET default_unit_cost =  18.00, default_markup_pct = 40 WHERE company_id IS NULL AND part_id = 'part_motor_brushes_pair';
UPDATE public.parts_catalog SET default_unit_cost =   2.50, default_markup_pct = 60 WHERE company_id IS NULL AND part_id = 'part_burr_carrier_oring';
UPDATE public.parts_catalog SET default_unit_cost =  15.00, default_markup_pct = 35 WHERE company_id IS NULL AND part_id = 'part_food_grease_h1';
UPDATE public.parts_catalog SET default_unit_cost =  45.00, default_markup_pct = 40 WHERE company_id IS NULL AND part_id = 'part_hopper_assembly_universal';

-- Brewer
UPDATE public.parts_catalog SET default_unit_cost =  65.00, default_markup_pct = 30 WHERE company_id IS NULL AND part_id = 'part_brewer_filter_curtis';
UPDATE public.parts_catalog SET default_unit_cost =  58.00, default_markup_pct = 30 WHERE company_id IS NULL AND part_id = 'part_brewer_filter_bunn';
UPDATE public.parts_catalog SET default_unit_cost =  38.00, default_markup_pct = 40 WHERE company_id IS NULL AND part_id = 'part_brewer_spray_head';
UPDATE public.parts_catalog SET default_unit_cost =  28.00, default_markup_pct = 40 WHERE company_id IS NULL AND part_id = 'part_brewer_dispense_valve';
UPDATE public.parts_catalog SET default_unit_cost =  18.00, default_markup_pct = 50 WHERE company_id IS NULL AND part_id = 'part_brewer_decanter_glass';
UPDATE public.parts_catalog SET default_unit_cost = 125.00, default_markup_pct = 40 WHERE company_id IS NULL AND part_id = 'part_brewer_decanter_thermal';

-- Roaster
UPDATE public.parts_catalog SET default_unit_cost = 145.00, default_markup_pct = 25 WHERE company_id IS NULL AND part_id = 'part_drum_gasket_loring_s15';
UPDATE public.parts_catalog SET default_unit_cost = 175.00, default_markup_pct = 25 WHERE company_id IS NULL AND part_id = 'part_drum_gasket_probat_l12';
UPDATE public.parts_catalog SET default_unit_cost = 115.00, default_markup_pct = 25 WHERE company_id IS NULL AND part_id = 'part_drum_gasket_diedrich';
UPDATE public.parts_catalog SET default_unit_cost =  38.00, default_markup_pct = 35 WHERE company_id IS NULL AND part_id = 'part_thermocouple_k_24in';
UPDATE public.parts_catalog SET default_unit_cost =  48.00, default_markup_pct = 35 WHERE company_id IS NULL AND part_id = 'part_thermocouple_k_36in';
UPDATE public.parts_catalog SET default_unit_cost =  35.00, default_markup_pct = 35 WHERE company_id IS NULL AND part_id = 'part_thermocouple_j_24in';
UPDATE public.parts_catalog SET default_unit_cost =  65.00, default_markup_pct = 30 WHERE company_id IS NULL AND part_id = 'part_drum_chain_60_link';
UPDATE public.parts_catalog SET default_unit_cost =  28.00, default_markup_pct = 35 WHERE company_id IS NULL AND part_id = 'part_bearing_grease_hi_temp';
UPDATE public.parts_catalog SET default_unit_cost = 285.00, default_markup_pct = 30 WHERE company_id IS NULL AND part_id = 'part_drum_bearing_set';
UPDATE public.parts_catalog SET default_unit_cost =  45.00, default_markup_pct = 40 WHERE company_id IS NULL AND part_id = 'part_sight_glass';
UPDATE public.parts_catalog SET default_unit_cost = 125.00, default_markup_pct = 30 WHERE company_id IS NULL AND part_id = 'part_burner_orifice_set';
UPDATE public.parts_catalog SET default_unit_cost = 225.00, default_markup_pct = 30 WHERE company_id IS NULL AND part_id = 'part_exhaust_fan_motor';
UPDATE public.parts_catalog SET default_unit_cost =  32.00, default_markup_pct = 35 WHERE company_id IS NULL AND part_id = 'part_drum_brush_stainless';
UPDATE public.parts_catalog SET default_unit_cost =  18.00, default_markup_pct = 40 WHERE company_id IS NULL AND part_id = 'part_chaff_collector_bag';
UPDATE public.parts_catalog SET default_unit_cost =  38.00, default_markup_pct = 30 WHERE company_id IS NULL AND part_id = 'part_door_seal_gasket';
UPDATE public.parts_catalog SET default_unit_cost =  65.00, default_markup_pct = 35 WHERE company_id IS NULL AND part_id = 'part_high_limit_switch';
UPDATE public.parts_catalog SET default_unit_cost = 185.00, default_markup_pct = 30 WHERE company_id IS NULL AND part_id = 'part_gas_valve_24v';

-- Water treatment
UPDATE public.parts_catalog SET default_unit_cost = 105.00, default_markup_pct = 25 WHERE company_id IS NULL AND part_id = 'part_wf_3m_hf45';
UPDATE public.parts_catalog SET default_unit_cost =  88.00, default_markup_pct = 25 WHERE company_id IS NULL AND part_id = 'part_wf_pentair_h300';
UPDATE public.parts_catalog SET default_unit_cost =  18.00, default_markup_pct = 35 WHERE company_id IS NULL AND part_id = 'part_water_hardness_strips';
