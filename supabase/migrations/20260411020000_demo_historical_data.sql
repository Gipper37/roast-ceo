-- ============================================================
-- DEMO: Historical data expansion
-- • Fix Q2 2026 April coffee shipment (add more origins)
-- • Add 5 mainland third-wave customers
-- • Add 2 new product groups + products + BOMs + prices
-- • 5 historical coffee shipments (Q2–Q4 2025) for cost variance
-- • Historical roast logs (Apr–Dec 2025)
-- • Historical orders (Apr–Dec 2025, low → high volume)
-- ============================================================

SET session_replication_role = 'replica';

-- ── 1. FIX Q2 2026 APRIL SHIPMENT ────────────────────────────────────────────
-- demo-ship-007 (received 2026-04-02) only had 3 origins. Add the rest.

INSERT INTO coffee_inventory_purchased
  (origin_purchase_id, shipment_id, origin, bags_ordered, cost_lb, amount, bag_size, facility_id, company_id, created_at)
VALUES
  (gen_random_uuid()::text, 'demo-ship-007', 'demo-org-brazil',   8, 3.88, 1232, '154', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-007', 'demo-org-colombia',  8, 4.28, 1232, '154', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-007', 'demo-org-guate',     5, 4.52,  770, '154', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-007', 'demo-org-sumatra',   8, 4.12, 1232, '154', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-007', 'demo-org-kona',      3, 29.50, 300, '100', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-007', 'demo-org-mexico',    5, 3.42,  770, '154', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-007', 'demo-org-costa',     3, 4.78,  462, '154', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-007', 'demo-org-peru',      3, 3.62,  462, '154', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW());

-- ── 2. NEW MAINLAND CUSTOMERS ─────────────────────────────────────────────────

INSERT INTO customers
  (customer_id, name_company, sales_area, customer_since, is_active, company_id, created_at)
VALUES
  ('demo-cust-031', 'Paper Crane Coffee',      'Mainland',  '2025-06-15', true, 'demo-aloha-coffee-roasters', NOW()),
  ('demo-cust-032', 'Counterweight Roasters',  'Mainland',  '2025-07-22', true, 'demo-aloha-coffee-roasters', NOW()),
  ('demo-cust-033', 'Onyx Supply Co.',          'Mainland',  '2025-09-04', true, 'demo-aloha-coffee-roasters', NOW()),
  ('demo-cust-034', 'Ritual Grounds SF',        'Mainland',  '2025-10-11', true, 'demo-aloha-coffee-roasters', NOW()),
  ('demo-cust-035', 'Harbinger Coffee',         'Mainland',  '2025-11-03', true, 'demo-aloha-coffee-roasters', NOW());

-- ── 3. NEW PRODUCT GROUPS ─────────────────────────────────────────────────────

INSERT INTO product_groups (group_id, group_name, facility_id, company_id, created_at)
VALUES
  ('00000000-0000-0000-0000-de0000000005', 'Ethiopia Yirgacheffe', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  ('00000000-0000-0000-0000-de0000000006', 'Tradewind Medium',     'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW());

-- ── 3a. New products (trigger builds product_name from group+size+channel) ───

INSERT INTO products
  (product_id, group_id, size, channel, recipe_id, product_type, weight_lbs, is_active, facility_id, company_id, created_at)
VALUES
  -- Ethiopia Yirgacheffe
  ('demo-prod-026', '00000000-0000-0000-0000-de0000000005', 'demo-size-12oz', '6e6f4b92-8d17-4858-913a-b38b85b178a6', 'demo-rcp-single-ethiopia', '734e6537-0a0b-4248-8720-56768d4e9234', 0.75, true, 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  ('demo-prod-027', '00000000-0000-0000-0000-de0000000005', 'demo-size-12oz', '87f69426-eb0f-4b67-a160-62c8be988323', 'demo-rcp-single-ethiopia', 'd3463359-eb50-4277-acaa-bedadd4dc211', 0.75, true, 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  ('demo-prod-028', '00000000-0000-0000-0000-de0000000005', 'demo-size-1lb',  '6e6f4b92-8d17-4858-913a-b38b85b178a6', 'demo-rcp-single-ethiopia', '734e6537-0a0b-4248-8720-56768d4e9234', 1.0,  true, 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  -- Tradewind Medium
  ('demo-prod-029', '00000000-0000-0000-0000-de0000000006', 'demo-size-12oz', '6e6f4b92-8d17-4858-913a-b38b85b178a6', 'demo-rcp-tradewind', '734e6537-0a0b-4248-8720-56768d4e9234', 0.75, true, 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  ('demo-prod-030', '00000000-0000-0000-0000-de0000000006', 'demo-size-12oz', '87f69426-eb0f-4b67-a160-62c8be988323', 'demo-rcp-tradewind', 'd3463359-eb50-4277-acaa-bedadd4dc211', 0.75, true, 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW());

-- ── 3b. Price logs for new products ──────────────────────────────────────────

INSERT INTO products_price_log (price_log_id, product_id, price, date_updated, company_id, facility_id, created_at)
VALUES
  (gen_random_uuid()::text, 'demo-prod-026', 24.99, '2025-07-01', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', NOW()),
  (gen_random_uuid()::text, 'demo-prod-027', 30.00, '2025-07-01', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', NOW()),
  (gen_random_uuid()::text, 'demo-prod-028', 44.99, '2025-07-01', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', NOW()),
  (gen_random_uuid()::text, 'demo-prod-029', 15.99, '2025-09-01', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', NOW()),
  (gen_random_uuid()::text, 'demo-prod-030', 19.99, '2025-09-01', 'demo-aloha-coffee-roasters', 'demo-kailua-roastery', NOW());

-- Sync price to products.price (trigger bypassed, do manually)
UPDATE products SET price = 24.99 WHERE product_id = 'demo-prod-026';
UPDATE products SET price = 30.00 WHERE product_id = 'demo-prod-027';
UPDATE products SET price = 44.99 WHERE product_id = 'demo-prod-028';
UPDATE products SET price = 15.99 WHERE product_id = 'demo-prod-029';
UPDATE products SET price = 19.99 WHERE product_id = 'demo-prod-030';

-- ── 3c. BOMs for new products ─────────────────────────────────────────────────
-- Using same consumables as existing 12oz and 1lb products

INSERT INTO product_consumables (product_consumable_id, product_id, consumable_id, quantity, company_id, facility_id, created_at)
SELECT gen_random_uuid()::text, np.product_id, pc.consumable_id, pc.quantity,
       'demo-aloha-coffee-roasters', 'demo-kailua-roastery', NOW()
FROM (VALUES
  ('demo-prod-026'), ('demo-prod-027'), ('demo-prod-029'), ('demo-prod-030')
) AS np(product_id)
CROSS JOIN (
  SELECT consumable_id, quantity FROM product_consumables WHERE product_id = 'demo-prod-012' LIMIT 10
) pc;

INSERT INTO product_consumables (product_consumable_id, product_id, consumable_id, quantity, company_id, facility_id, created_at)
SELECT gen_random_uuid()::text, 'demo-prod-028', pc.consumable_id, pc.quantity,
       'demo-aloha-coffee-roasters', 'demo-kailua-roastery', NOW()
FROM (
  SELECT consumable_id, quantity FROM product_consumables WHERE product_id = 'demo-prod-017' LIMIT 10
) pc;

-- ── 4. HISTORICAL COFFEE SHIPMENTS ──────────────────────────────────────────

-- Q2 2025 (April)
INSERT INTO shipment_received (shipment_id, supplier_id, order_date, date_received, shipping_cost_unit, facility_id, company_id, created_at)
VALUES ('demo-ship-hist-01', 'demo-sup-001', '2025-04-01', '2025-04-14', 0.08, 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW());

INSERT INTO coffee_inventory_purchased (origin_purchase_id, shipment_id, origin, bags_ordered, cost_lb, amount, bag_size, facility_id, company_id, created_at)
VALUES
  (gen_random_uuid()::text, 'demo-ship-hist-01', 'demo-org-brazil',   6, 3.75,  924, '154', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-hist-01', 'demo-org-colombia',  6, 4.10,  924, '154', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-hist-01', 'demo-org-ethiopia',  3, 5.80,  396, '132', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-hist-01', 'demo-org-decaf-co',  2, 5.85,  308, '154', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-hist-01', 'demo-org-kona',      3, 27.50, 300, '100', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW());

-- Q3 2025 (July)
INSERT INTO shipment_received (shipment_id, supplier_id, order_date, date_received, shipping_cost_unit, facility_id, company_id, created_at)
VALUES ('demo-ship-hist-02', 'demo-sup-001', '2025-07-01', '2025-07-14', 0.08, 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW());

INSERT INTO coffee_inventory_purchased (origin_purchase_id, shipment_id, origin, bags_ordered, cost_lb, amount, bag_size, facility_id, company_id, created_at)
VALUES
  (gen_random_uuid()::text, 'demo-ship-hist-02', 'demo-org-brazil',   8, 3.80, 1232, '154', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-hist-02', 'demo-org-colombia',  8, 4.15, 1232, '154', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-hist-02', 'demo-org-ethiopia',  4, 5.90,  528, '132', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-hist-02', 'demo-org-guate',     3, 4.35,  462, '154', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-hist-02', 'demo-org-sumatra',   6, 3.95,  924, '154', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-hist-02', 'demo-org-decaf-co',  3, 5.90,  462, '154', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-hist-02', 'demo-org-kona',      4, 28.00, 400, '100', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW());

-- Q3 2025 (September)
INSERT INTO shipment_received (shipment_id, supplier_id, order_date, date_received, shipping_cost_unit, facility_id, company_id, created_at)
VALUES ('demo-ship-hist-03', 'demo-sup-004', '2025-09-02', '2025-09-15', 0.09, 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW());

INSERT INTO coffee_inventory_purchased (origin_purchase_id, shipment_id, origin, bags_ordered, cost_lb, amount, bag_size, facility_id, company_id, created_at)
VALUES
  (gen_random_uuid()::text, 'demo-ship-hist-03', 'demo-org-brazil',   8, 3.82, 1232, '154', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-hist-03', 'demo-org-colombia',  8, 4.20, 1232, '154', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-hist-03', 'demo-org-ethiopia',  4, 5.95,  528, '132', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-hist-03', 'demo-org-kenya',     3, 6.30,  396, '132', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-hist-03', 'demo-org-guate',     4, 4.40,  616, '154', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-hist-03', 'demo-org-kona',      5, 28.50, 500, '100', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW());

-- Q4 2025 (October)
INSERT INTO shipment_received (shipment_id, supplier_id, order_date, date_received, shipping_cost_unit, facility_id, company_id, created_at)
VALUES ('demo-ship-hist-04', 'demo-sup-001', '2025-10-01', '2025-10-13', 0.08, 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW());

INSERT INTO coffee_inventory_purchased (origin_purchase_id, shipment_id, origin, bags_ordered, cost_lb, amount, bag_size, facility_id, company_id, created_at)
VALUES
  (gen_random_uuid()::text, 'demo-ship-hist-04', 'demo-org-brazil',   10, 3.85, 1540, '154', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-hist-04', 'demo-org-colombia', 10, 4.20, 1540, '154', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-hist-04', 'demo-org-ethiopia',  5, 5.95,  660, '132', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-hist-04', 'demo-org-guate',     5, 4.42,  770, '154', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-hist-04', 'demo-org-sumatra',   8, 3.98, 1232, '154', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-hist-04', 'demo-org-mexico',    5, 3.30,  770, '154', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-hist-04', 'demo-org-kenya',     3, 6.35,  396, '132', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-hist-04', 'demo-org-decaf-co',  3, 4.95,  462, '154', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-hist-04', 'demo-org-kona',      6, 28.80, 600, '100', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW());

-- Q4 2025 (December)
INSERT INTO shipment_received (shipment_id, supplier_id, order_date, date_received, shipping_cost_unit, facility_id, company_id, created_at)
VALUES ('demo-ship-hist-05', 'demo-sup-001', '2025-11-28', '2025-12-10', 0.08, 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW());

INSERT INTO coffee_inventory_purchased (origin_purchase_id, shipment_id, origin, bags_ordered, cost_lb, amount, bag_size, facility_id, company_id, created_at)
VALUES
  (gen_random_uuid()::text, 'demo-ship-hist-05', 'demo-org-brazil',   10, 3.83, 1540, '154', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-hist-05', 'demo-org-colombia', 10, 4.22, 1540, '154', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-hist-05', 'demo-org-ethiopia',  6, 5.92,  792, '132', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-hist-05', 'demo-org-guate',     5, 4.45,  770, '154', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-hist-05', 'demo-org-sumatra',  10, 4.00, 1540, '154', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-hist-05', 'demo-org-mexico',    5, 3.35,  770, '154', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-hist-05', 'demo-org-costa',     4, 4.70,  616, '154', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-hist-05', 'demo-org-rwanda',    3, 5.25,  396, '132', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-hist-05', 'demo-org-decaf-co',  3, 4.97,  462, '154', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW()),
  (gen_random_uuid()::text, 'demo-ship-hist-05', 'demo-org-kona',      7, 29.00, 700, '100', 'demo-kailua-roastery', 'demo-aloha-coffee-roasters', NOW());

-- ── 5. HISTORICAL ROAST LOGS (Apr–Dec 2025) ──────────────────────────────────
-- Probat P25 (unit a0a0a0a0-0001-4000-8000-000000000001)
-- Charge weights: demo-cw-25 = 25 lbs, demo-cw-15 = 15 lbs
-- Roasted weight ≈ charge × 0.82 (retention)

DO $$
DECLARE
  v_roaster UUID := 'a0a0a0a0-0001-4000-8000-000000000001';
  v_fac TEXT := 'demo-kailua-roastery';
  v_co  TEXT := 'demo-aloha-coffee-roasters';

  -- month_data: month_start, n_house, n_kona, n_espresso, n_decaf, n_ethiopia
  months RECORD;
BEGIN
  FOR months IN (
    SELECT * FROM (VALUES
      --  month_start       house kona espr decaf eth
      ('2025-04-05'::date,   4,   2,   1,    0,   0),
      ('2025-05-05'::date,   5,   3,   1,    1,   0),
      ('2025-06-06'::date,   6,   3,   1,    1,   0),
      ('2025-07-07'::date,   8,   4,   2,    1,   0),
      ('2025-08-04'::date,  10,   5,   2,    1,   1),
      ('2025-09-03'::date,  12,   5,   2,    1,   1),
      ('2025-10-06'::date,  14,   6,   3,    2,   2),
      ('2025-11-03'::date,  16,   7,   3,    2,   2),
      ('2025-12-01'::date,  20,   8,   4,    2,   2)
    ) AS t(month_start, n_house, n_kona, n_espresso, n_decaf, n_ethiopia)
  ) LOOP
    -- Aloha House Blend batches
    FOR i IN 1..months.n_house LOOP
      INSERT INTO roast_log
        (roast_log_id, roast_date, recipe_id, charge_weight, charge_weight_lbs,
         roasted_weight, "charged?", roast_type, roaster_unit_id, facility_id, company_id,
         recipe_name_snapshot, created_at)
      VALUES (
        gen_random_uuid()::text,
        months.month_start + ((i-1) * 2) * INTERVAL '1 day' + INTERVAL '8 hours',
        'demo-rcp-aloha-house', 'demo-cw-25', 25,
        25 * 0.82 + (random() * 0.6 - 0.3),
        true, 'Pre-Blend', v_roaster, v_fac, v_co,
        'Aloha House Blend', NOW()
      );
    END LOOP;

    -- Kona Sunrise batches (single origin, 15 lbs)
    FOR i IN 1..months.n_kona LOOP
      INSERT INTO roast_log
        (roast_log_id, roast_date, origin_id, charge_weight, charge_weight_lbs,
         roasted_weight, "charged?", roast_type, roaster_unit_id, facility_id, company_id,
         coffee_name_snapshot, created_at)
      VALUES (
        gen_random_uuid()::text,
        months.month_start + ((i-1) * 3 + 1) * INTERVAL '1 day' + INTERVAL '10 hours',
        'demo-org-kona', 'demo-cw-15', 15,
        15 * 0.84 + (random() * 0.4 - 0.2),
        true, 'Single Origin/Post-Blend', v_roaster, v_fac, v_co,
        'Hawaii Kona Extra Fancy', NOW()
      );
    END LOOP;

    -- Pele Espresso batches
    FOR i IN 1..months.n_espresso LOOP
      INSERT INTO roast_log
        (roast_log_id, roast_date, recipe_id, charge_weight, charge_weight_lbs,
         roasted_weight, "charged?", roast_type, roaster_unit_id, facility_id, company_id,
         recipe_name_snapshot, created_at)
      VALUES (
        gen_random_uuid()::text,
        months.month_start + ((i-1) * 5 + 2) * INTERVAL '1 day' + INTERVAL '9 hours',
        'demo-rcp-pacific-sunrise', 'demo-cw-25', 25,
        25 * 0.82 + (random() * 0.4 - 0.2),
        true, 'Pre-Blend', v_roaster, v_fac, v_co,
        'Pacific Sunrise Espresso', NOW()
      );
    END LOOP;

    -- Decaf batches
    FOR i IN 1..months.n_decaf LOOP
      INSERT INTO roast_log
        (roast_log_id, roast_date, recipe_id, charge_weight, charge_weight_lbs,
         roasted_weight, "charged?", roast_type, roaster_unit_id, facility_id, company_id,
         recipe_name_snapshot, created_at)
      VALUES (
        gen_random_uuid()::text,
        months.month_start + ((i-1) * 7 + 3) * INTERVAL '1 day' + INTERVAL '7 hours',
        'demo-rcp-decaf-blend', 'demo-cw-15', 15,
        15 * 0.83 + (random() * 0.3 - 0.15),
        true, 'Pre-Blend', v_roaster, v_fac, v_co,
        'Decaf Sunset Blend', NOW()
      );
    END LOOP;

    -- Ethiopia Single Origin batches (starts Aug 2025)
    FOR i IN 1..months.n_ethiopia LOOP
      INSERT INTO roast_log
        (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, charge_weight_lbs,
         roasted_weight, "charged?", roast_type, roaster_unit_id, facility_id, company_id,
         coffee_name_snapshot, recipe_name_snapshot, created_at)
      VALUES (
        gen_random_uuid()::text,
        months.month_start + ((i-1) * 6 + 4) * INTERVAL '1 day' + INTERVAL '11 hours',
        'demo-org-ethiopia', 'demo-rcp-single-ethiopia', 'demo-cw-15', 15,
        15 * 0.83 + (random() * 0.3 - 0.15),
        true, 'Single Origin/Post-Blend', v_roaster, v_fac, v_co,
        'Ethiopia Yirgacheffe Gr. 1', 'Ethiopia Single Origin', NOW()
      );
    END LOOP;

  END LOOP;
END $$;

-- ── 6. HISTORICAL ORDERS (Apr–Dec 2025) ──────────────────────────────────────
-- Growing volume: 20 → 90 orders/month, all status=Delivered

DO $$
DECLARE
  v_fac TEXT := 'demo-kailua-roastery';
  v_co  TEXT := 'demo-aloha-coffee-roasters';

  -- Core product pool (active, wholesale/retail)
  core_products  TEXT[] := ARRAY['demo-prod-016','demo-prod-017','demo-prod-022',
                                  'demo-prod-001','demo-prod-008',
                                  'demo-prod-024','demo-prod-025',
                                  'demo-prod-020','demo-prod-021','demo-prod-023'];
  retail_products TEXT[] := ARRAY['demo-prod-012','demo-prod-018',
                                   'demo-prod-002','demo-prod-009'];
  new_products   TEXT[] := ARRAY['demo-prod-026','demo-prod-027','demo-prod-028',
                                  'demo-prod-029','demo-prod-030'];

  -- Customer tiers
  tier1_custs TEXT[] := ARRAY['demo-cust-001','demo-cust-002','demo-cust-003',
                               'demo-cust-004','demo-cust-005','demo-cust-006',
                               'demo-cust-007','demo-cust-008','demo-cust-009','demo-cust-010'];
  tier2_custs TEXT[] := ARRAY['demo-cust-011','demo-cust-012','demo-cust-013',
                               'demo-cust-014','demo-cust-015','demo-cust-016',
                               'demo-cust-017','demo-cust-018','demo-cust-019','demo-cust-020'];
  tier3_custs TEXT[] := ARRAY['demo-cust-021','demo-cust-022','demo-cust-023',
                               'demo-cust-024','demo-cust-025','demo-cust-026',
                               'demo-cust-027','demo-cust-028','demo-cust-029','demo-cust-030'];
  mainland_custs TEXT[] := ARRAY['demo-cust-031','demo-cust-032','demo-cust-033',
                                  'demo-cust-034','demo-cust-035'];

  -- Month parameters
  months RECORD;

  v_order_id   TEXT;
  v_detail_id  TEXT;
  v_date       DATE;
  v_cust       TEXT;
  v_prod       TEXT;
  v_qty        INT;
  v_n_items    INT;
  available_custs TEXT[];
  available_prods TEXT[];
  i INT;
  j INT;
BEGIN
  FOR months IN (
    SELECT * FROM (VALUES
      -- month_start,  n_orders,  use_tier2, use_tier3, use_mainland, use_new_prods
      ('2025-04-01'::date, 20, false, false, false, false),
      ('2025-05-01'::date, 28, true,  false, false, false),
      ('2025-06-01'::date, 35, true,  false, false, false),
      ('2025-07-01'::date, 45, true,  true,  false, false),
      ('2025-08-01'::date, 55, true,  true,  false, true),
      ('2025-09-01'::date, 63, true,  true,  true,  true),
      ('2025-10-01'::date, 72, true,  true,  true,  true),
      ('2025-11-01'::date, 83, true,  true,  true,  true),
      ('2025-12-01'::date, 92, true,  true,  true,  true)
    ) AS t(month_start, n_orders, use_tier2, use_tier3, use_mainland, use_new_prods)
  ) LOOP

    -- Build available customer pool
    available_custs := tier1_custs;
    IF months.use_tier2   THEN available_custs := available_custs || tier2_custs; END IF;
    IF months.use_tier3   THEN available_custs := available_custs || tier3_custs; END IF;
    IF months.use_mainland THEN available_custs := available_custs || mainland_custs; END IF;

    -- Build available product pool
    available_prods := core_products || retail_products;
    IF months.use_new_prods THEN available_prods := available_prods || new_products; END IF;

    FOR i IN 1..months.n_orders LOOP
      v_order_id := gen_random_uuid()::text;
      -- Spread orders across the month (weekdays skew)
      v_date := months.month_start + ((i * 28 / months.n_orders) % 28)::int;

      -- Pick customer (cycle through available pool)
      v_cust := available_custs[1 + ((i - 1) % array_length(available_custs, 1))];

      -- 1-3 line items per order
      v_n_items := 1 + ((i * 7 + 3) % 3);

      INSERT INTO orders (order_id, customer_id, order_date, order_status,
                          facility_id, company_id, status_changed_at, created_at)
      VALUES (v_order_id, v_cust, v_date, 'Delivered',
              v_fac, v_co, (v_date + 7)::timestamp, NOW());

      FOR j IN 1..v_n_items LOOP
        v_detail_id := gen_random_uuid()::text;
        v_prod := available_prods[1 + ((i * 3 + j * 7) % array_length(available_prods, 1))];
        -- Qty: 1-12 bags depending on product type
        v_qty := 1 + ((i * 5 + j * 11) % 10);

        INSERT INTO order_details (order_detail_id, order_id, product_id, quantity,
                                   item_status, order_date, customer_id,
                                   facility_id, company_id, created_at)
        VALUES (v_detail_id, v_order_id, v_prod, v_qty,
                'Open', v_date, v_cust,
                v_fac, v_co, NOW());
      END LOOP;
    END LOOP;

  END LOOP;
END $$;

-- ── Restore normal role ───────────────────────────────────────────────────────
RESET session_replication_role;

-- ── Nudge latest_cost to propagate COGS for new products ─────────────────────
-- Only needs to run for the new Ethiopia/Tradewind products since their
-- recipe_components already have component_cost set.
-- Force update_product_total_cogs by touching is_active on the new products.
UPDATE products SET is_active = true
WHERE product_id IN ('demo-prod-026','demo-prod-027','demo-prod-028','demo-prod-029','demo-prod-030');
