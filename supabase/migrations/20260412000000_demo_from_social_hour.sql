-- Migration: Replace demo data with Social Hour Waikapu data (renamed)
-- Source: facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de' (Social Hour Coffee Roasters, Waikapu)
-- Target: facility_id = 'demo-kailua-roastery' (Aloha Coffee Roasters / Strata Coffee Roasters)

SET statement_timeout = 0;

-- ============================================================
-- PHASE 1: WIPE EXISTING DEMO DATA
-- ============================================================
SET session_replication_role = replica;

DELETE FROM weekly_roast_snapshot      WHERE facility_id = 'demo-kailua-roastery';
DELETE FROM order_details              WHERE facility_id = 'demo-kailua-roastery';
DELETE FROM orders                     WHERE facility_id = 'demo-kailua-roastery';
DELETE FROM products_price_log         WHERE facility_id = 'demo-kailua-roastery';
DELETE FROM product_consumables
  WHERE product_id IN (SELECT product_id FROM products WHERE facility_id = 'demo-kailua-roastery');
DELETE FROM products                   WHERE facility_id = 'demo-kailua-roastery';
DELETE FROM customers                  WHERE facility_id = 'demo-kailua-roastery';
DELETE FROM recipe_components          WHERE facility_id = 'demo-kailua-roastery';
DELETE FROM roast_recipes              WHERE facility_id = 'demo-kailua-roastery';
DELETE FROM roast_log                  WHERE facility_id = 'demo-kailua-roastery';
DELETE FROM coffee_inventory_purchased WHERE facility_id = 'demo-kailua-roastery';
DELETE FROM coffee_inventory           WHERE facility_id = 'demo-kailua-roastery';
DELETE FROM consumable_inventory       WHERE facility_id = 'demo-kailua-roastery';
DELETE FROM shipment_received          WHERE facility_id = 'demo-kailua-roastery';
DELETE FROM product_groups             WHERE company_id  = 'demo-aloha-coffee-roasters';
DELETE FROM size                       WHERE company_id  = 'demo-aloha-coffee-roasters';
DELETE FROM sales_area                 WHERE company_id  = 'demo-aloha-coffee-roasters';
DELETE FROM product_type               WHERE company_id  = 'demo-aloha-coffee-roasters';
DELETE FROM consumable_type            WHERE company_id  = 'demo-aloha-coffee-roasters';
DELETE FROM company_parameters         WHERE facility_id = 'demo-kailua-roastery';
DELETE FROM charge_weight_options      WHERE facility_id = 'demo-kailua-roastery';
DELETE FROM contacts                   WHERE facility_id = 'demo-kailua-roastery';
DELETE FROM consumable_inventory_history WHERE facility_id = 'demo-kailua-roastery';
DELETE FROM coffee_inventory_history   WHERE facility_id = 'demo-kailua-roastery';
DELETE FROM coffee_source              WHERE company_id   = 'demo-aloha-coffee-roasters';
DELETE FROM user_roaster_settings      WHERE facility_id = 'demo-kailua-roastery';
DELETE FROM blending_worksheet         WHERE facility_id = 'demo-kailua-roastery';
DELETE FROM staged_line_items          WHERE facility_id = 'demo-kailua-roastery';
DELETE FROM staged_shipments           WHERE facility_id = 'demo-kailua-roastery';
DELETE FROM invitations                WHERE facility_id = 'demo-kailua-roastery';

-- ============================================================
-- PHASE 2: BUILD ID MAPPING TEMP TABLES
-- ============================================================

-- product_groups.group_id is UUID type
CREATE TEMP TABLE _map_groups AS
  SELECT group_id AS src, gen_random_uuid() AS dst
  FROM product_groups WHERE company_id = 'R7CbqHmA1j';

CREATE TEMP TABLE _map_sizes AS
  SELECT size_id AS src, 'demo-sz-' || row_number() OVER(ORDER BY size_id) AS dst
  FROM size WHERE company_id = 'R7CbqHmA1j';

CREATE TEMP TABLE _map_recipes AS
  SELECT recipe_id AS src, 'demo-rcp-' || row_number() OVER(ORDER BY recipe_id) AS dst
  FROM roast_recipes WHERE facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de';

CREATE TEMP TABLE _map_origins AS
  SELECT origin_id AS src, 'demo-org-' || row_number() OVER(ORDER BY origin_id) AS dst
  FROM coffee_inventory WHERE facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de';

CREATE TEMP TABLE _map_shipments AS
  SELECT shipment_id AS src, 'demo-ship-' || row_number() OVER(ORDER BY shipment_id) AS dst
  FROM shipment_received WHERE facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de';

CREATE TEMP TABLE _map_products AS
  SELECT product_id AS src, 'demo-prod-' || row_number() OVER(ORDER BY product_id) AS dst
  FROM products WHERE facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de';

CREATE TEMP TABLE _map_customers AS
  SELECT customer_id AS src, 'demo-cust-' || row_number() OVER(ORDER BY customer_id) AS dst
  FROM customers WHERE facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de';

CREATE TEMP TABLE _map_orders AS
  SELECT order_id AS src, gen_random_uuid()::text AS dst
  FROM orders WHERE facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de';

-- sales_area: id is text PK, orders.area also stores these IDs
CREATE TEMP TABLE _map_areas AS
  SELECT id AS src, 'demo-area-' || row_number() OVER(ORDER BY id) AS dst
  FROM sales_area WHERE company_id = 'R7CbqHmA1j';

-- product_type: product_type_id is text
CREATE TEMP TABLE _map_ptypes AS
  SELECT product_type_id AS src, gen_random_uuid()::text AS dst, product_type
  FROM product_type WHERE company_id = 'R7CbqHmA1j';

-- consumable_type: consumable_type_id is text
CREATE TEMP TABLE _map_ctypes AS
  SELECT consumable_type_id AS src, gen_random_uuid()::text AS dst, consumable_type, is_active
  FROM consumable_type WHERE company_id = 'R7CbqHmA1j';

-- consumable_inventory
CREATE TEMP TABLE _map_consumables AS
  SELECT consumable_inventory_id AS src, 'demo-cons-' || row_number() OVER(ORDER BY consumable_inventory_id) AS dst
  FROM consumable_inventory WHERE facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de';

-- restock_category: match by name between Social Hour and demo
CREATE TEMP TABLE _map_restock AS
  SELECT sh.restock_category_id AS src, demo.restock_category_id AS dst
  FROM restock_category sh
  JOIN restock_category demo ON demo.name = sh.name
    AND demo.facility_id = 'demo-kailua-roastery'
  WHERE sh.facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de';

-- charge_weight_options: generate new UUIDs (PK is facility-independent, can't reuse Social Hour UUIDs)
CREATE TEMP TABLE _map_charge_weights AS
  SELECT id AS src, gen_random_uuid() AS dst, charge_weight
  FROM charge_weight_options WHERE facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de';

-- ============================================================
-- PHASE 3: COPY DATA IN DEPENDENCY ORDER
-- ============================================================

-- 3a. product_type (company-scoped, text PK)
INSERT INTO product_type (product_type_id, product_type, company_id, is_active)
SELECT dst, product_type, 'demo-aloha-coffee-roasters', TRUE FROM _map_ptypes;

-- 3b. consumable_type (company-scoped, text PK)
INSERT INTO consumable_type (consumable_type_id, consumable_type, company_id, is_active)
SELECT dst, consumable_type, 'demo-aloha-coffee-roasters', is_active FROM _map_ctypes;

-- 3c. charge_weight_options — new UUIDs for demo facility (can't copy Social Hour UUIDs, PK is global)
INSERT INTO charge_weight_options (id, charge_weight, facility_id, company_id, created_at, updated_at)
SELECT mcw.dst, cwo.charge_weight, 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', cwo.created_at, cwo.updated_at
FROM charge_weight_options cwo
JOIN _map_charge_weights mcw ON mcw.src = cwo.id
WHERE cwo.facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de';

-- Update demo roaster_units.max_charge_weight_id using mapped new UUIDs (lookup by lb value)
-- Probat P25 → 25 lb option; Diedrich IR-12 → 15 lb option
UPDATE roaster_units SET max_charge_weight_id = (
  SELECT mcw.dst FROM _map_charge_weights mcw WHERE mcw.charge_weight = 25 LIMIT 1
) WHERE roaster_unit_id = 'a0a0a0a0-0001-4000-8000-000000000001';
UPDATE roaster_units SET max_charge_weight_id = (
  SELECT mcw.dst FROM _map_charge_weights mcw WHERE mcw.charge_weight = 15 LIMIT 1
) WHERE roaster_unit_id = 'a0a0a0a0-0001-4000-8000-000000000002';

-- 3d. product_groups (company-scoped, UUID PK)
INSERT INTO product_groups (group_id, group_name, description, company_id, facility_id, created_at, updated_at)
SELECT mg.dst, pg.group_name, pg.description,
  'demo-aloha-coffee-roasters', 'demo-kailua-roastery', pg.created_at, pg.updated_at
FROM product_groups pg
JOIN _map_groups mg ON mg.src = pg.group_id
WHERE pg.company_id = 'R7CbqHmA1j';

-- 3e. size (company-scoped, text PK)
INSERT INTO size (size_id, size_name, weight, company_id, created_at, updated_at)
SELECT ms.dst, s.size_name, s.weight, 'demo-aloha-coffee-roasters', s.created_at, s.updated_at
FROM size s
JOIN _map_sizes ms ON ms.src = s.size_id
WHERE s.company_id = 'R7CbqHmA1j';

-- 3f. sales_area (company-scoped; PK = id text, name column = area_name)
INSERT INTO sales_area (id, area_name, company_id, state_id, created_at, updated_at)
SELECT ma.dst, sa.area_name, 'demo-aloha-coffee-roasters', sa.state_id, sa.created_at, sa.updated_at
FROM sales_area sa
JOIN _map_areas ma ON ma.src = sa.id
WHERE sa.company_id = 'R7CbqHmA1j';

-- 3g. company_parameters (UUID PK, unique on company_id+facility_id+parameter_id)
INSERT INTO company_parameters (id, parameter_id, value, value_number, display_name, day_of_week,
  company_id, facility_id, created_at, updated_at)
SELECT gen_random_uuid(), cp.parameter_id, cp.value, cp.value_number, cp.display_name, cp.day_of_week,
  'demo-aloha-coffee-roasters', 'demo-kailua-roastery', cp.created_at, cp.updated_at
FROM company_parameters cp
WHERE cp.facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de'
ON CONFLICT (company_id, facility_id, parameter_id) DO UPDATE
  SET value = EXCLUDED.value, value_number = EXCLUDED.value_number;

-- 3h. coffee_inventory (origins, text PK)
INSERT INTO coffee_inventory (origin_id, origin, supplier_id, last_inventory, inventory_count_bags,
  bags_ordered, bag_size, last_cost_lb, last_shipping_cost, latest_cost, fallback_cost,
  restock_category_id, is_active, company_id, facility_id, created_at, updated_at)
SELECT mo.dst, ci.origin, ci.supplier_id, ci.last_inventory, ci.inventory_count_bags,
  ci.bags_ordered, ci.bag_size, ci.last_cost_lb, ci.last_shipping_cost, ci.latest_cost, ci.fallback_cost,
  mr.dst, ci.is_active, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', ci.created_at, ci.updated_at
FROM coffee_inventory ci
JOIN _map_origins mo ON mo.src = ci.origin_id
LEFT JOIN _map_restock mr ON mr.src = ci.restock_category_id
WHERE ci.facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de';

-- 3i. shipment_received (text PK)
INSERT INTO shipment_received (shipment_id, supplier_id, shipping_cost, date_received, order_date,
  shipment_total_weight_units, shipping_cost_unit, voided, invoice_number,
  company_id, facility_id, created_at, updated_at)
SELECT ms.dst, sr.supplier_id, sr.shipping_cost, sr.date_received, sr.order_date,
  sr.shipment_total_weight_units, sr.shipping_cost_unit, sr.voided, sr.invoice_number,
  'demo-aloha-coffee-roasters', 'demo-kailua-roastery', sr.created_at, sr.updated_at
FROM shipment_received sr
JOIN _map_shipments ms ON ms.src = sr.shipment_id
WHERE sr.facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de';

-- 3j. coffee_inventory_purchased (origin FK column is named "origin", not origin_id)
INSERT INTO coffee_inventory_purchased (origin_purchase_id, shipment_id, origin, cost_lb, amount,
  bags_ordered, bag_size, harvest_year, company_id, facility_id, created_at, updated_at)
SELECT gen_random_uuid()::text, ms.dst, mo.dst, cip.cost_lb, cip.amount,
  cip.bags_ordered, cip.bag_size, cip.harvest_year,
  'demo-aloha-coffee-roasters', 'demo-kailua-roastery', cip.created_at, cip.updated_at
FROM coffee_inventory_purchased cip
JOIN _map_shipments ms ON ms.src = cip.shipment_id
JOIN _map_origins mo ON mo.src = cip.origin
WHERE cip.facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de';

-- 3k. consumable_inventory (remap consumable_type + restock_category)
INSERT INTO consumable_inventory (consumable_inventory_id, consumable_inventory_item,
  last_inventory_date, inventory_count, last_cost_unit, fallback_unit_cost,
  consumable_type, restock_category_id, is_active, company_id, facility_id, created_at, updated_at)
SELECT mc.dst, ci.consumable_inventory_item, ci.last_inventory_date, ci.inventory_count,
  ci.last_cost_unit, ci.fallback_unit_cost,
  mct.dst, mr.dst, ci.is_active,
  'demo-aloha-coffee-roasters', 'demo-kailua-roastery', ci.created_at, ci.updated_at
FROM consumable_inventory ci
JOIN _map_consumables mc ON mc.src = ci.consumable_inventory_id
JOIN _map_ctypes mct ON mct.src = ci.consumable_type
LEFT JOIN _map_restock mr ON mr.src = ci.restock_category_id
WHERE ci.facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de';

-- 3l. roast_recipes (text PK)
INSERT INTO roast_recipes (recipe_id, recipe_name, roast_type, retention_factor, is_active,
  company_id, facility_id, created_at, updated_at)
SELECT mr.dst, rr.recipe_name, rr.roast_type, rr.retention_factor, rr.is_active,
  'demo-aloha-coffee-roasters', 'demo-kailua-roastery', rr.created_at, rr.updated_at
FROM roast_recipes rr
JOIN _map_recipes mr ON mr.src = rr.recipe_id
WHERE rr.facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de';

-- 3m. recipe_components (coffee_item and item_id both use origin IDs — remap both the same way)
INSERT INTO recipe_components (component_id, recipe_id, coffee_item, item_id, percentage,
  component_cost, company_id, facility_id, created_at, updated_at)
SELECT gen_random_uuid()::text, mr.dst, mo.dst, mo.dst, rc.percentage,
  rc.component_cost, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', rc.created_at, rc.updated_at
FROM recipe_components rc
JOIN _map_recipes mr ON mr.src = rc.recipe_id
JOIN _map_origins mo ON mo.src = rc.coffee_item
WHERE rc.facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de';

-- 3n. products (copy COGS values directly; channel is global UUID — copy as-is)
--     trg_build_product_name and trg_update_product_cogs disabled via session_replication_role = replica
INSERT INTO products (product_id, product_name, group_id, size, recipe_id, product_type, channel,
  price, weight_lbs, total_unit_cogs, total_coffee_cost, total_consumable_cost,
  gross_profit_per_unit, cogs_pct, margin_pct, last_active_unit_cogs, last_active_cogs_pct,
  last_active_gross_profit_per_unit, last_active_margin_pct, is_active,
  company_id, facility_id, created_at, updated_at)
SELECT mp.dst, p.product_name, mg.dst, ms.dst, mr.dst, mpt.dst, p.channel,
  p.price, p.weight_lbs, p.total_unit_cogs, p.total_coffee_cost, p.total_consumable_cost,
  p.gross_profit_per_unit, p.cogs_pct, p.margin_pct, p.last_active_unit_cogs, p.last_active_cogs_pct,
  p.last_active_gross_profit_per_unit, p.last_active_margin_pct, p.is_active,
  'demo-aloha-coffee-roasters', 'demo-kailua-roastery', p.created_at, p.updated_at
FROM products p
JOIN _map_products mp ON mp.src = p.product_id
JOIN _map_groups mg ON mg.src = p.group_id
JOIN _map_sizes ms ON ms.src = p.size
LEFT JOIN _map_recipes mr ON mr.src = p.recipe_id
JOIN _map_ptypes mpt ON mpt.src = p.product_type
WHERE p.facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de';

-- 3o. products_price_log
INSERT INTO products_price_log (price_log_id, product_id, price, date_updated,
  facility_id, company_id, created_at, updated_at)
SELECT gen_random_uuid()::text, mp.dst, pl.price, pl.date_updated,
  'demo-kailua-roastery', 'demo-aloha-coffee-roasters', pl.created_at, pl.updated_at
FROM products_price_log pl
JOIN _map_products mp ON mp.src = pl.product_id
WHERE pl.facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de';

-- 3p. product_consumables (remap product_id and consumable_id)
INSERT INTO product_consumables (product_consumable_id, product_id, consumable_id, quantity,
  company_id, facility_id, created_at, updated_at)
SELECT gen_random_uuid()::text, mp.dst, mc.dst, pc.quantity,
  'demo-aloha-coffee-roasters', 'demo-kailua-roastery', pc.created_at, pc.updated_at
FROM product_consumables pc
JOIN _map_products mp ON mp.src = pc.product_id
JOIN _map_consumables mc ON mc.src = pc.consumable_id
WHERE pc.facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de';

-- 3q. customers (remap sales_area FK; clear real PII — email/phone/address left NULL)
INSERT INTO customers (customer_id, name_company, sales_area, customer_category, management_type,
  acct_management_interval_wks, deal_open_closed, customer_since, is_active, flag,
  country_id, company_id, facility_id, created_at, updated_at)
SELECT mc.dst, c.name_company, ma.dst, c.customer_category, c.management_type,
  c.acct_management_interval_wks, c.deal_open_closed, c.customer_since, c.is_active, c.flag,
  c.country_id, 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', c.created_at, c.updated_at
FROM customers c
JOIN _map_customers mc ON mc.src = c.customer_id
LEFT JOIN _map_areas ma ON ma.src = c.sales_area
WHERE c.facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de';

-- 3r. orders (NULL previous_order / next_order; remap area via _map_areas since it stores sales_area.id)
INSERT INTO orders (order_id, customer_id, order_date, order_status, order_notes,
  order_total, total_weight, area, status_changed_at, company_id, facility_id, created_at, updated_at)
SELECT mo.dst, mc.dst, o.order_date, o.order_status, o.order_notes,
  o.order_total, o.total_weight, ma.dst, o.status_changed_at,
  'demo-aloha-coffee-roasters', 'demo-kailua-roastery', o.created_at, o.updated_at
FROM orders o
JOIN _map_orders mo ON mo.src = o.order_id
JOIN _map_customers mc ON mc.src = o.customer_id
LEFT JOIN _map_areas ma ON ma.src = o.area
WHERE o.facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de';

-- 3s. order_details (remap order_id, product_id, recipe_id, customer_id; NULL previous/next refs)
INSERT INTO order_details (order_detail_id, order_id, product_id, recipe_id, order_date,
  customer_id, quantity, item_status, coffee_prep, roasted_weight, total_price,
  unit_cost_at_sale, product_name_snapshot, company_id, facility_id, created_at, updated_at)
SELECT gen_random_uuid()::text, mo.dst, mp.dst, mr.dst, od.order_date,
  mc.dst, od.quantity, od.item_status, od.coffee_prep, od.roasted_weight, od.total_price,
  od.unit_cost_at_sale, od.product_name_snapshot,
  'demo-aloha-coffee-roasters', 'demo-kailua-roastery', od.created_at, od.updated_at
FROM order_details od
JOIN _map_orders mo ON mo.src = od.order_id
LEFT JOIN _map_products mp ON mp.src = od.product_id
LEFT JOIN _map_recipes mr ON mr.src = od.recipe_id
LEFT JOIN _map_customers mc ON mc.src = od.customer_id
WHERE od.facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de';

-- 3t. roast_log (remap origin_id + recipe_id + charge_weight UUID; set roaster_unit_id → demo Probat P25)
INSERT INTO roast_log (roast_log_id, roast_date, roast_date_utc, origin_id, recipe_id,
  charge_weight, charge_weight_lbs, roasted_weight, "charged?", "chaff_cleaned?",
  roast_type, recipe_name_snapshot, coffee_name_snapshot, sort_order,
  roaster_unit_id, company_id, facility_id, created_at, updated_at)
SELECT gen_random_uuid()::text, rl.roast_date, rl.roast_date_utc, mo.dst, mr.dst,
  COALESCE(mcw.dst::text, rl.charge_weight), rl.charge_weight_lbs,
  rl.roasted_weight, rl."charged?", rl."chaff_cleaned?",
  rl.roast_type, rl.recipe_name_snapshot, rl.coffee_name_snapshot, rl.sort_order,
  'a0a0a0a0-0001-4000-8000-000000000001',
  'demo-aloha-coffee-roasters', 'demo-kailua-roastery', rl.created_at, rl.updated_at
FROM roast_log rl
LEFT JOIN _map_origins mo ON mo.src = rl.origin_id
LEFT JOIN _map_recipes mr ON mr.src = rl.recipe_id
LEFT JOIN _map_charge_weights mcw ON mcw.src::text = rl.charge_weight
WHERE rl.facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de';

-- 3u. weekly_roast_snapshot (no IDs to remap)
INSERT INTO weekly_roast_snapshot (snapshot_id, week_start, total_roasted, total_roasted_green,
  total_ordered_roasted, total_ordered_green, order_count, products_sold, roast_count,
  roasting_hours, capacity_pct, batches_since_chaff, snapshotted_at, facility_id, company_id, created_at)
SELECT gen_random_uuid(), week_start, total_roasted, total_roasted_green,
  total_ordered_roasted, total_ordered_green, order_count, products_sold, roast_count,
  roasting_hours, capacity_pct, batches_since_chaff, snapshotted_at,
  'demo-kailua-roastery', 'demo-aloha-coffee-roasters', created_at
FROM weekly_roast_snapshot
WHERE facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de';

SET session_replication_role = DEFAULT;

-- ============================================================
-- PHASE 4: RENAME EVERYTHING
-- ============================================================

-- 4a. Company and facility names
UPDATE companies SET company_name = 'Strata Coffee Roasters'
  WHERE company_id = 'demo-aloha-coffee-roasters';
UPDATE facilities SET facility_name = 'Portland Roastery'
  WHERE facility_id = 'demo-kailua-roastery';
UPDATE team SET name = 'Alex Rivera'
  WHERE team_member_id = 'demo-team-admin';

-- 4b. Product groups (54 groups)
UPDATE product_groups SET group_name = CASE group_name
  WHEN 'Dawn Patrol'           THEN 'Morning Watch'
  WHEN 'Kona Blend'            THEN 'Mountain Blend'
  WHEN 'Kona Extra Fancy'      THEN 'Reserve Single Origin'
  WHEN 'Kona Melody'           THEN 'Harmony'
  WHEN 'Maui Sunrise'          THEN 'Summit Sunrise'
  WHEN 'Mahi Pono'             THEN 'True North'
  WHEN 'Pohaku'                THEN 'Bedrock'
  WHEN 'Hon Solo'              THEN 'Lone Star Espresso'
  WHEN 'Hotel Wailea'          THEN 'Grand Hotel Blend'
  WHEN 'Kea Lani'              THEN 'Terrace Blend'
  WHEN 'Kea Lani Espresso'     THEN 'Terrace Espresso'
  WHEN 'Kea Lani House'        THEN 'Terrace House'
  WHEN 'NOLA'                  THEN 'French Quarter'
  WHEN 'Mokka Peaberry'        THEN 'Heirloom Peaberry'
  WHEN 'Mokka Reserve'         THEN 'Reserve Collection'
  WHEN 'Olili Espresso'        THEN 'Nightshade Espresso'
  WHEN 'Olili House'           THEN 'Nightshade House'
  WHEN 'Olinda Blend'          THEN 'Hillside Blend'
  WHEN 'Piko Espresso'         THEN 'Centerpoint Espresso'
  WHEN 'Piko Espresso (Vinyl)' THEN 'Centerpoint Vinyl'
  WHEN 'Piko House'            THEN 'Centerpoint House'
  WHEN 'Papi''s Ohana'         THEN 'Familia Blend'
  WHEN 'B-Side Espresso'       THEN 'Backbeat Espresso'
  WHEN 'B-Side House'          THEN 'Backbeat House'
  WHEN 'Et Al'                 THEN 'Common Thread'
  WHEN 'Golden Hour'           THEN 'Dusk'
  WHEN 'Dear Wanderlust'       THEN 'Waypoint'
  WHEN 'Better Things'         THEN 'Forward Motion'
  WHEN 'Bottom of the Barrel'  THEN 'Deep Cut'
  WHEN 'Beardy Brew'           THEN 'Watershed'
  WHEN 'Beardy Brew (Vinyl)'   THEN 'Watershed Vinyl'
  WHEN 'Momona Bakery'         THEN 'Artisan Bakery Blend'
  WHEN 'Redfish Espresso'      THEN 'Ironwood Espresso'
  WHEN 'Redfish House'         THEN 'Ironwood House'
  WHEN 'Sunset Decaf'          THEN 'Evening Decaf'
  WHEN 'Java Cafe'             THEN 'Java Café Blend'
  WHEN 'Ax Ranch'              THEN 'Ridgeline'
  WHEN 'Casa Nova'             THEN 'Hearthstone'
  WHEN 'Christmas Spirit'      THEN 'Winter Reserve'
  WHEN 'Drew Method Honduras'  THEN 'Single Origin Honduras'
  WHEN 'Drew Method Mindful'   THEN 'Mindful Blend'
  WHEN 'Red Origin'            THEN 'Ridge Red'
  WHEN 'Trotter''s Koffie'     THEN 'Trotter''s Brew'
  ELSE group_name
END
WHERE company_id = 'demo-aloha-coffee-roasters';

-- 4c. Roast recipes (29 recipes)
UPDATE roast_recipes SET recipe_name = CASE recipe_name
  WHEN 'Bottom Of The Barrel'         THEN 'Deep Cut'
  WHEN 'Christmas Spirit Aged'        THEN 'Winter Reserve Aged'
  WHEN 'Dear Wanderlust Retail Blend' THEN 'Waypoint Retail'
  WHEN 'Decaf'                        THEN 'Evening Decaf'
  WHEN 'Et Al'                        THEN 'Common Thread'
  WHEN 'Golden Hour'                  THEN 'Dusk'
  WHEN 'Hon Solo'                     THEN 'Lone Star Espresso'
  WHEN 'Kona Blend'                   THEN 'Mountain Blend'
  WHEN 'Kona Extra Fancy'             THEN 'Reserve Single Origin'
  WHEN 'Kona Melody'                  THEN 'Harmony'
  WHEN 'Mahi Pono'                    THEN 'True North'
  WHEN 'Maui Hendrix'                 THEN 'Hendrix Reserve'
  WHEN 'Maui Nova'                    THEN 'Nova Reserve'
  WHEN 'Maui Nova Brazil'             THEN 'Nova Brazil Reserve'
  WHEN 'Maui Red'                     THEN 'Ridge Red'
  WHEN 'Maui Red Origin'              THEN 'Ridge Red Origin'
  WHEN 'Maui Sunrise'                 THEN 'Summit Sunrise'
  WHEN 'Mokka Peaberry'               THEN 'Heirloom Peaberry'
  WHEN 'Mokka Reserve'                THEN 'Reserve Collection'
  WHEN 'Pohaku'                       THEN 'Bedrock'
  WHEN 'Pohaku Maui'                  THEN 'Bedrock Reserve'
  WHEN 'NOLA'                         THEN 'French Quarter'
  ELSE recipe_name
END
WHERE facility_id = 'demo-kailua-roastery';

-- 4d. Update roast_log.recipe_name_snapshot to strip obvious Hawaii references
UPDATE roast_log SET
  recipe_name_snapshot = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
    recipe_name_snapshot,
    'Maui ', ''), 'Kona ', 'Mountain '), 'Pohaku', 'Bedrock'), 'Mahi Pono', 'True North'), 'Hon Solo', 'Lone Star Espresso'),
  coffee_name_snapshot = REPLACE(REPLACE(coffee_name_snapshot, 'Maui', 'Summit'), 'Kona', 'Mountain')
WHERE facility_id = 'demo-kailua-roastery';

-- 4e. Sales areas (28 areas — area_name column)
UPDATE sales_area SET area_name = CASE area_name
  WHEN 'Honolulu'          THEN 'Downtown'
  WHEN 'Kailua'            THEN 'East Side'
  WHEN 'Kakaako'           THEN 'Arts District'
  WHEN 'Kaimuki'           THEN 'Highland Park'
  WHEN 'Manoa'             THEN 'University District'
  WHEN 'Hawaii Wide'       THEN 'Regional'
  WHEN 'Maui Wide'         THEN 'South Regional'
  WHEN 'Haleiwa'           THEN 'North Side'
  WHEN 'Waikiki'           THEN 'Tourist District'
  WHEN 'Kaanapali/Kapalua' THEN 'Uptown'
  WHEN 'Kahului/Wailuku'   THEN 'Midtown'
  WHEN 'Kihei/Wailea'      THEN 'Resort District'
  WHEN 'Ko''olina'         THEN 'Marina District'
  WHEN 'Kona'              THEN 'Mountain District'
  WHEN 'Lahaina'           THEN 'Old Town'
  WHEN 'Lanai'             THEN 'Island Outpost'
  WHEN 'Aiea'              THEN 'Northeast District'
  WHEN 'Chinatown'         THEN 'Historic District'
  WHEN 'Ewa beach'         THEN 'Westside'
  WHEN 'Hawaii Kai'        THEN 'East Bay'
  WHEN 'Kapolei'           THEN 'West End'
  WHEN 'Mililani'          THEN 'Suburban North'
  WHEN 'Moanalua'          THEN 'Valley District'
  WHEN 'Molokai'           THEN 'Remote'
  WHEN 'Wailuku'           THEN 'Market District'
  WHEN 'Waimanalo'         THEN 'Coastal'
  WHEN 'Waimea'            THEN 'Canyon District'
  WHEN 'Windward'          THEN 'Eastward'
  ELSE area_name
END
WHERE company_id = 'demo-aloha-coffee-roasters';

-- 4f. Consumable items (64 items)
UPDATE consumable_inventory SET consumable_inventory_item = CASE consumable_inventory_item
  WHEN 'Alii Nui Label'             THEN 'Grand Hotel Label'
  WHEN 'Ax Ranch'                   THEN 'Ridgeline Label'
  WHEN 'B-Side Espresso Label'      THEN 'Backbeat Espresso Label'
  WHEN 'B-Side House'               THEN 'Backbeat House Label'
  WHEN 'Blank Golden Hour Labels'   THEN 'Blank Dusk Labels'
  WHEN 'Bready Brew Label'          THEN 'Watershed Label'
  WHEN 'Christmas Spirit Label'     THEN 'Winter Reserve Label'
  WHEN 'Dawn Patrol Label'          THEN 'Morning Watch Label'
  WHEN 'Dear Wanderlust Label'      THEN 'Waypoint Label'
  WHEN 'Drew Method Honduras'       THEN 'Single Origin Honduras Label'
  WHEN 'Drew Method Mindful Label'  THEN 'Mindful Blend Label'
  WHEN 'Gold Hour Old Label'        THEN 'Dusk Classic Label'
  WHEN 'Hon Solo 8oz Barcode'       THEN 'Lone Star Espresso 8oz Barcode'
  WHEN 'Hon Solo Barcode'           THEN 'Lone Star Espresso Barcode'
  WHEN 'Hon Solo Label'             THEN 'Lone Star Espresso Label'
  WHEN 'Hotel Wailea Label'         THEN 'Grand Hotel Label'
  WHEN 'Java Cafe Labels'           THEN 'Java Café Labels'
  WHEN 'Kea Lani Label'             THEN 'Terrace Label'
  WHEN 'Kona Blend'                 THEN 'Mountain Blend Label'
  WHEN 'Kona Extra Fancy'           THEN 'Reserve Single Origin Label'
  WHEN 'Kona Melody'                THEN 'Harmony Label'
  WHEN 'Mahi Pono'                  THEN 'True North Label'
  WHEN 'Maui Cigar Label'           THEN 'Reserve Cigar Box Label'
  WHEN 'Maui Fire Department'       THEN 'Annual Benefit Box'
  WHEN 'Maui Sunrise Label'         THEN 'Summit Sunrise Label'
  WHEN 'Mokka Old Label'            THEN 'Heirloom Classic Label'
  WHEN 'Mokka Peaberry Label'       THEN 'Heirloom Peaberry Label'
  WHEN 'Mokka Reserve Label'        THEN 'Reserve Collection Label'
  WHEN 'Momona Label'               THEN 'Artisan Bakery Label'
  WHEN 'Olili Label'                THEN 'Nightshade Label'
  WHEN 'Pacfiic Whale'              THEN 'Wildlife Fund Box'
  WHEN 'Papi''s Ohana Label'        THEN 'Familia Label'
  WHEN 'Piko House Blend Label'     THEN 'Centerpoint House Label'
  WHEN 'Pohaku'                     THEN 'Bedrock Label'
  WHEN 'Pohaku Label'               THEN 'Bedrock Label'
  WHEN 'Red Origin Label'           THEN 'Ridge Red Label'
  WHEN 'Sol Do Brasil (Jesus)'      THEN 'Sol Do Brasil Reserve Label'
  WHEN 'SunLit Films Label'         THEN 'Prism Films Label'
  WHEN 'Sunset Decaf'               THEN 'Evening Decaf Label'
  WHEN 'Trotters Koffie'            THEN 'Trotter''s Brew Label'
  WHEN 'Vigilatte New Label'        THEN 'Vigilatte Label'
  WHEN 'Viglilatte Old Style Label' THEN 'Vigilatte Classic Label'
  ELSE consumable_inventory_item
END
WHERE facility_id = 'demo-kailua-roastery';

-- 4g. Rebuild product_name via trg_build_product_name (now outside replica mode, trigger fires normally)
UPDATE products SET group_id = group_id WHERE facility_id = 'demo-kailua-roastery';

-- 4h. Customers (818 customers — programmatic rename via DO block)
DO $$
DECLARE
  biz_names TEXT[] := ARRAY[
    'Threshold Coffee Co','Compass Coffee','Slate & Grind','Onyx Supply Co',
    'Verve Coffee','Toby''s Estate','Blue Bottle Café','Intelligentsia Coffee',
    'Stumptown Coffee Bar','La Colombe Café','Sightglass Coffee','Ritual Coffee',
    'Equator Coffees','Bird Rock Coffee','Coava Coffee','Heart Coffee Roasters',
    'Water Avenue Coffee','Roseline Coffee','Nossa Familia Coffee','Guilder Café',
    'Sterling Coffee Co','Good Coffee','Deadstock Coffee','Push X Pull Coffee',
    'Never Coffee','Either/Or Coffee','Proud Mary','Case Study Coffee',
    'Extracto Coffee','Coffee House Northwest','Courier Coffee','Cellar Door Coffee',
    'Olympia Coffee','Tony''s Coffee','Lighthouse Roasters','Broadcast Coffee',
    'Hothouse Coffee','Analog Coffee','Elm Coffee Roasters','Fulcrum Coffee',
    'Herkimer Coffee','Victrola Coffee','Caffe Vita','Espresso Vivace',
    'Zoka Coffee','Seattle Coffee Works','Capitol Hill Coffee','Anchorhead Coffee',
    'Ada''s Technical Books','Bedlam Coffee','Elm Street Coffee','Bar Del Corso',
    'Preserve & Gather','Communion Restaurant','Gabi & Jules','Lighthouse Boulangerie',
    'Seven Coffee Roasters','Upper Left Roasters','Public Domain Coffee','Spella Caffè',
    'Barista Coffee','Water Avenue Café','Cathedral Coffee','Fresh Pot Coffee',
    'Never Coffee Lab','Heart Espresso Bar','Quaintrelle','Ava Gene''s',
    'Roman Candle Bakery','Little T Baker','Grand Central Bakery','Tabor Bread',
    'Ken''s Artisan Bakery','Nuvrei Bakery','City State Coffee','Cerimon House',
    'Nostrana Restaurant','Tasty n Daughters','Tusk Restaurant','Luce Restaurant',
    'Ox Restaurant','Canard Wine Bar','Han Oak','Imperial Restaurant',
    'Headwaters Bar','Jackrabbit Restaurant','Mother''s Bistro','Pix Patisserie',
    'Pinolo Gelato','Pepe Le Moko','Clyde Common','The Rambler Bar',
    'Loyal Legion','Ecliptic Brewing','Stormbreaker Brewing','Breakside Brewery',
    'pFriem Family Brewers','Crux Fermentation','Boneyard Beer','Deschutes Brewery',
    'Ninkasi Brewing','Oakshire Brewing','Falling Sky Brewing','McMenamins',
    'Hop Valley Brewing','Alpine Trail Roasters','Summit Coffee Supply','Ridge Coffee Co',
    'Canyon Brew Co','Ironwood Coffee','Backwood Roasters','Watershed Coffee Co',
    'Common Thread Café','Forward Motion Café','Morning Watch Coffee','Waypoint Coffee',
    'Dusk Coffee Bar','Deep Cut Coffee','Hearthstone Café','Ridgeline Coffee',
    'Hillside Coffee','Bedrock Coffee','True North Coffee','Harmony Coffee Co',
    'French Quarter Coffee','Evening Decaf Bar','Artisan Bakery & Coffee','Java Café Supply',
    'Centerpoint Coffee','Nightshade Espresso','Familia Coffee','Vinyl Coffee Co',
    'Trotter''s Brew','Vida Coffee','Rubix Coffee','Nova Coffee Bar',
    'Sol Café','Crema Coffee Bar','Cold Brew Station','Ironwood Supply',
    'Backbeat Coffee','Watershed Supply Co','Common Ground Café','Blue Ridge Coffee',
    'Summit Roasting Co','Pacific Crest Coffee','Highline Coffee','Mesa Coffee Co',
    'Cascade Roasters','Ridgeback Coffee','Thornwood Coffee','Sterling Grounds',
    'Irongate Coffee','Fieldwork Coffee','Northfield Coffee','Grindstone Coffee'
  ];
  first_names TEXT[] := ARRAY[
    'James','John','Robert','Michael','William','David','Richard','Joseph','Thomas','Charles',
    'Christopher','Daniel','Matthew','Anthony','Mark','Donald','Steven','Paul','Andrew','Joshua',
    'Kenneth','Kevin','Brian','George','Timothy','Ronald','Edward','Jason','Jeffrey','Ryan',
    'Jacob','Gary','Nicholas','Eric','Jonathan','Stephen','Larry','Justin','Scott','Brandon',
    'Benjamin','Samuel','Raymond','Gregory','Frank','Alexander','Patrick','Jack','Dennis','Jerry',
    'Mary','Patricia','Jennifer','Linda','Barbara','Elizabeth','Susan','Jessica','Sarah','Karen',
    'Lisa','Nancy','Betty','Margaret','Sandra','Ashley','Dorothy','Kimberly','Emily','Donna',
    'Michelle','Carol','Amanda','Melissa','Deborah','Stephanie','Rebecca','Sharon','Laura','Cynthia',
    'Kathleen','Amy','Angela','Shirley','Anna','Brenda','Pamela','Emma','Nicole','Helen',
    'Samantha','Katherine','Christine','Debra','Rachel','Carolyn','Janet','Catherine','Maria','Heather'
  ];
  last_names TEXT[] := ARRAY[
    'Smith','Johnson','Williams','Brown','Jones','Garcia','Miller','Davis','Wilson','Anderson',
    'Taylor','Thomas','Hernandez','Moore','Martin','Jackson','Thompson','White','Lopez','Lee',
    'Gonzalez','Harris','Clark','Lewis','Robinson','Walker','Perez','Hall','Young','Allen',
    'Sanchez','Wright','King','Scott','Green','Baker','Adams','Nelson','Hill','Ramirez',
    'Campbell','Mitchell','Roberts','Carter','Phillips','Evans','Turner','Torres','Parker','Collins',
    'Edwards','Stewart','Flores','Morris','Nguyen','Murphy','Rivera','Cook','Rogers','Morgan',
    'Peterson','Cooper','Reed','Bailey','Bell','Gomez','Kelly','Howard','Ward','Cox',
    'Diaz','Richardson','Wood','Watson','Brooks','Bennett','Gray','James','Reyes','Cruz',
    'Hughes','Price','Myers','Long','Foster','Sanders','Ross','Morales','Powell','Sullivan',
    'Russell','Ortiz','Jenkins','Gutierrez','Perry','Butler','Barnes','Fisher','Henderson','Coleman'
  ];
  biz_keywords TEXT[] := ARRAY[
    'restaurant','café','cafe','coffee','bar','bakery','hotel','resort','store','kitchen',
    'brewing','brewery','market','supply','co','llc','inc','bistro','roaster',
    'eatery','lounge','house','grill','shop','deli','patisserie','boulangerie',
    'alii','nui','aloha','beach','abc stores','acacia','alive','9bar','papi'
  ];
  rec RECORD;
  biz_count INT := 0;
  ind_count INT := 0;
  name_lower TEXT;
  is_biz BOOLEAN;
  kw TEXT;
BEGIN
  FOR rec IN SELECT customer_id, name_company FROM customers
    WHERE facility_id = 'demo-kailua-roastery' ORDER BY customer_id
  LOOP
    name_lower := lower(COALESCE(rec.name_company, ''));
    is_biz := FALSE;
    FOREACH kw IN ARRAY biz_keywords LOOP
      IF name_lower LIKE '%' || kw || '%' THEN is_biz := TRUE; EXIT; END IF;
    END LOOP;
    IF is_biz THEN
      biz_count := biz_count + 1;
      UPDATE customers
        SET name_company = biz_names[((biz_count - 1) % array_length(biz_names, 1)) + 1]
        WHERE customer_id = rec.customer_id;
    ELSE
      ind_count := ind_count + 1;
      UPDATE customers
        SET name_company =
          first_names[((ind_count - 1) % array_length(first_names, 1)) + 1] || ' ' ||
          last_names[((ind_count - 1) % array_length(last_names, 1)) + 1]
        WHERE customer_id = rec.customer_id;
    END IF;
  END LOOP;
END $$;

-- ============================================================
-- PHASE 5: REFRESH MATERIALIZED VIEWS
-- ============================================================
REFRESH MATERIALIZED VIEW weekly_coffee_stock_by_origin;
REFRESH MATERIALIZED VIEW order_graphs_week;
