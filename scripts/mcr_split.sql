BEGIN;
SET LOCAL app.skip_audit = 'true';

-- ── 1. New coffee groups (origins) ──
INSERT INTO public.coffee_inventory (origin_id, origin, bag_size, inventory_count_bags, in_stock, company_id, facility_id, is_active, created_at, updated_at, created_by) VALUES ('orig_mcr_kona_prime', 'Kona Prime', '100', 0, 0, '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', true, now(), now(), '9ShiyDAXhV') ON CONFLICT (origin_id) DO NOTHING;
INSERT INTO public.coffee_inventory (origin_id, origin, bag_size, inventory_count_bags, in_stock, company_id, facility_id, is_active, created_at, updated_at, created_by) VALUES ('orig_mcr_kona_peaberry', 'Kona Peaberry', '100', 0, 0, '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', true, now(), now(), '9ShiyDAXhV') ON CONFLICT (origin_id) DO NOTHING;
INSERT INTO public.coffee_inventory (origin_id, origin, bag_size, inventory_count_bags, in_stock, company_id, facility_id, is_active, created_at, updated_at, created_by) VALUES ('orig_mcr_kona_organic', 'Kona Organic', '100', 0, 0, '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', true, now(), now(), '9ShiyDAXhV') ON CONFLICT (origin_id) DO NOTHING;
INSERT INTO public.coffee_inventory (origin_id, origin, bag_size, inventory_count_bags, in_stock, company_id, facility_id, is_active, created_at, updated_at, created_by) VALUES ('orig_mcr_kona_h3', 'Kona H3', '100', 0, 0, '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', true, now(), now(), '9ShiyDAXhV') ON CONFLICT (origin_id) DO NOTHING;
INSERT INTO public.coffee_inventory (origin_id, origin, bag_size, inventory_count_bags, in_stock, company_id, facility_id, is_active, created_at, updated_at, created_by) VALUES ('orig_mcr_kona_decaf', 'Kona Decaf', '100', 0, 0, '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', true, now(), now(), '9ShiyDAXhV') ON CONFLICT (origin_id) DO NOTHING;
INSERT INTO public.coffee_inventory (origin_id, origin, bag_size, inventory_count_bags, in_stock, company_id, facility_id, is_active, created_at, updated_at, created_by) VALUES ('orig_mcr_kona_castaway', 'Kona Castaway', '100', 0, 0, '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', true, now(), now(), '9ShiyDAXhV') ON CONFLICT (origin_id) DO NOTHING;
INSERT INTO public.coffee_inventory (origin_id, origin, bag_size, inventory_count_bags, in_stock, company_id, facility_id, is_active, created_at, updated_at, created_by) VALUES ('orig_mcr_maui_yellow', 'Maui Yellow', '100', 0, 0, '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', true, now(), now(), '9ShiyDAXhV') ON CONFLICT (origin_id) DO NOTHING;
INSERT INTO public.coffee_inventory (origin_id, origin, bag_size, inventory_count_bags, in_stock, company_id, facility_id, is_active, created_at, updated_at, created_by) VALUES ('orig_mcr_maui_h3', 'Maui H3', '100', 0, 0, '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', true, now(), now(), '9ShiyDAXhV') ON CONFLICT (origin_id) DO NOTHING;
INSERT INTO public.coffee_inventory (origin_id, origin, bag_size, inventory_count_bags, in_stock, company_id, facility_id, is_active, created_at, updated_at, created_by) VALUES ('orig_mcr_maui_red', 'Maui Red', '100', 0, 0, '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', true, now(), now(), '9ShiyDAXhV') ON CONFLICT (origin_id) DO NOTHING;
INSERT INTO public.coffee_inventory (origin_id, origin, bag_size, inventory_count_bags, in_stock, company_id, facility_id, is_active, created_at, updated_at, created_by) VALUES ('orig_mcr_maui_moka', 'Maui Moka', '100', 0, 0, '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', true, now(), now(), '9ShiyDAXhV') ON CONFLICT (origin_id) DO NOTHING;
INSERT INTO public.coffee_inventory (origin_id, origin, bag_size, inventory_count_bags, in_stock, company_id, facility_id, is_active, created_at, updated_at, created_by) VALUES ('orig_mcr_maui_peaberry', 'Maui Peaberry', '100', 0, 0, '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', true, now(), now(), '9ShiyDAXhV') ON CONFLICT (origin_id) DO NOTHING;
INSERT INTO public.coffee_inventory (origin_id, origin, bag_size, inventory_count_bags, in_stock, company_id, facility_id, is_active, created_at, updated_at, created_by) VALUES ('orig_mcr_maui_decaf', 'Maui Decaf', '100', 0, 0, '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', true, now(), now(), '9ShiyDAXhV') ON CONFLICT (origin_id) DO NOTHING;
INSERT INTO public.coffee_inventory (origin_id, origin, bag_size, inventory_count_bags, in_stock, company_id, facility_id, is_active, created_at, updated_at, created_by) VALUES ('orig_mcr_decaf', 'Decaf', '152', 0, 0, '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', true, now(), now(), '9ShiyDAXhV') ON CONFLICT (origin_id) DO NOTHING;
INSERT INTO public.coffee_inventory (origin_id, origin, bag_size, inventory_count_bags, in_stock, company_id, facility_id, is_active, created_at, updated_at, created_by) VALUES ('orig_mcr_pacific_peaberry', 'Pacific Peaberry', '152', 0, 0, '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', true, now(), now(), '9ShiyDAXhV') ON CONFLICT (origin_id) DO NOTHING;

-- ── 2. Repoint coffee_sources to new groups ──
UPDATE public.coffee_source SET origin_id = 'orig_mcr_kona_h3' WHERE company_id = '9ShiyDAXhV' AND coffee_name = 'Hawaii No.3 (Kona)';
UPDATE public.coffee_source SET origin_id = 'orig_mcr_kona_h3' WHERE company_id = '9ShiyDAXhV' AND coffee_name = 'Kona #3';
UPDATE public.coffee_source SET origin_id = 'orig_mcr_kona_castaway' WHERE company_id = '9ShiyDAXhV' AND coffee_name = 'Kona Castaway Estate';
UPDATE public.coffee_source SET origin_id = 'orig_mcr_kona_castaway' WHERE company_id = '9ShiyDAXhV' AND coffee_name = 'Kona Castaway Reserve';
UPDATE public.coffee_source SET origin_id = 'orig_mcr_kona_decaf' WHERE company_id = '9ShiyDAXhV' AND coffee_name = 'Kona Decaf';
UPDATE public.coffee_source SET origin_id = 'orig_mcr_kona_organic' WHERE company_id = '9ShiyDAXhV' AND coffee_name = 'Kona Organic';
UPDATE public.coffee_source SET origin_id = 'orig_mcr_kona_peaberry' WHERE company_id = '9ShiyDAXhV' AND coffee_name = 'Kona Peaberry';
UPDATE public.coffee_source SET origin_id = 'orig_mcr_kona_prime' WHERE company_id = '9ShiyDAXhV' AND coffee_name = 'Kona Prime';
UPDATE public.coffee_source SET origin_id = 'orig_mcr_kona_prime' WHERE company_id = '9ShiyDAXhV' AND coffee_name = 'Kona Prime 16/17';
UPDATE public.coffee_source SET origin_id = 'orig_mcr_kona_prime' WHERE company_id = '9ShiyDAXhV' AND coffee_name = 'Kona Prime 18/19';
UPDATE public.coffee_source SET origin_id = 'orig_mcr_kona_peaberry' WHERE company_id = '9ShiyDAXhV' AND coffee_name = 'Kona Prime Peaberry';
UPDATE public.coffee_source SET origin_id = 'orig_mcr_maui_decaf' WHERE company_id = '9ShiyDAXhV' AND coffee_name = 'Maui Dec Yellow 14';
UPDATE public.coffee_source SET origin_id = 'orig_mcr_maui_h3' WHERE company_id = '9ShiyDAXhV' AND coffee_name = 'Maui H3';
UPDATE public.coffee_source SET origin_id = 'orig_mcr_maui_moka' WHERE company_id = '9ShiyDAXhV' AND coffee_name = 'Maui Moka 11';
UPDATE public.coffee_source SET origin_id = 'orig_mcr_maui_moka' WHERE company_id = '9ShiyDAXhV' AND coffee_name = 'Maui Moka 14';
UPDATE public.coffee_source SET origin_id = 'orig_mcr_maui_red' WHERE company_id = '9ShiyDAXhV' AND coffee_name = 'Maui Red 14';
UPDATE public.coffee_source SET origin_id = 'orig_mcr_maui_red' WHERE company_id = '9ShiyDAXhV' AND coffee_name = 'Maui Red Catuai Wash';
UPDATE public.coffee_source SET origin_id = 'orig_mcr_maui_h3' WHERE company_id = '9ShiyDAXhV' AND coffee_name = 'Maui Red H3';
UPDATE public.coffee_source SET origin_id = 'orig_mcr_maui_red' WHERE company_id = '9ShiyDAXhV' AND coffee_name = 'Maui Red Natural 14 (NO LONGER USE)';
UPDATE public.coffee_source SET origin_id = 'orig_mcr_maui_red' WHERE company_id = '9ShiyDAXhV' AND coffee_name = 'Maui Red Natural 16';
UPDATE public.coffee_source SET origin_id = 'orig_mcr_maui_peaberry' WHERE company_id = '9ShiyDAXhV' AND coffee_name = 'Maui Red Peaberry';
UPDATE public.coffee_source SET origin_id = 'orig_mcr_maui_yellow' WHERE company_id = '9ShiyDAXhV' AND coffee_name = 'Maui Yellow 14 Nautral (NO LONGER USE)';
UPDATE public.coffee_source SET origin_id = 'orig_mcr_maui_yellow' WHERE company_id = '9ShiyDAXhV' AND coffee_name = 'Maui Yellow 16';
UPDATE public.coffee_source SET origin_id = 'orig_mcr_maui_h3' WHERE company_id = '9ShiyDAXhV' AND coffee_name = 'Maui Yellow H3 Natural';
UPDATE public.coffee_source SET origin_id = 'orig_mcr_maui_peaberry' WHERE company_id = '9ShiyDAXhV' AND coffee_name = 'Maui Yellow Peaberry';
UPDATE public.coffee_source SET origin_id = 'orig_mcr_decaf' WHERE company_id = '9ShiyDAXhV' AND coffee_name = 'Decaf Brazil (FLAVOR)';
UPDATE public.coffee_source SET origin_id = 'orig_mcr_decaf' WHERE company_id = '9ShiyDAXhV' AND coffee_name = 'Decaf Colombia (DECAF BLENDS)';
UPDATE public.coffee_source SET origin_id = 'orig_mcr_decaf' WHERE company_id = '9ShiyDAXhV' AND coffee_name = 'Decaf Mexico Esmeralda';
UPDATE public.coffee_source SET origin_id = 'orig_mcr_pacific_peaberry' WHERE company_id = '9ShiyDAXhV' AND coffee_name = 'Papa New Guinea Peaberry';
UPDATE public.coffee_source SET origin_id = 'orig_mcr_pacific_peaberry' WHERE company_id = '9ShiyDAXhV' AND coffee_name = 'PNG Peaberry';
UPDATE public.coffee_source SET origin_id = 'orig_mcr_pacific_peaberry' WHERE company_id = '9ShiyDAXhV' AND coffee_name = 'Organic Timor peaberry';
UPDATE public.coffee_source SET origin_id = 'orig_mcr_pacific_peaberry' WHERE company_id = '9ShiyDAXhV' AND coffee_name = 'Organic Timor Peaberry';

-- ── 3. Repoint coffee_inventory_purchased (lots) by source ──
UPDATE public.coffee_inventory_purchased cip SET origin = cs.origin_id FROM public.coffee_source cs WHERE cip.coffee_source_id = cs.coffee_source_id AND cip.company_id = '9ShiyDAXhV';

-- ── 4. Repoint recipe_components to new groups ──
UPDATE public.recipe_components SET coffee_item = 'orig_mcr_maui_h3' WHERE recipe_id = 'rcp-mcr-mb-lt' AND coffee_item = 'orig_142ffc976e750f22' AND ROUND(percentage::numeric, 4) = 0.1;
UPDATE public.recipe_components SET coffee_item = 'orig_mcr_maui_h3' WHERE recipe_id = 'rcp-mcr-mb-dk' AND coffee_item = 'orig_142ffc976e750f22' AND ROUND(percentage::numeric, 4) = 0.1;
UPDATE public.recipe_components SET coffee_item = 'orig_mcr_maui_h3' WHERE recipe_id = 'rcp-mcr-mb-med-2oz' AND coffee_item = 'orig_142ffc976e750f22' AND ROUND(percentage::numeric, 4) = 0.1;
UPDATE public.recipe_components SET coffee_item = 'orig_mcr_maui_moka' WHERE recipe_id = 'rcp-mcr-mama-s-maui-moka' AND coffee_item = 'orig_142ffc976e750f22' AND ROUND(percentage::numeric, 4) = 0.7;
UPDATE public.recipe_components SET coffee_item = 'orig_mcr_maui_moka' WHERE recipe_id = 'rcp-mcr-maui-moka' AND coffee_item = 'orig_142ffc976e750f22' AND ROUND(percentage::numeric, 4) = 1.0;
UPDATE public.recipe_components SET coffee_item = 'orig_mcr_maui_peaberry' WHERE recipe_id = 'rcp-mcr-maui-pea-lt' AND coffee_item = 'orig_142ffc976e750f22' AND ROUND(percentage::numeric, 4) = 1.0;
UPDATE public.recipe_components SET coffee_item = 'orig_mcr_maui_peaberry' WHERE recipe_id = 'rcp-mcr-maui-pea-dk' AND coffee_item = 'orig_142ffc976e750f22' AND ROUND(percentage::numeric, 4) = 1.0;
UPDATE public.recipe_components SET coffee_item = 'orig_mcr_maui_red' WHERE recipe_id = 'rcp-mcr-red-rooster' AND coffee_item = 'orig_142ffc976e750f22' AND ROUND(percentage::numeric, 4) = 1.0;
UPDATE public.recipe_components SET coffee_item = 'orig_mcr_maui_yellow' WHERE recipe_id = 'rcp-mcr-yellow-cat' AND coffee_item = 'orig_142ffc976e750f22' AND ROUND(percentage::numeric, 4) = 1.0;
UPDATE public.recipe_components SET coffee_item = 'orig_mcr_decaf' WHERE recipe_id = 'rcp-mcr-espresso-decaf' AND coffee_item = 'orig_0d75323d13d7e2fe' AND ROUND(percentage::numeric, 4) = 1.0;
UPDATE public.recipe_components SET coffee_item = 'orig_mcr_decaf' WHERE recipe_id = 'rcp-mcr-flavor-decaf' AND coffee_item = 'orig_0d75323d13d7e2fe' AND ROUND(percentage::numeric, 4) = 1.0;
UPDATE public.recipe_components SET coffee_item = 'orig_mcr_decaf' WHERE recipe_id = 'rcp-mcr-mcr-hi-blend-decaf' AND coffee_item = 'orig_0d75323d13d7e2fe' AND ROUND(percentage::numeric, 4) = 0.95;
UPDATE public.recipe_components SET coffee_item = 'orig_mcr_kona_decaf' WHERE recipe_id = 'rcp-mcr-mcr-hi-blend-decaf' AND coffee_item = 'orig_2bb4bb4cfe71072a' AND ROUND(percentage::numeric, 4) = 0.05;
UPDATE public.recipe_components SET coffee_item = 'orig_mcr_decaf' WHERE recipe_id = 'rcp-mcr-french-decaf' AND coffee_item = 'orig_0d75323d13d7e2fe' AND ROUND(percentage::numeric, 4) = 1.0;
UPDATE public.recipe_components SET coffee_item = 'orig_mcr_pacific_peaberry' WHERE recipe_id = 'rcp-mcr-pacific-pea-blend' AND coffee_item = 'orig_93f7f73f959de942' AND ROUND(percentage::numeric, 4) = 0.9;
UPDATE public.recipe_components SET coffee_item = 'orig_mcr_maui_peaberry' WHERE recipe_id = 'rcp-mcr-pacific-pea-blend' AND coffee_item = 'orig_142ffc976e750f22' AND ROUND(percentage::numeric, 4) = 0.1;
UPDATE public.recipe_components SET coffee_item = 'orig_mcr_kona_h3' WHERE recipe_id = 'rcp-mcr-pacific-blend' AND coffee_item = 'orig_2bb4bb4cfe71072a' AND ROUND(percentage::numeric, 4) = 0.05;
UPDATE public.recipe_components SET coffee_item = 'orig_mcr_pacific_peaberry' WHERE recipe_id = 'rcp-mcr-sw-pea-lt' AND coffee_item = 'orig_93f7f73f959de942' AND ROUND(percentage::numeric, 4) = 1.0;
UPDATE public.recipe_components SET coffee_item = 'orig_mcr_kona_h3' WHERE recipe_id = 'rcp-mcr-nicbeans-kona' AND coffee_item = 'orig_2bb4bb4cfe71072a' AND ROUND(percentage::numeric, 4) = 1.0;
UPDATE public.recipe_components SET coffee_item = 'orig_mcr_decaf' WHERE recipe_id = 'rcp-mcr-kona-decaf' AND coffee_item = 'orig_0d75323d13d7e2fe' AND ROUND(percentage::numeric, 4) = 0.9;
UPDATE public.recipe_components SET coffee_item = 'orig_mcr_kona_decaf' WHERE recipe_id = 'rcp-mcr-kona-decaf' AND coffee_item = 'orig_2bb4bb4cfe71072a' AND ROUND(percentage::numeric, 4) = 0.1;
UPDATE public.recipe_components SET coffee_item = 'orig_mcr_kona_h3' WHERE recipe_id = 'rcp-mcr-kona-bl-med' AND coffee_item = 'orig_2bb4bb4cfe71072a' AND ROUND(percentage::numeric, 4) = 0.1;
UPDATE public.recipe_components SET coffee_item = 'orig_mcr_kona_h3' WHERE recipe_id = 'rcp-mcr-kona-bl-dk' AND coffee_item = 'orig_2bb4bb4cfe71072a' AND ROUND(percentage::numeric, 4) = 0.1;
UPDATE public.recipe_components SET coffee_item = 'orig_mcr_kona_h3' WHERE recipe_id = 'rcp-mcr-kona-bl-lt' AND coffee_item = 'orig_2bb4bb4cfe71072a' AND ROUND(percentage::numeric, 4) = 0.1;
UPDATE public.recipe_components SET coffee_item = 'orig_mcr_kona_prime' WHERE recipe_id = 'rcp-mcr-kona-castaway-reserve' AND coffee_item = 'orig_2bb4bb4cfe71072a' AND ROUND(percentage::numeric, 4) = 1.0;
UPDATE public.recipe_components SET coffee_item = 'orig_mcr_kona_h3' WHERE recipe_id = 'rcp-mcr-kona-est-dk' AND coffee_item = 'orig_2bb4bb4cfe71072a' AND ROUND(percentage::numeric, 4) = 1.0;
UPDATE public.recipe_components SET coffee_item = 'orig_mcr_kona_h3' WHERE recipe_id = 'rcp-mcr-kona-est-lt' AND coffee_item = 'orig_2bb4bb4cfe71072a' AND ROUND(percentage::numeric, 4) = 1.0;
UPDATE public.recipe_components SET coffee_item = 'orig_mcr_kona_peaberry' WHERE recipe_id = 'rcp-mcr-kona-pea-med' AND coffee_item = 'orig_2bb4bb4cfe71072a' AND ROUND(percentage::numeric, 4) = 1.0;
UPDATE public.recipe_components SET coffee_item = 'orig_mcr_kona_h3' WHERE recipe_id = 'rcp-mcr-mcr-hi-blend' AND coffee_item = 'orig_2bb4bb4cfe71072a' AND ROUND(percentage::numeric, 4) = 0.1;
UPDATE public.recipe_components SET coffee_item = 'orig_mcr_kona_organic' WHERE recipe_id = 'rcp-mcr-org-kona-bl-med' AND coffee_item = 'orig_2bb4bb4cfe71072a' AND ROUND(percentage::numeric, 4) = 0.1;
UPDATE public.recipe_components SET coffee_item = 'orig_mcr_kona_organic' WHERE recipe_id = 'rcp-mcr-org-kona-bl-dk' AND coffee_item = 'orig_2bb4bb4cfe71072a' AND ROUND(percentage::numeric, 4) = 0.1;

-- ── 5. Reset old Kona/Maui stock via history count = 0 ──
INSERT INTO public.coffee_inventory_history (history_id, origin_id, inventory_date, bag_count, notes, company_id, facility_id, created_by) VALUES (gen_random_uuid()::text, 'orig_2bb4bb4cfe71072a', CURRENT_DATE, 0, 'Reset after group split', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', '9ShiyDAXhV');
INSERT INTO public.coffee_inventory_history (history_id, origin_id, inventory_date, bag_count, notes, company_id, facility_id, created_by) VALUES (gen_random_uuid()::text, 'orig_142ffc976e750f22', CURRENT_DATE, 0, 'Reset after group split', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', '9ShiyDAXhV');

COMMIT;
