-- ============================================================================
-- DEMO COMPANY SEED: Aloha Coffee Roasters
-- ============================================================================
-- Seeds a complete demo company with realistic Hawaiian specialty roastery data
-- for the STRATA marketing website interactive demo.
--
-- NOTE: The demo auth user (demo@strataroast.com) must be created separately
-- via Supabase Auth admin API or dashboard. After creating, update the
-- auth_user_id in the team row below.
-- ============================================================================

BEGIN;

-- Skip audit triggers for bulk inserts
SET LOCAL app.skip_audit = 'true';
SET LOCAL session_replication_role = 'replica';

-- ── 1. Add is_demo column to companies ──────────────────────────────────────
ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS is_demo boolean NOT NULL DEFAULT false;

-- ── 2. Company ──────────────────────────────────────────────────────────────
INSERT INTO public.companies (company_id, company_name, is_demo, created_by)
VALUES ('demo-aloha-coffee-roasters', 'Aloha Coffee Roasters', true, 'demo-team-admin')
ON CONFLICT (company_id) DO NOTHING;

-- ── 3. Facility ─────────────────────────────────────────────────────────────
INSERT INTO public.facilities (facility_id, company_id, facility_name, time_zone, country_code, created_by)
VALUES ('demo-kailua-roastery', 'demo-aloha-coffee-roasters', 'Kailua Roastery', 'Pacific/Honolulu', 'US', 'demo-team-admin')
ON CONFLICT (facility_id) DO NOTHING;

-- ── 4. Team member (demo user) ─────────────────────────────────────────────
-- auth_user_id is NULL until the Supabase Auth user is created separately
INSERT INTO public.team (team_member_id, name, email, company_id, facility_id, role, created_by, onboarding_completed)
VALUES ('demo-team-admin', 'Demo User', 'demo@strataroast.com', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'company_admin', 'demo-team-admin', true)
ON CONFLICT (team_member_id) DO NOTHING;

-- ── 5. Subscription (active trial) ─────────────────────────────────────────
INSERT INTO public.subscriptions (subscription_id, company_id, plan_id, status, trial_end, created_by)
VALUES (
  'demo-sub-001',
  'demo-aloha-coffee-roasters',
  'pro',
  'trialing',
  NOW() + INTERVAL '30 days',
  'demo-team-admin'
)
ON CONFLICT (subscription_id) DO NOTHING;

-- ── 6. Company parameters ───────────────────────────────────────────────────
-- Seed from standard_parameters, then override specific values
-- Guard: skip if already seeded
INSERT INTO public.company_parameters (company_id, facility_id, parameter_id, value, value_number, display_name, created_by)
SELECT
  'demo-aloha-coffee-roasters',
  'demo-kailua-roastery',
  sp.parameters_id,
  sp.text_value,
  sp.amount,
  sp.parameter,
  'demo-team-admin'
FROM public.standard_parameters sp
WHERE NOT EXISTS (
  SELECT 1 FROM public.company_parameters cp
  WHERE cp.company_id = 'demo-aloha-coffee-roasters'
    AND cp.facility_id = 'demo-kailua-roastery'
    AND cp.parameter_id = sp.parameters_id
);

-- Override key parameters
UPDATE public.company_parameters SET value_number = 0.82
WHERE company_id = 'demo-aloha-coffee-roasters' AND parameter_id = '1de271df';  -- retention_rate

UPDATE public.company_parameters SET value_number = 25
WHERE company_id = 'demo-aloha-coffee-roasters' AND parameter_id = '761fd894';  -- charge_weight

UPDATE public.company_parameters SET value_number = 4
WHERE company_id = 'demo-aloha-coffee-roasters' AND parameter_id = 'RF1iFWjOh7';  -- roast_reset_day (Thursday)

UPDATE public.company_parameters SET value_number = 4
WHERE company_id = 'demo-aloha-coffee-roasters' AND parameter_id = 'orders_reset_day';  -- orders_reset_day (Thursday)

-- ── 7. Suppliers ────────────────────────────────────────────────────────────
INSERT INTO public.supplier (supplier_id, supplier, supplier_category, company_id, facility_id, created_by) VALUES
  ('demo-sup-001', 'Pacific Green Imports',    'coffee',     'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-sup-002', 'Kona Direct Sourcing',     'coffee',     'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-sup-003', 'Island Packaging Co.',     'consumable', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-sup-004', 'Volcano Bean Trading',     'coffee',     'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-sup-005', 'Maui Label & Print',       'consumable', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin')
ON CONFLICT DO NOTHING;

-- ── 9. Bag sizes ────────────────────────────────────────────────────────────
INSERT INTO public.bag_sizes (bag_size_id, label, company_id, facility_id) VALUES
  ('154', '154',  'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  ('132', '132',  'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  ('100', '100',  'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  ('69',  '69',   'demo-aloha-coffee-roasters', 'demo-kailua-roastery')
ON CONFLICT DO NOTHING;

-- ── 10. Sizes (product sizes) ───────────────────────────────────────────────
INSERT INTO public.size (size_id, size_name, weight, company_id, created_by) VALUES
  ('demo-size-12oz', '12oz',  0.75,  'demo-aloha-coffee-roasters', 'demo-team-admin'),
  ('demo-size-1lb',  '1lb',   1.0,   'demo-aloha-coffee-roasters', 'demo-team-admin'),
  ('demo-size-5lb',  '5lb',   5.0,   'demo-aloha-coffee-roasters', 'demo-team-admin'),
  ('demo-size-2lb',  '2lb',   2.0,   'demo-aloha-coffee-roasters', 'demo-team-admin')
ON CONFLICT DO NOTHING;

-- ── 11. Charge weight options ───────────────────────────────────────────────
INSERT INTO public.charge_weight_options (id, charge_weight, company_id, facility_id, created_by) VALUES
  ('demo-cw-15', 15, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-cw-20', 20, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-cw-25', 25, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-cw-30', 30, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin')
ON CONFLICT DO NOTHING;

-- ── 12. Roaster unit ────────────────────────────────────────────────────────
INSERT INTO public.roaster_units (roaster_unit_id, facility_id, company_id, name, max_charge_weight_lbs, max_charge_weight_id, created_by) VALUES
  ('a0a0a0a0-0001-4000-8000-000000000001'::uuid, 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', 'Probat P25', 25, 'demo-cw-25', 'demo-team-admin'),
  ('a0a0a0a0-0001-4000-8000-000000000002'::uuid, 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', 'Diedrich IR-12', 15, 'demo-cw-15', 'demo-team-admin')
ON CONFLICT DO NOTHING;

-- User roaster preference
INSERT INTO public.user_roaster_settings (user_roaster_settings_id, email, roaster_unit_id, facility_id, company_id) VALUES
  ('demo-urs-001', 'demo@strataroast.com', 'a0a0a0a0-0001-4000-8000-000000000001'::uuid, 'demo-kailua-roastery', 'demo-aloha-coffee-roasters')
ON CONFLICT DO NOTHING;

-- ── 13. Coffee inventory (green coffee origins) ─────────────────────────────
INSERT INTO public.coffee_inventory (origin_id, origin, supplier_id, bag_size, company_id, facility_id, created_by,
  inventory_count_bags, in_stock, par, restock_level, in_stock_lbs, last_cost_lb, latest_cost, fallback_cost) VALUES
  ('demo-org-kona',     'Hawaii Kona Extra Fancy',    'demo-sup-002', '100', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', 8,  8,  6,  3,  800,  28.50, 34.76, 34.76),
  ('demo-org-brazil',   'Brazil Santos FC',           'demo-sup-001', '154', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', 12, 12, 8,  4,  1848, 3.85,  4.70,  4.70),
  ('demo-org-colombia', 'Colombia Huila Supremo',     'demo-sup-001', '154', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', 10, 10, 7,  3,  1540, 4.25,  5.18,  5.18),
  ('demo-org-ethiopia', 'Ethiopia Yirgacheffe Gr. 1', 'demo-sup-004', '132', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', 6,  6,  5,  2,  792,  5.90,  7.20,  7.20),
  ('demo-org-guate',    'Guatemala Antigua',          'demo-sup-001', '154', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', 7,  7,  5,  2,  1078, 4.50,  5.49,  5.49),
  ('demo-org-costa',    'Costa Rica Tarrazu',         'demo-sup-001', '154', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', 5,  5,  5,  2,  770,  4.75,  5.79,  5.79),
  ('demo-org-kenya',    'Kenya AA',                   'demo-sup-004', '132', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', 4,  4,  4,  2,  528,  6.20,  7.56,  7.56),
  ('demo-org-sumatra',  'Sumatra Mandheling',         'demo-sup-001', '154', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', 9,  9,  6,  3,  1386, 4.10,  5.00,  5.00),
  ('demo-org-peru',     'Peru Cajamarca',             'demo-sup-001', '154', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', 3,  3,  5,  2,  462,  3.60,  4.39,  4.39),
  ('demo-org-mexico',   'Mexico Chiapas',             'demo-sup-001', '154', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', 6,  6,  4,  2,  924,  3.40,  4.15,  4.15),
  ('demo-org-elsalv',   'El Salvador Pacamara',       'demo-sup-004', '132', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', 2,  2,  3,  1,  264,  5.50,  6.71,  6.71),
  ('demo-org-png',      'Papua New Guinea Sigri',     'demo-sup-001', '154', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', 5,  5,  4,  2,  770,  4.00,  4.88,  4.88),
  ('demo-org-rwanda',   'Rwanda Nyamasheke',          'demo-sup-004', '132', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', 3,  3,  3,  1,  396,  5.30,  6.46,  6.46),
  ('demo-org-decaf-co', 'Decaf Colombia Swiss Water', 'demo-sup-001', '154', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', 4,  4,  3,  1,  616,  5.00,  6.10,  6.10),
  ('demo-org-decaf-et', 'Decaf Ethiopia Sidamo',      'demo-sup-004', '132', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', 2,  2,  2,  1,  264,  5.80,  7.07,  7.07)
ON CONFLICT DO NOTHING;

-- ── 14. Coffee sources ──────────────────────────────────────────────────────
INSERT INTO public.coffee_source (coffee_source_id, coffee_name, origin_id, bag_size, company_id, process, region, farm, elevation, certifications, created_by) VALUES
  ('demo-cs-001', 'Kona Extra Fancy Greenwell',       'demo-org-kona',     '100', 'demo-aloha-coffee-roasters', 'Washed',         'Kona, Hawaii',           'Greenwell Farms',          '1800-2200 ft',   'Hawaii Certified',        'demo-team-admin'),
  ('demo-cs-002', 'Kona Peaberry Select',             'demo-org-kona',     '100', 'demo-aloha-coffee-roasters', 'Washed',         'Kona, Hawaii',           'Holualoa Estate',          '2000-2400 ft',   'Hawaii Certified',        'demo-team-admin'),
  ('demo-cs-003', 'Brazil Alta Mogiana SS FC 14/16',  'demo-org-brazil',   '154', 'demo-aloha-coffee-roasters', 'Natural',        'Alta Mogiana, SP',       'Fazenda Santa Lucia',      '1000-1200m',     NULL,                      'demo-team-admin'),
  ('demo-cs-004', 'Colombia Huila La Plata EP',       'demo-org-colombia', '154', 'demo-aloha-coffee-roasters', 'Washed',         'Huila',                  'Various smallholders',     '1600-1900m',     'Rainforest Alliance',     'demo-team-admin'),
  ('demo-cs-005', 'Colombia Popayan Micro-Lot',       'demo-org-colombia', '154', 'demo-aloha-coffee-roasters', 'Honey',          'Cauca, Popayan',         'Finca El Paraiso',         '1750-2000m',     NULL,                      'demo-team-admin'),
  ('demo-cs-006', 'Ethiopia Yirg Kochere Aricha',     'demo-org-ethiopia', '132', 'demo-aloha-coffee-roasters', 'Natural',        'Yirgacheffe, Kochere',   'Aricha station',           '1850-2100m',     NULL,                      'demo-team-admin'),
  ('demo-cs-007', 'Ethiopia Yirg Chelba Washed',      'demo-org-ethiopia', '132', 'demo-aloha-coffee-roasters', 'Washed',         'Yirgacheffe, Chelba',    'Chelba washing station',   '1900-2200m',     NULL,                      'demo-team-admin'),
  ('demo-cs-008', 'Guatemala Antigua Pastores SHB',   'demo-org-guate',    '154', 'demo-aloha-coffee-roasters', 'Washed',         'Antigua',                'Finca Pastores',           '1500-1700m',     'UTZ Certified',           'demo-team-admin'),
  ('demo-cs-009', 'Costa Rica Tarrazu La Minita',     'demo-org-costa',    '154', 'demo-aloha-coffee-roasters', 'Washed',         'Tarrazu',                'La Minita',                '1400-1600m',     NULL,                      'demo-team-admin'),
  ('demo-cs-010', 'Kenya Nyeri AB',                   'demo-org-kenya',    '132', 'demo-aloha-coffee-roasters', 'Washed',         'Nyeri',                  'Tegu factory',             '1700-1900m',     NULL,                      'demo-team-admin'),
  ('demo-cs-011', 'Sumatra Mandheling Triple Pick',   'demo-org-sumatra',  '154', 'demo-aloha-coffee-roasters', 'Wet-Hulled',     'Lintong, North Sumatra', 'Various smallholders',     '1200-1500m',     'Organic',                 'demo-team-admin'),
  ('demo-cs-012', 'Peru Cajamarca Cenfrocafe',        'demo-org-peru',     '154', 'demo-aloha-coffee-roasters', 'Washed',         'Cajamarca',              'Cenfrocafe Co-op',         '1500-1800m',     'Fair Trade, Organic',     'demo-team-admin'),
  ('demo-cs-013', 'Mexico Chiapas Jaltenango SHG',    'demo-org-mexico',   '154', 'demo-aloha-coffee-roasters', 'Washed',         'Chiapas, Jaltenango',    'Various',                  '1200-1500m',     'Organic',                 'demo-team-admin'),
  ('demo-cs-014', 'El Salvador Pacamara Las Brumas',  'demo-org-elsalv',   '132', 'demo-aloha-coffee-roasters', 'Honey',          'Santa Ana',              'Finca Las Brumas',         '1500-1700m',     NULL,                      'demo-team-admin'),
  ('demo-cs-015', 'PNG Sigri Estate A',               'demo-org-png',      '154', 'demo-aloha-coffee-roasters', 'Washed',         'Western Highlands',      'Sigri Estate',             '1500-1600m',     NULL,                      'demo-team-admin'),
  ('demo-cs-016', 'Rwanda Nyamasheke Buf Dukunde',    'demo-org-rwanda',   '132', 'demo-aloha-coffee-roasters', 'Washed',         'Nyamasheke',             'Buf Dukunde Kawa Co-op',   '1700-2000m',     'Direct Trade',            'demo-team-admin'),
  ('demo-cs-017', 'Decaf Colombia SWP EP',            'demo-org-decaf-co', '154', 'demo-aloha-coffee-roasters', 'Swiss Water',    'Huila',                  'Various',                  '1600-1800m',     'Swiss Water Process',     'demo-team-admin'),
  ('demo-cs-018', 'Decaf Ethiopia Sidamo SWP',        'demo-org-decaf-et', '132', 'demo-aloha-coffee-roasters', 'Swiss Water',    'Sidamo',                 'Various',                  '1800-2000m',     'Swiss Water Process',     'demo-team-admin'),
  ('demo-cs-019', 'Brazil Cerrado Bourbon Natural',   'demo-org-brazil',   '154', 'demo-aloha-coffee-roasters', 'Natural',        'Cerrado, MG',            'Fazenda Rainha',           '900-1100m',      NULL,                      'demo-team-admin'),
  ('demo-cs-020', 'Kenya Kirinyaga Peaberry',         'demo-org-kenya',    '132', 'demo-aloha-coffee-roasters', 'Washed',         'Kirinyaga',              'Kabare factory',           '1600-1800m',     NULL,                      'demo-team-admin')
ON CONFLICT DO NOTHING;

-- ── 15. Roast recipes ───────────────────────────────────────────────────────
INSERT INTO public.roast_recipes (recipe_id, recipe_name, company_id, facility_id, roast_type, created_by) VALUES
  ('demo-rcp-hawaiian-blend',  'Hawaiian Blend',             'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'Pre-Blend',                   'demo-team-admin'),
  ('demo-rcp-kona-dark',       'Kona Dark Roast',            'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'Single Origin/Post-Blend',    'demo-team-admin'),
  ('demo-rcp-pacific-sunrise', 'Pacific Sunrise Espresso',   'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'Pre-Blend',                   'demo-team-admin'),
  ('demo-rcp-island-breeze',   'Island Breeze Blend',        'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'Pre-Blend',                   'demo-team-admin'),
  ('demo-rcp-volcanic-drk',    'Volcanic Dark',              'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'Pre-Blend',                   'demo-team-admin'),
  ('demo-rcp-tradewind',       'Tradewind Medium',           'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'Pre-Blend',                   'demo-team-admin'),
  ('demo-rcp-aloha-house',     'Aloha House Blend',          'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'Pre-Blend',                   'demo-team-admin'),
  ('demo-rcp-maui-morning',    'Maui Morning',               'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'Pre-Blend',                   'demo-team-admin'),
  ('demo-rcp-decaf-blend',     'Decaf Sunset Blend',         'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'Pre-Blend',                   'demo-team-admin'),
  ('demo-rcp-single-ethiopia', 'Ethiopia Single Origin',     'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'Single Origin/Post-Blend',    'demo-team-admin')
ON CONFLICT DO NOTHING;

-- ── 16. Recipe components ───────────────────────────────────────────────────
INSERT INTO public.recipe_components (component_id, recipe_id, item_id, coffee_item, percentage, company_id, facility_id) VALUES
  -- Hawaiian Blend: 30% Kona, 40% Brazil, 30% Colombia
  ('demo-rc-001', 'demo-rcp-hawaiian-blend', 'demo-org-kona',     'demo-org-kona',     0.30, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  ('demo-rc-002', 'demo-rcp-hawaiian-blend', 'demo-org-brazil',   'demo-org-brazil',   0.40, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  ('demo-rc-003', 'demo-rcp-hawaiian-blend', 'demo-org-colombia', 'demo-org-colombia', 0.30, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),

  -- Pacific Sunrise Espresso: 40% Brazil, 30% Colombia, 30% Guatemala
  ('demo-rc-004', 'demo-rcp-pacific-sunrise', 'demo-org-brazil',   'demo-org-brazil',   0.40, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  ('demo-rc-005', 'demo-rcp-pacific-sunrise', 'demo-org-colombia', 'demo-org-colombia', 0.30, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  ('demo-rc-006', 'demo-rcp-pacific-sunrise', 'demo-org-guate',    'demo-org-guate',    0.30, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),

  -- Island Breeze: 35% Costa Rica, 35% Ethiopia, 30% Guatemala
  ('demo-rc-007', 'demo-rcp-island-breeze', 'demo-org-costa',    'demo-org-costa',    0.35, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  ('demo-rc-008', 'demo-rcp-island-breeze', 'demo-org-ethiopia', 'demo-org-ethiopia', 0.35, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  ('demo-rc-009', 'demo-rcp-island-breeze', 'demo-org-guate',    'demo-org-guate',    0.30, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),

  -- Volcanic Dark: 50% Sumatra, 30% Brazil, 20% PNG
  ('demo-rc-010', 'demo-rcp-volcanic-drk', 'demo-org-sumatra', 'demo-org-sumatra', 0.50, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  ('demo-rc-011', 'demo-rcp-volcanic-drk', 'demo-org-brazil',  'demo-org-brazil',  0.30, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  ('demo-rc-012', 'demo-rcp-volcanic-drk', 'demo-org-png',     'demo-org-png',     0.20, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),

  -- Tradewind Medium: 40% Colombia, 30% Mexico, 30% Peru
  ('demo-rc-013', 'demo-rcp-tradewind', 'demo-org-colombia', 'demo-org-colombia', 0.40, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  ('demo-rc-014', 'demo-rcp-tradewind', 'demo-org-mexico',   'demo-org-mexico',   0.30, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  ('demo-rc-015', 'demo-rcp-tradewind', 'demo-org-peru',     'demo-org-peru',     0.30, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),

  -- Aloha House: 30% Brazil, 25% Colombia, 25% Costa Rica, 20% Guatemala
  ('demo-rc-016', 'demo-rcp-aloha-house', 'demo-org-brazil',   'demo-org-brazil',   0.30, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  ('demo-rc-017', 'demo-rcp-aloha-house', 'demo-org-colombia', 'demo-org-colombia', 0.25, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  ('demo-rc-018', 'demo-rcp-aloha-house', 'demo-org-costa',    'demo-org-costa',    0.25, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  ('demo-rc-019', 'demo-rcp-aloha-house', 'demo-org-guate',    'demo-org-guate',    0.20, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),

  -- Maui Morning: 40% Ethiopia, 30% Kenya, 30% Rwanda
  ('demo-rc-020', 'demo-rcp-maui-morning', 'demo-org-ethiopia', 'demo-org-ethiopia', 0.40, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  ('demo-rc-021', 'demo-rcp-maui-morning', 'demo-org-kenya',    'demo-org-kenya',    0.30, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  ('demo-rc-022', 'demo-rcp-maui-morning', 'demo-org-rwanda',   'demo-org-rwanda',   0.30, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),

  -- Decaf Sunset: 60% Decaf Colombia, 40% Decaf Ethiopia
  ('demo-rc-023', 'demo-rcp-decaf-blend', 'demo-org-decaf-co', 'demo-org-decaf-co', 0.60, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  ('demo-rc-024', 'demo-rcp-decaf-blend', 'demo-org-decaf-et', 'demo-org-decaf-et', 0.40, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery')
ON CONFLICT DO NOTHING;

-- ── 16b. Product groups ─────────────────────────────────────────────────────
INSERT INTO public.product_groups (group_id, group_name, company_id) VALUES
  ('00000000-0000-0000-0000-de0000000001', 'Single Origin', 'demo-aloha-coffee-roasters'),
  ('00000000-0000-0000-0000-de0000000002', 'Blends',        'demo-aloha-coffee-roasters'),
  ('00000000-0000-0000-0000-de0000000003', 'Espresso',      'demo-aloha-coffee-roasters'),
  ('00000000-0000-0000-0000-de0000000004', 'Decaf',         'demo-aloha-coffee-roasters')
ON CONFLICT DO NOTHING;

-- ── 17. Products ────────────────────────────────────────────────────────────
-- product_type: Bag (standard), Espresso, Merged (archived)
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, weight_lbs, group_id,
  price, total_unit_cogs, total_coffee_cost, gross_profit_per_unit, cogs_pct, margin_pct,
  company_id, facility_id, created_by, created_at) VALUES

  -- Single Origin 12oz
  ('demo-prod-001', 'Hawaii Kona Extra Fancy 12oz',     'demo-rcp-kona-dark',       'Bag', 'demo-size-12oz', 0.75, '00000000-0000-0000-0000-de0000000001', 24.99, 11.42, 11.12, 13.57, 45.7, 54.3, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', NOW() - INTERVAL '180 days'),
  ('demo-prod-002', 'Ethiopia Yirgacheffe 12oz',        'demo-rcp-single-ethiopia', 'Bag', 'demo-size-12oz', 0.75, '00000000-0000-0000-0000-de0000000001', 18.99,  5.85,  5.40,  13.14, 30.8, 69.2, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', NOW() - INTERVAL '180 days'),
  ('demo-prod-003', 'Colombia Huila 12oz',              NULL,                       'Bag', 'demo-size-12oz', 0.75, '00000000-0000-0000-0000-de0000000001', 16.99,  4.19,  3.89,  12.80, 24.7, 75.3, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', NOW() - INTERVAL '180 days'),
  ('demo-prod-004', 'Guatemala Antigua 12oz',           NULL,                       'Bag', 'demo-size-12oz', 0.75, '00000000-0000-0000-0000-de0000000001', 16.99,  4.42,  4.12,  12.57, 26.0, 74.0, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', NOW() - INTERVAL '180 days'),
  ('demo-prod-005', 'Costa Rica Tarrazu 12oz',          NULL,                       'Bag', 'demo-size-12oz', 0.75, '00000000-0000-0000-0000-de0000000001', 17.49,  4.64,  4.34,  12.85, 26.5, 73.5, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', NOW() - INTERVAL '150 days'),
  ('demo-prod-006', 'Kenya AA 12oz',                    NULL,                       'Bag', 'demo-size-12oz', 0.75, '00000000-0000-0000-0000-de0000000001', 19.99,  6.02,  5.67,  13.97, 30.1, 69.9, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', NOW() - INTERVAL '150 days'),
  ('demo-prod-007', 'Sumatra Mandheling 12oz',          NULL,                       'Bag', 'demo-size-12oz', 0.75, '00000000-0000-0000-0000-de0000000001', 16.49,  4.05,  3.75,  12.44, 24.6, 75.4, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', NOW() - INTERVAL '120 days'),

  -- Single Origin 1lb
  ('demo-prod-008', 'Hawaii Kona Extra Fancy 1lb',      'demo-rcp-kona-dark',       'Bag', 'demo-size-1lb',  1.0,  '00000000-0000-0000-0000-de0000000001', 32.99, 15.06, 14.76, 17.93, 45.6, 54.4, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', NOW() - INTERVAL '180 days'),
  ('demo-prod-009', 'Ethiopia Yirgacheffe 1lb',         'demo-rcp-single-ethiopia', 'Bag', 'demo-size-1lb',  1.0,  '00000000-0000-0000-0000-de0000000001', 24.99,  7.50,  7.20,  17.49, 30.0, 70.0, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', NOW() - INTERVAL '180 days'),
  ('demo-prod-010', 'Colombia Huila 1lb',               NULL,                       'Bag', 'demo-size-1lb',  1.0,  '00000000-0000-0000-0000-de0000000001', 21.99,  5.48,  5.18,  16.51, 24.9, 75.1, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', NOW() - INTERVAL '180 days'),

  -- Blends 12oz
  ('demo-prod-011', 'Hawaiian Blend 12oz',              'demo-rcp-hawaiian-blend',  'Bag', 'demo-size-12oz', 0.75, '00000000-0000-0000-0000-de0000000002', 19.99,  8.15,  7.85,  11.84, 40.8, 59.2, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', NOW() - INTERVAL '180 days'),
  ('demo-prod-012', 'Island Breeze Blend 12oz',         'demo-rcp-island-breeze',   'Bag', 'demo-size-12oz', 0.75, '00000000-0000-0000-0000-de0000000002', 16.99,  4.89,  4.59,  12.10, 28.8, 71.2, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', NOW() - INTERVAL '160 days'),
  ('demo-prod-013', 'Volcanic Dark 12oz',               'demo-rcp-volcanic-drk',    'Bag', 'demo-size-12oz', 0.75, '00000000-0000-0000-0000-de0000000002', 15.99,  4.05,  3.75,  11.94, 25.3, 74.7, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', NOW() - INTERVAL '160 days'),
  ('demo-prod-014', 'Tradewind Medium 12oz',            'demo-rcp-tradewind',       'Bag', 'demo-size-12oz', 0.75, '00000000-0000-0000-0000-de0000000002', 15.49,  3.82,  3.52,  11.67, 24.7, 75.3, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', NOW() - INTERVAL '180 days'),
  ('demo-prod-015', 'Aloha House Blend 12oz',           'demo-rcp-aloha-house',     'Bag', 'demo-size-12oz', 0.75, '00000000-0000-0000-0000-de0000000002', 14.99,  3.96,  3.66,  11.03, 26.4, 73.6, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', NOW() - INTERVAL '180 days'),
  ('demo-prod-016', 'Maui Morning 12oz',                'demo-rcp-maui-morning',    'Bag', 'demo-size-12oz', 0.75, '00000000-0000-0000-0000-de0000000002', 18.49,  5.68,  5.38,  12.81, 30.7, 69.3, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', NOW() - INTERVAL '140 days'),

  -- Blends 1lb
  ('demo-prod-017', 'Hawaiian Blend 1lb',               'demo-rcp-hawaiian-blend',  'Bag', 'demo-size-1lb',  1.0,  '00000000-0000-0000-0000-de0000000002', 25.99, 10.63, 10.33, 15.36, 40.9, 59.1, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', NOW() - INTERVAL '180 days'),
  ('demo-prod-018', 'Aloha House Blend 1lb',            'demo-rcp-aloha-house',     'Bag', 'demo-size-1lb',  1.0,  '00000000-0000-0000-0000-de0000000002', 19.99,  5.08,  4.78,  14.91, 25.4, 74.6, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', NOW() - INTERVAL '180 days'),
  ('demo-prod-019', 'Volcanic Dark 1lb',                'demo-rcp-volcanic-drk',    'Bag', 'demo-size-1lb',  1.0,  '00000000-0000-0000-0000-de0000000002', 20.99,  5.30,  5.00,  15.69, 25.3, 74.7, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', NOW() - INTERVAL '160 days'),

  -- Espresso
  ('demo-prod-020', 'Pacific Sunrise Espresso 12oz',    'demo-rcp-pacific-sunrise', 'Bag', 'demo-size-12oz', 0.75, '00000000-0000-0000-0000-de0000000003', 17.99,  4.28,  3.98,  13.71, 23.8, 76.2, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', NOW() - INTERVAL '180 days'),
  ('demo-prod-021', 'Pacific Sunrise Espresso 1lb',     'demo-rcp-pacific-sunrise', 'Bag', 'demo-size-1lb',  1.0,  '00000000-0000-0000-0000-de0000000003', 23.49,  5.54,  5.24,  17.95, 23.6, 76.4, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', NOW() - INTERVAL '180 days'),

  -- 5lb wholesale
  ('demo-prod-022', 'Aloha House Blend 5lb',            'demo-rcp-aloha-house',     'Bag', 'demo-size-5lb',  5.0,  '00000000-0000-0000-0000-de0000000002', 74.99, 23.30, 22.00, 51.69, 31.1, 68.9, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', NOW() - INTERVAL '150 days'),
  ('demo-prod-023', 'Pacific Sunrise Espresso 5lb',     'demo-rcp-pacific-sunrise', 'Bag', 'demo-size-5lb',  5.0,  '00000000-0000-0000-0000-de0000000003', 84.99, 26.20, 24.90, 58.79, 30.8, 69.2, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', NOW() - INTERVAL '150 days'),

  -- Decaf
  ('demo-prod-024', 'Decaf Sunset Blend 12oz',          'demo-rcp-decaf-blend',     'Bag', 'demo-size-12oz', 0.75, '00000000-0000-0000-0000-de0000000004', 17.49,  5.03,  4.73,  12.46, 28.8, 71.2, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', NOW() - INTERVAL '120 days'),
  ('demo-prod-025', 'Decaf Sunset Blend 1lb',           'demo-rcp-decaf-blend',     'Bag', 'demo-size-1lb',  1.0,  '00000000-0000-0000-0000-de0000000004', 22.99,  6.50,  6.20,  16.49, 28.3, 71.7, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', NOW() - INTERVAL '120 days')
ON CONFLICT DO NOTHING;

-- ── 18. Consumable inventory ────────────────────────────────────────────────
INSERT INTO public.consumable_inventory (consumable_inventory_id, consumable_inventory_item, in_stock, par, restock_level, last_cost_unit,
  company_id, facility_id, created_by, inventory_count, last_inventory_date) VALUES
  ('demo-cons-001', '12oz Kraft Bag',          2500, 3000, 1500,  0.18, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', 2500, CURRENT_DATE - 3),
  ('demo-cons-002', '1lb Kraft Bag',           1800, 2000, 1000,  0.22, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', 1800, CURRENT_DATE - 3),
  ('demo-cons-003', '5lb Poly Bag',             200,  300,  150,  0.45, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin',  200, CURRENT_DATE - 3),
  ('demo-cons-004', '12oz Label - Blends',     3000, 3500, 1500,  0.08, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', 3000, CURRENT_DATE - 3),
  ('demo-cons-005', '12oz Label - Single Orig',2000, 2500, 1000,  0.08, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', 2000, CURRENT_DATE - 3),
  ('demo-cons-006', '1lb Label - Blends',      1500, 2000, 800,   0.09, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', 1500, CURRENT_DATE - 3),
  ('demo-cons-007', '1lb Label - Single Orig', 1200, 1500, 600,   0.09, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', 1200, CURRENT_DATE - 3),
  ('demo-cons-008', '5lb Label',                250,  400,  200,  0.12, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin',  250, CURRENT_DATE - 3),
  ('demo-cons-009', 'Degassing Valve',         4000, 5000, 2500,  0.03, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', 4000, CURRENT_DATE - 3),
  ('demo-cons-010', 'Tin Tie',                 4000, 5000, 2500,  0.02, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', 4000, CURRENT_DATE - 3),
  ('demo-cons-011', 'Shipping Box - Small',     300,  400,  200,  0.85, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin',  300, CURRENT_DATE - 3),
  ('demo-cons-012', 'Shipping Box - Large',     150,  200,  100,  1.25, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin',  150, CURRENT_DATE - 3),
  ('demo-cons-013', 'Packing Tape Roll',         25,   30,   15,  3.50, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin',   25, CURRENT_DATE - 3),
  ('demo-cons-014', 'Sticker - Aloha Logo',    1500, 2000, 1000,  0.04, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', 1500, CURRENT_DATE - 3),
  ('demo-cons-015', 'Barcode Label',           3000, 4000, 2000,  0.02, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin', 3000, CURRENT_DATE - 3)
ON CONFLICT DO NOTHING;

-- ── 19. Product consumables (BOM) ───────────────────────────────────────────
-- Link each product to its consumables (1 bag + 1 label + 1 valve + 1 tin tie + 1 sticker)
-- 12oz products
INSERT INTO public.product_consumables (product_consumable_id, product_id, consumable_id, quantity, company_id, facility_id) VALUES
  ('demo-pc-001', 'demo-prod-001', 'demo-cons-001', 1, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  ('demo-pc-002', 'demo-prod-001', 'demo-cons-005', 1, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  ('demo-pc-003', 'demo-prod-001', 'demo-cons-009', 1, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  ('demo-pc-004', 'demo-prod-001', 'demo-cons-014', 1, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  -- Blend 12oz (prod-011 Hawaiian Blend as example - all 12oz blends get same consumables)
  ('demo-pc-005', 'demo-prod-011', 'demo-cons-001', 1, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  ('demo-pc-006', 'demo-prod-011', 'demo-cons-004', 1, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  ('demo-pc-007', 'demo-prod-011', 'demo-cons-009', 1, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  ('demo-pc-008', 'demo-prod-011', 'demo-cons-014', 1, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  -- 1lb product (prod-008 Kona 1lb)
  ('demo-pc-009', 'demo-prod-008', 'demo-cons-002', 1, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  ('demo-pc-010', 'demo-prod-008', 'demo-cons-007', 1, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  ('demo-pc-011', 'demo-prod-008', 'demo-cons-009', 1, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  ('demo-pc-012', 'demo-prod-008', 'demo-cons-014', 1, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  -- 5lb product (prod-022 House 5lb)
  ('demo-pc-013', 'demo-prod-022', 'demo-cons-003', 1, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  ('demo-pc-014', 'demo-prod-022', 'demo-cons-008', 1, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  ('demo-pc-015', 'demo-prod-022', 'demo-cons-014', 1, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  -- Espresso 12oz (prod-020)
  ('demo-pc-016', 'demo-prod-020', 'demo-cons-001', 1, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  ('demo-pc-017', 'demo-prod-020', 'demo-cons-004', 1, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  ('demo-pc-018', 'demo-prod-020', 'demo-cons-009', 1, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  ('demo-pc-019', 'demo-prod-020', 'demo-cons-014', 1, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  -- Decaf 12oz (prod-024)
  ('demo-pc-020', 'demo-prod-024', 'demo-cons-001', 1, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  ('demo-pc-021', 'demo-prod-024', 'demo-cons-004', 1, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  ('demo-pc-022', 'demo-prod-024', 'demo-cons-009', 1, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery'),
  ('demo-pc-023', 'demo-prod-024', 'demo-cons-014', 1, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery')
ON CONFLICT DO NOTHING;

-- ── 20. Sales areas ─────────────────────────────────────────────────────────
INSERT INTO public.sales_area (id, area_name, company_id, created_by) VALUES
  ('demo-area-001', 'Kailua-Kona',      'demo-aloha-coffee-roasters', 'demo-team-admin'),
  ('demo-area-002', 'Hilo',             'demo-aloha-coffee-roasters', 'demo-team-admin'),
  ('demo-area-003', 'Waikiki',          'demo-aloha-coffee-roasters', 'demo-team-admin'),
  ('demo-area-004', 'North Shore Oahu', 'demo-aloha-coffee-roasters', 'demo-team-admin'),
  ('demo-area-005', 'Maui',             'demo-aloha-coffee-roasters', 'demo-team-admin'),
  ('demo-area-006', 'Online',           'demo-aloha-coffee-roasters', 'demo-team-admin')
ON CONFLICT DO NOTHING;

-- ── 21. Customer categories ─────────────────────────────────────────────────
INSERT INTO public.customer_category (customer_category) VALUES
  ('Cafe'), ('Restaurant'), ('Grocery'), ('Hotel'), ('Online'), ('Wholesale')
ON CONFLICT DO NOTHING;

-- ── 22. Customers ───────────────────────────────────────────────────────────
INSERT INTO public.customers (customer_id, name_company, customer_category, sales_area, city, state, email, phone,
  customer_since, company_id, facility_id, is_active, created_by, created_at) VALUES

  -- Cafes (12)
  ('demo-cust-001', 'Kona Coffee Shack',          'Cafe',       'demo-area-001', 'Kailua-Kona',  'HI', 'orders@konacoffeeshack.com',      '808-555-0101', '2024-03-15', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', true, 'demo-team-admin', NOW() - INTERVAL '2 years'),
  ('demo-cust-002', 'Lava Java Cafe',             'Cafe',       'demo-area-001', 'Kailua-Kona',  'HI', 'manager@lavajava.com',             '808-555-0102', '2024-06-01', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', true, 'demo-team-admin', NOW() - INTERVAL '2 years'),
  ('demo-cust-003', 'Hilo Bay Coffee',            'Cafe',       'demo-area-002', 'Hilo',         'HI', 'info@hilobaycoffee.com',           '808-555-0103', '2024-01-10', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', true, 'demo-team-admin', NOW() - INTERVAL '2 years'),
  ('demo-cust-004', 'Waikiki Brew Bar',           'Cafe',       'demo-area-003', 'Honolulu',     'HI', 'orders@waikikibrewbar.com',        '808-555-0104', '2024-09-20', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', true, 'demo-team-admin', NOW() - INTERVAL '1 year'),
  ('demo-cust-005', 'North Shore Grind',          'Cafe',       'demo-area-004', 'Haleiwa',      'HI', 'hello@northshoregrind.com',        '808-555-0105', '2025-01-05', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', true, 'demo-team-admin', NOW() - INTERVAL '1 year'),
  ('demo-cust-006', 'Maui Sunrise Cafe',          'Cafe',       'demo-area-005', 'Lahaina',      'HI', 'orders@mauisunrise.com',           '808-555-0106', '2025-02-14', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', true, 'demo-team-admin', NOW() - INTERVAL '1 year'),
  ('demo-cust-007', 'Paia Coffee Co',             'Cafe',       'demo-area-005', 'Paia',         'HI', 'hello@paiacoffee.com',             '808-555-0107', '2025-04-01', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', true, 'demo-team-admin', NOW() - INTERVAL '11 months'),
  ('demo-cust-008', 'Volcano Espresso Bar',       'Cafe',       'demo-area-002', 'Volcano',      'HI', 'info@volcanoespresso.com',         '808-555-0108', '2025-05-15', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', true, 'demo-team-admin', NOW() - INTERVAL '10 months'),
  ('demo-cust-009', 'Kailua Village Coffee',      'Cafe',       'demo-area-001', 'Kailua-Kona',  'HI', 'orders@kailuavillagecoffee.com',   '808-555-0109', '2025-07-01', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', true, 'demo-team-admin', NOW() - INTERVAL '9 months'),
  ('demo-cust-010', 'Kapaa Morning Brew',         'Cafe',       'demo-area-004', 'Kapaa',        'HI', 'info@kapaamorning.com',            '808-555-0110', '2025-08-10', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', true, 'demo-team-admin', NOW() - INTERVAL '8 months'),
  ('demo-cust-011', 'Diamond Head Drip',          'Cafe',       'demo-area-003', 'Honolulu',     'HI', 'orders@diamondheaddrip.com',       '808-555-0111', '2025-10-01', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', true, 'demo-team-admin', NOW() - INTERVAL '6 months'),
  ('demo-cust-012', 'Hamakua Coast Coffee',       'Cafe',       'demo-area-002', 'Honokaa',      'HI', 'hello@hamakuacoast.com',           '808-555-0112', '2025-11-15', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', true, 'demo-team-admin', NOW() - INTERVAL '5 months'),

  -- Restaurants (6)
  ('demo-cust-013', 'Merriman''s Big Island',     'Restaurant', 'demo-area-001', 'Waimea',       'HI', 'purchasing@merrimans.com',          '808-555-0113', '2024-05-01', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', true, 'demo-team-admin', NOW() - INTERVAL '2 years'),
  ('demo-cust-014', 'Hualalai Grille',            'Restaurant', 'demo-area-001', 'Kailua-Kona',  'HI', 'chef@hualalagrille.com',            '808-555-0114', '2024-08-01', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', true, 'demo-team-admin', NOW() - INTERVAL '2 years'),
  ('demo-cust-015', 'Mama''s Fish House',         'Restaurant', 'demo-area-005', 'Paia',         'HI', 'bar@mamasfishhouse.com',            '808-555-0115', '2025-01-15', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', true, 'demo-team-admin', NOW() - INTERVAL '1 year'),
  ('demo-cust-016', 'Monkeypod Kitchen',          'Restaurant', 'demo-area-003', 'Honolulu',     'HI', 'orders@monkeypodkitchen.com',       '808-555-0116', '2025-06-01', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', true, 'demo-team-admin', NOW() - INTERVAL '10 months'),
  ('demo-cust-017', 'Hilo Bay Grill',             'Restaurant', 'demo-area-002', 'Hilo',         'HI', 'mgr@hilobaygrill.com',              '808-555-0117', '2025-09-01', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', true, 'demo-team-admin', NOW() - INTERVAL '7 months'),
  ('demo-cust-018', 'The Lanai Restaurant',       'Restaurant', 'demo-area-005', 'Lahaina',      'HI', 'orders@thelanai.com',               '808-555-0118', '2026-01-10', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', true, 'demo-team-admin', NOW() - INTERVAL '3 months'),

  -- Grocery / Retail (5)
  ('demo-cust-019', 'Island Naturals Market',     'Grocery',    'demo-area-001', 'Kailua-Kona',  'HI', 'buyer@islandnaturals.com',          '808-555-0119', '2024-02-01', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', true, 'demo-team-admin', NOW() - INTERVAL '2 years'),
  ('demo-cust-020', 'KTA Super Stores',           'Grocery',    'demo-area-002', 'Hilo',         'HI', 'vendor@ktasuperstores.com',          '808-555-0120', '2024-04-15', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', true, 'demo-team-admin', NOW() - INTERVAL '2 years'),
  ('demo-cust-021', 'Foodland Farms Waikiki',     'Grocery',    'demo-area-003', 'Honolulu',     'HI', 'local@foodlandfarms.com',            '808-555-0121', '2025-03-01', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', true, 'demo-team-admin', NOW() - INTERVAL '1 year'),
  ('demo-cust-022', 'Choice Mart Kailua',         'Grocery',    'demo-area-001', 'Kailua-Kona',  'HI', 'purchasing@choicemart.com',          '808-555-0122', '2025-07-15', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', true, 'demo-team-admin', NOW() - INTERVAL '9 months'),
  ('demo-cust-023', 'Mana Foods Paia',            'Grocery',    'demo-area-005', 'Paia',         'HI', 'buyer@manafoods.com',               '808-555-0123', '2025-11-01', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', true, 'demo-team-admin', NOW() - INTERVAL '5 months'),

  -- Hotels (4)
  ('demo-cust-024', 'Mauna Lani Resort',          'Hotel',      'demo-area-001', 'Kohala Coast', 'HI', 'fb@maunalani.com',                  '808-555-0124', '2024-07-01', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', true, 'demo-team-admin', NOW() - INTERVAL '2 years'),
  ('demo-cust-025', 'Fairmont Orchid',            'Hotel',      'demo-area-001', 'Kohala Coast', 'HI', 'purchasing@fairmontorchid.com',      '808-555-0125', '2025-02-01', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', true, 'demo-team-admin', NOW() - INTERVAL '1 year'),
  ('demo-cust-026', 'Four Seasons Hualalai',      'Hotel',      'demo-area-001', 'Kailua-Kona',  'HI', 'chef@fshualalai.com',               '808-555-0126', '2025-05-01', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', true, 'demo-team-admin', NOW() - INTERVAL '11 months'),
  ('demo-cust-027', 'Grand Wailea Resort',        'Hotel',      'demo-area-005', 'Wailea',       'HI', 'fb@grandwailea.com',                '808-555-0127', '2025-08-01', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', true, 'demo-team-admin', NOW() - INTERVAL '8 months'),

  -- Online (3)
  ('demo-cust-028', 'Web - Direct',               'Online',     'demo-area-006', NULL,           NULL, NULL,                                 NULL,           '2024-01-01', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', true, 'demo-team-admin', NOW() - INTERVAL '2 years'),
  ('demo-cust-029', 'Amazon Storefront',          'Online',     'demo-area-006', NULL,           NULL, NULL,                                 NULL,           '2025-06-01', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', true, 'demo-team-admin', NOW() - INTERVAL '10 months'),
  ('demo-cust-030', 'Faire Wholesale',            'Wholesale',  'demo-area-006', NULL,           NULL, 'hello@alohacoffee.faire.com',        NULL,           '2025-09-15', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', true, 'demo-team-admin', NOW() - INTERVAL '7 months')
ON CONFLICT DO NOTHING;

-- ── 23. Contacts ────────────────────────────────────────────────────────────
INSERT INTO public.contacts (contact_id, contact, role, email, phone, customer_id, is_primary, company_id, facility_id, created_by) VALUES
  ('demo-cont-001', 'Mike Kalani',      'Owner',              'mike@konacoffeeshack.com',       '808-555-0201', 'demo-cust-001', true,  'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-cont-002', 'Sarah Leilani',    'Manager',            'sarah@lavajava.com',             '808-555-0202', 'demo-cust-002', true,  'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-cont-003', 'David Nakamura',   'Barista Lead',       'david@hilobaycoffee.com',        '808-555-0203', 'demo-cust-003', true,  'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-cont-004', 'Jen Tanaka',       'Head Barista',       'jen@waikikibrewbar.com',         '808-555-0204', 'demo-cust-004', true,  'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-cont-005', 'Tom Kealoha',      'Owner',              'tom@northshoregrind.com',        '808-555-0205', 'demo-cust-005', true,  'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-cont-006', 'Lisa Pukui',       'Purchasing Manager', 'lisa@mauisunrise.com',           '808-555-0206', 'demo-cust-006', true,  'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-cont-007', 'James Wong',       'Chef',               'james@merrimans.com',            '808-555-0207', 'demo-cust-013', true,  'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-cont-008', 'Amy Rodrigues',    'Buyer',              'amy@islandnaturals.com',         '808-555-0208', 'demo-cust-019', true,  'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-cont-009', 'Robert Chun',      'Category Manager',   'robert@ktasuperstores.com',      '808-555-0209', 'demo-cust-020', true,  'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-cont-010', 'Karen Mahina',     'F&B Director',       'karen@maunalani.com',            '808-555-0210', 'demo-cust-024', true,  'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin')
ON CONFLICT DO NOTHING;

-- ── 24. Shipments received ──────────────────────────────────────────────────
INSERT INTO public.shipment_received (shipment_id, supplier_id, shipping_cost, date_received, order_date,
  company_id, facility_id, created_by) VALUES
  ('demo-ship-001', 'demo-sup-001', 450.00, CURRENT_DATE - 75, CURRENT_DATE - 90,  'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-ship-002', 'demo-sup-002', 120.00, CURRENT_DATE - 60, CURRENT_DATE - 70,  'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-ship-003', 'demo-sup-004', 380.00, CURRENT_DATE - 45, CURRENT_DATE - 60,  'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-ship-004', 'demo-sup-001', 520.00, CURRENT_DATE - 30, CURRENT_DATE - 45,  'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-ship-005', 'demo-sup-003', 85.00,  CURRENT_DATE - 25, CURRENT_DATE - 35,  'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-ship-006', 'demo-sup-002', 120.00, CURRENT_DATE - 15, CURRENT_DATE - 25,  'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-ship-007', 'demo-sup-004', 290.00, CURRENT_DATE - 10, CURRENT_DATE - 20,  'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-ship-008', 'demo-sup-005', 45.00,  CURRENT_DATE - 8,  CURRENT_DATE - 15,  'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  -- Pending shipments (no date_received)
  ('demo-ship-009', 'demo-sup-001', NULL,    NULL,              CURRENT_DATE - 5,   'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-ship-010', 'demo-sup-003', NULL,    NULL,              CURRENT_DATE - 3,   'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin')
ON CONFLICT DO NOTHING;

-- ── 25. Coffee inventory purchased ──────────────────────────────────────────
INSERT INTO public.coffee_inventory_purchased (origin_purchase_id, shipment_id, origin, lot_id, cost_lb, amount, bags_ordered,
  coffee_source_id, harvest_year, bag_size, company_id, facility_id, created_by) VALUES
  -- Shipment 1: Brazil + Colombia + Guatemala + Sumatra
  ('demo-cip-001', 'demo-ship-001', 'demo-org-brazil',   'BR-2025-A', 3.85, 1540, 10, 'demo-cs-003', 2025, '154', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-cip-002', 'demo-ship-001', 'demo-org-colombia', 'CO-2025-A', 4.25, 1540, 10, 'demo-cs-004', 2025, '154', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-cip-003', 'demo-ship-001', 'demo-org-guate',    'GT-2025-A', 4.50,  770,  5, 'demo-cs-008', 2025, '154', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-cip-004', 'demo-ship-001', 'demo-org-sumatra',  'ID-2025-A', 4.10, 1540, 10, 'demo-cs-011', 2025, '154', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),

  -- Shipment 2: Kona
  ('demo-cip-005', 'demo-ship-002', 'demo-org-kona',     'HI-2025-A', 28.50, 500,  5, 'demo-cs-001', 2025, '100', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),

  -- Shipment 3: Ethiopia + Kenya + Rwanda + El Salvador
  ('demo-cip-006', 'demo-ship-003', 'demo-org-ethiopia', 'ET-2025-A', 5.90,  660,  5, 'demo-cs-006', 2025, '132', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-cip-007', 'demo-ship-003', 'demo-org-kenya',    'KE-2025-A', 6.20,  528,  4, 'demo-cs-010', 2025, '132', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-cip-008', 'demo-ship-003', 'demo-org-rwanda',   'RW-2025-A', 5.30,  396,  3, 'demo-cs-016', 2025, '132', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-cip-009', 'demo-ship-003', 'demo-org-elsalv',   'SV-2025-A', 5.50,  264,  2, 'demo-cs-014', 2025, '132', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),

  -- Shipment 4: Costa Rica + Mexico + Peru + PNG + Decaf
  ('demo-cip-010', 'demo-ship-004', 'demo-org-costa',    'CR-2025-A', 4.75,  770,  5, 'demo-cs-009', 2025, '154', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-cip-011', 'demo-ship-004', 'demo-org-mexico',   'MX-2025-A', 3.40,  924,  6, 'demo-cs-013', 2025, '154', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-cip-012', 'demo-ship-004', 'demo-org-peru',     'PE-2025-A', 3.60,  462,  3, 'demo-cs-012', 2025, '154', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-cip-013', 'demo-ship-004', 'demo-org-png',      'PG-2025-A', 4.00,  770,  5, 'demo-cs-015', 2025, '154', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-cip-014', 'demo-ship-004', 'demo-org-decaf-co', 'DC-2025-A', 5.00,  616,  4, 'demo-cs-017', 2025, '154', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),

  -- Shipment 6: more Kona
  ('demo-cip-015', 'demo-ship-006', 'demo-org-kona',     'HI-2025-B', 29.00, 300,  3, 'demo-cs-002', 2025, '100', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),

  -- Shipment 7: Ethiopia + Decaf Ethiopia + Kenya
  ('demo-cip-016', 'demo-ship-007', 'demo-org-ethiopia',  'ET-2025-B', 6.10,  396,  3, 'demo-cs-007', 2025, '132', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-cip-017', 'demo-ship-007', 'demo-org-decaf-et',  'DE-2025-A', 5.80,  264,  2, 'demo-cs-018', 2025, '132', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-cip-018', 'demo-ship-007', 'demo-org-kenya',     'KE-2025-B', 6.40,  264,  2, 'demo-cs-020', 2025, '132', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),

  -- Pending shipment 9: Brazil + Colombia reorder
  ('demo-cip-019', 'demo-ship-009', 'demo-org-brazil',   'BR-2026-A', 3.95, 1540, 10, 'demo-cs-019', 2025, '154', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-cip-020', 'demo-ship-009', 'demo-org-colombia', 'CO-2026-A', 4.35, 1540, 10, 'demo-cs-005', 2025, '154', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin')
ON CONFLICT DO NOTHING;

-- ── 26. Consumable purchases ────────────────────────────────────────────────
INSERT INTO public.consumable_inventory_purchased (consumable_purchase_id, shipment_id, consumable_inventory_item, cost_unit, amount,
  company_id, facility_id, created_by) VALUES
  ('demo-consp-001', 'demo-ship-005', 'demo-cons-001', 0.18, 5000, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-consp-002', 'demo-ship-005', 'demo-cons-002', 0.22, 3000, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-consp-003', 'demo-ship-005', 'demo-cons-009', 0.03, 10000,'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-consp-004', 'demo-ship-008', 'demo-cons-004', 0.08, 5000, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-consp-005', 'demo-ship-008', 'demo-cons-005', 0.08, 3000, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-consp-006', 'demo-ship-008', 'demo-cons-014', 0.04, 5000, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-consp-007', 'demo-ship-008', 'demo-cons-015', 0.02, 5000, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin')
ON CONFLICT DO NOTHING;

-- ── 27. Orders (110 orders over 3 months) ───────────────────────────────────
-- Generate realistic orders with a mix of statuses.
-- We use a DO block to procedurally generate orders.
DO $$
DECLARE
  v_order_id     text;
  v_detail_id    text;
  v_customer_ids text[] := ARRAY[
    'demo-cust-001','demo-cust-002','demo-cust-003','demo-cust-004','demo-cust-005',
    'demo-cust-006','demo-cust-007','demo-cust-008','demo-cust-009','demo-cust-010',
    'demo-cust-011','demo-cust-012','demo-cust-013','demo-cust-014','demo-cust-015',
    'demo-cust-016','demo-cust-017','demo-cust-018','demo-cust-019','demo-cust-020',
    'demo-cust-021','demo-cust-022','demo-cust-023','demo-cust-024','demo-cust-025',
    'demo-cust-026','demo-cust-027','demo-cust-028','demo-cust-029','demo-cust-030'
  ];
  v_product_ids  text[] := ARRAY[
    'demo-prod-001','demo-prod-002','demo-prod-003','demo-prod-004','demo-prod-005',
    'demo-prod-006','demo-prod-007','demo-prod-008','demo-prod-009','demo-prod-010',
    'demo-prod-011','demo-prod-012','demo-prod-013','demo-prod-014','demo-prod-015',
    'demo-prod-016','demo-prod-017','demo-prod-018','demo-prod-019','demo-prod-020',
    'demo-prod-021','demo-prod-022','demo-prod-023','demo-prod-024','demo-prod-025'
  ];
  v_statuses     text[] := ARRAY['Delivered','Delivered','Delivered','Delivered','Delivered','Packed','Packed','Open','Open','Open'];
  v_order_date   date;
  v_status       text;
  v_cust_id      text;
  v_prod_id      text;
  v_qty          numeric;
  v_price        numeric;
  v_weight       numeric;
  v_cogs         numeric;
  v_order_total  numeric;
  v_total_weight numeric;
  v_items_count  int;
  v_item_status  text;
  i              int;
  j              int;
BEGIN
  FOR i IN 1..110 LOOP
    v_order_id := 'demo-ord-' || lpad(i::text, 3, '0');

    -- Skip if already exists
    IF EXISTS (SELECT 1 FROM public.orders WHERE order_id = v_order_id) THEN
      CONTINUE;
    END IF;

    -- Date spread: last 90 days, more recent orders more likely
    v_order_date := CURRENT_DATE - (floor(random() * 90))::int;

    -- Status: older orders more likely delivered
    IF v_order_date < CURRENT_DATE - 21 THEN
      v_status := 'Delivered';
    ELSIF v_order_date < CURRENT_DATE - 7 THEN
      v_status := (ARRAY['Delivered','Delivered','Delivered','Packed','Packed'])[floor(random()*5+1)::int];
    ELSIF v_order_date < CURRENT_DATE - 2 THEN
      v_status := (ARRAY['Packed','Packed','Open','Open','Delivered'])[floor(random()*5+1)::int];
    ELSE
      v_status := (ARRAY['Open','Open','Open','Packed'])[floor(random()*4+1)::int];
    END IF;

    -- Add some canceled orders (about 5%)
    IF random() < 0.05 THEN
      v_status := 'Canceled';
    END IF;

    -- Pick customer (cycle through with some randomness)
    v_cust_id := v_customer_ids[((i - 1) % 30) + 1];

    v_order_total := 0;
    v_total_weight := 0;

    -- Insert order
    INSERT INTO public.orders (order_id, customer_id, order_date, order_status, company_id, facility_id, created_by, created_at,
      status_changed_at)
    VALUES (
      v_order_id,
      v_cust_id,
      v_order_date,
      v_status,
      'demo-aloha-coffee-roasters',
      'demo-kailua-roastery',
      'demo-team-admin',
      v_order_date::timestamp + (random() * INTERVAL '8 hours'),
      CASE WHEN v_status IN ('Packed','Delivered') THEN v_order_date::timestamptz + INTERVAL '1 day'
           ELSE NULL END
    );

    -- 1-5 line items per order
    v_items_count := floor(random() * 4 + 1)::int + 1;

    FOR j IN 1..v_items_count LOOP
      v_detail_id := v_order_id || '-d' || j;

      -- Pick product (distribute across products)
      v_prod_id := v_product_ids[floor(random() * 25 + 1)::int];

      -- Get product info
      SELECT p.price, p.weight_lbs, p.total_unit_cogs
        INTO v_price, v_weight, v_cogs
        FROM public.products p WHERE p.product_id = v_prod_id;

      v_price  := COALESCE(v_price, 15.99);
      v_weight := COALESCE(v_weight, 0.75);
      v_cogs   := COALESCE(v_cogs, 4.00);

      -- Quantity: mostly small (1-6), sometimes larger for wholesale
      IF v_cust_id IN ('demo-cust-019','demo-cust-020','demo-cust-021','demo-cust-024','demo-cust-025','demo-cust-026','demo-cust-027','demo-cust-030') THEN
        v_qty := floor(random() * 20 + 5)::numeric;
      ELSE
        v_qty := floor(random() * 5 + 1)::numeric;
      END IF;

      -- Item status matches order status
      v_item_status := CASE
        WHEN v_status = 'Open' THEN 'Open'
        WHEN v_status = 'Packed' THEN 'Packed'
        WHEN v_status = 'Delivered' THEN 'Packed'
        WHEN v_status = 'Canceled' THEN 'Open'
      END;

      INSERT INTO public.order_details (order_detail_id, order_id, product_id, quantity, item_status,
        total_price, roasted_weight, unit_cost_at_sale, order_date, customer_id,
        company_id, facility_id, created_by, created_at)
      VALUES (
        v_detail_id,
        v_order_id,
        v_prod_id,
        v_qty,
        v_item_status,
        round((v_price * v_qty)::numeric, 2),
        round((v_weight * v_qty)::numeric, 2),
        round((v_cogs * v_qty)::numeric, 2),
        v_order_date,
        v_cust_id,
        'demo-aloha-coffee-roasters',
        'demo-kailua-roastery',
        'demo-team-admin',
        v_order_date::timestamp + (random() * INTERVAL '8 hours')
      );

      v_order_total  := v_order_total + round((v_price * v_qty)::numeric, 2);
      v_total_weight := v_total_weight + round((v_weight * v_qty)::numeric, 2);
    END LOOP;

    -- Update order totals
    UPDATE public.orders SET order_total = v_order_total, total_weight = v_total_weight
    WHERE order_id = v_order_id;
  END LOOP;
END $$;

-- ── 28. Roast log (85 entries over 2 months) ────────────────────────────────
DO $$
DECLARE
  v_roast_id     text;
  v_recipe_ids   text[] := ARRAY[
    'demo-rcp-hawaiian-blend','demo-rcp-kona-dark','demo-rcp-pacific-sunrise',
    'demo-rcp-island-breeze','demo-rcp-volcanic-drk','demo-rcp-tradewind',
    'demo-rcp-aloha-house','demo-rcp-maui-morning','demo-rcp-decaf-blend',
    'demo-rcp-single-ethiopia'
  ];
  v_origin_ids   text[] := ARRAY[
    'demo-org-kona','demo-org-brazil','demo-org-colombia','demo-org-ethiopia',
    'demo-org-guate','demo-org-costa','demo-org-kenya','demo-org-sumatra'
  ];
  v_recipe_id    text;
  v_origin_id    text;
  v_charge_wt    numeric;
  v_roasted_wt   numeric;
  v_roast_date   timestamp;
  v_roast_type   text;
  i              int;
BEGIN
  FOR i IN 1..85 LOOP
    v_roast_id := 'demo-roast-' || lpad(i::text, 3, '0');

    IF EXISTS (SELECT 1 FROM public.roast_log WHERE roast_log_id = v_roast_id) THEN
      CONTINUE;
    END IF;

    -- Date spread over last 60 days, local Hawaii time
    v_roast_date := (CURRENT_DATE - (floor(random() * 60))::int)::timestamp
                    + (INTERVAL '6 hours' + random() * INTERVAL '8 hours');

    -- Alternate between blend roasts (no origin) and single-origin roasts
    IF random() < 0.55 THEN
      -- Blend roast: use recipe, no origin
      v_recipe_id := v_recipe_ids[floor(random() * 10 + 1)::int];
      v_origin_id := NULL;
      v_roast_type := 'Pre-Blend';
    ELSE
      -- Single origin roast: origin, optional recipe
      v_origin_id := v_origin_ids[floor(random() * 8 + 1)::int];
      IF random() < 0.3 THEN
        v_recipe_id := 'demo-rcp-kona-dark';
      ELSE
        v_recipe_id := NULL;
      END IF;
      v_roast_type := 'Single Origin/Post-Blend';
    END IF;

    -- Charge weight: 15 or 25 lbs
    IF random() < 0.7 THEN
      v_charge_wt := 25;
    ELSE
      v_charge_wt := 15;
    END IF;

    -- Roasted weight = charge * retention (0.80-0.84 range)
    v_roasted_wt := round((v_charge_wt * (0.80 + random() * 0.04))::numeric, 2);

    INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id,
      charge_weight, charge_weight_lbs, roasted_weight, "charged?",
      roaster_unit_id, roast_type, company_id, facility_id, created_by, created_at)
    VALUES (
      v_roast_id,
      v_roast_date,
      v_origin_id,
      v_recipe_id,
      CASE WHEN v_charge_wt = 25 THEN 'demo-cw-25' ELSE 'demo-cw-15' END,
      v_charge_wt,
      v_roasted_wt,
      true,
      'a0a0a0a0-0001-4000-8000-000000000001'::uuid,
      v_roast_type,
      'demo-aloha-coffee-roasters',
      'demo-kailua-roastery',
      'demo-team-admin',
      v_roast_date
    );
  END LOOP;
END $$;

-- ── 29. Price log (one entry per product) ───────────────────────────────────
INSERT INTO public.products_price_log (price_log_id, product_id, price, date_updated, company_id, facility_id, created_by, created_at)
SELECT
  'demo-pl-' || product_id,
  product_id,
  price,
  (created_at::date),
  company_id,
  facility_id,
  'demo-team-admin',
  created_at
FROM public.products
WHERE company_id = 'demo-aloha-coffee-roasters'
  AND NOT EXISTS (
    SELECT 1 FROM public.products_price_log pl WHERE pl.price_log_id = 'demo-pl-' || products.product_id
  );

-- ── 30. Coffee inventory history (manual counts) ────────────────────────────
INSERT INTO public.coffee_inventory_history (history_id, origin_id, inventory_date, bag_count, company_id, facility_id, created_by) VALUES
  ('demo-cih-001', 'demo-org-kona',     CURRENT_DATE - 30, 10, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-cih-002', 'demo-org-brazil',   CURRENT_DATE - 30, 15, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-cih-003', 'demo-org-colombia', CURRENT_DATE - 30, 12, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-cih-004', 'demo-org-ethiopia', CURRENT_DATE - 30,  8, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-cih-005', 'demo-org-sumatra',  CURRENT_DATE - 30, 11, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-cih-006', 'demo-org-kona',     CURRENT_DATE - 5,   8, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-cih-007', 'demo-org-brazil',   CURRENT_DATE - 5,  12, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-cih-008', 'demo-org-colombia', CURRENT_DATE - 5,  10, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin')
ON CONFLICT DO NOTHING;

-- ── 31. Consumable inventory history ────────────────────────────────────────
INSERT INTO public.consumable_inventory_history (history_id, consumable_id, inventory_date, inventory_count, company_id, facility_id, created_by) VALUES
  ('demo-coih-001', 'demo-cons-001', CURRENT_DATE - 30, 3200, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-coih-002', 'demo-cons-002', CURRENT_DATE - 30, 2100, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-coih-003', 'demo-cons-009', CURRENT_DATE - 30, 5500, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-coih-004', 'demo-cons-001', CURRENT_DATE - 3,  2500, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin'),
  ('demo-coih-005', 'demo-cons-002', CURRENT_DATE - 3,  1800, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', 'demo-team-admin')
ON CONFLICT DO NOTHING;

-- ── Done ────────────────────────────────────────────────────────────────────
-- Restore normal trigger behavior
RESET session_replication_role;

COMMIT;
