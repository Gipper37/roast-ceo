-- Purge four early-testing companies that were never used past the
-- initial sign-up flow:
--
--   Blue Ridge Roasters  (c6dcd861-…)  — 0 team, 1 facility, no data
--   Foldgers             (1d8ede89-…)  — 0 team, 1 facility, no data
--   pick                 (6ec258e2-…)  — 0 team, 1 facility, no data
--   Test Company         (42046c1d-…)  — 0 team, 2 facilities, 1 customer, 1 sub
--
-- Most tables that reference companies are ON DELETE CASCADE (facilities,
-- subscriptions, restock_category, shop_config, etc.). The non-cascading
-- ones (customers, sales_area, company_parameters, size, etc.) need
-- explicit DELETEs first; that's what the bulk of this migration does.
--
-- Order matters: leaf tables before parent tables. Sales/contact /
-- customer trees go before customers themselves; products before
-- product_groups (cascades) etc. Anything left referencing a deleted
-- company will surface as a FK error and abort the transaction.

BEGIN;

WITH targets AS (
  SELECT unnest(ARRAY[
    'c6dcd861-ec16-4967-bc85-53726ff51504',
    '1d8ede89-bfae-42d5-aca5-fc58af84711f',
    '6ec258e2-9b16-44a0-baae-2a7e4a3a2522',
    '42046c1d-13bd-4c9f-81f3-ee8acf794611'
  ]) AS company_id
)
SELECT 'Purging ' || count(*) || ' companies' AS msg FROM targets;

-- ── Sales / customer tree ─────────────────────────────────────────
DELETE FROM sales_notes              WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM sales_tasks              WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM customer_notes_detail    WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM customer_sales_filter    WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM contacts                 WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM contact_role             WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM customers                WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');

-- ── Order chain ───────────────────────────────────────────────────
DELETE FROM order_details            WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM orders                   WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');

-- ── Roast / recipe / product tree ─────────────────────────────────
DELETE FROM roast_log                WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM blending_worksheet       WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM recipe_components        WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM roast_recipes            WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM products_price_log       WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM product_filter           WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM product_consumables      WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM products                 WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');

-- ── Inventory tree ────────────────────────────────────────────────
DELETE FROM staged_line_items        WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM staged_shipments         WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM invoice_documents        WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM coffee_inventory_purchased   WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM consumable_inventory_purchased WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM shipment_received        WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM coffee_inventory         WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM consumable_inventory     WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');

-- ── Lookup / config tables ────────────────────────────────────────
DELETE FROM consumable_type          WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM product_type             WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM management_type          WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM channel                  WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM size                     WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM charge_weight_options    WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM supplier_category        WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM supplier                 WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM sales_area               WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM sales_category           WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM sales_data_filter        WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM sales_goals              WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM sales_parameters         WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM sales_state_backup       WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM sales_tracking           WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM company_parameters       WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');
DELETE FROM team                     WHERE company_id IN ('c6dcd861-ec16-4967-bc85-53726ff51504','1d8ede89-bfae-42d5-aca5-fc58af84711f','6ec258e2-9b16-44a0-baae-2a7e4a3a2522','42046c1d-13bd-4c9f-81f3-ee8acf794611');

-- ── Companies (cascades the rest: facilities, subscriptions, etc.) ──
DELETE FROM companies
WHERE company_id IN (
  'c6dcd861-ec16-4967-bc85-53726ff51504',
  '1d8ede89-bfae-42d5-aca5-fc58af84711f',
  '6ec258e2-9b16-44a0-baae-2a7e4a3a2522',
  '42046c1d-13bd-4c9f-81f3-ee8acf794611'
);

COMMIT;
