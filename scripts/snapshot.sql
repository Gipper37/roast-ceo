-- STRATA Pre-Migration Snapshot
-- Run before and after product variant migration to verify data integrity

\echo '=== SNAPSHOT DATE ==='
SELECT now() AS snapshot_at;

\echo ''
\echo '=== PRODUCT COUNTS ==='
SELECT
  COUNT(*)                                                    AS total_products,
  COUNT(*) FILTER (WHERE is_archived = false OR is_archived IS NULL) AS active_products,
  COUNT(*) FILTER (WHERE product_type = 'Merged')             AS merged_products,
  COUNT(*) FILTER (WHERE product_type = 'Sample')             AS sample_products
FROM products;

\echo ''
\echo '=== REVENUE & PROFITABILITY (ALL TIME) ==='
SELECT
  ROUND(SUM(revenue)::numeric, 2)       AS total_revenue,
  ROUND(SUM(cogs)::numeric, 2)          AS total_cogs,
  ROUND(SUM(gross_profit)::numeric, 2)  AS total_gross_profit,
  SUM(total_orders)                     AS total_orders
FROM customer_profitability;

\echo ''
\echo '=== ORDERS BY STATUS ==='
SELECT order_status, COUNT(*) AS count, ROUND(SUM(order_total)::numeric, 2) AS total_value
FROM orders
GROUP BY order_status
ORDER BY count DESC;

\echo ''
\echo '=== TOP 20 PRODUCTS BY REVENUE ==='
SELECT
  p.product_name,
  p.product_type,
  COUNT(DISTINCT od.order_id)           AS order_count,
  SUM(od.quantity)                      AS units_sold,
  ROUND(SUM(od.line_price)::numeric, 2) AS revenue
FROM order_details od
JOIN products p ON p.product_id = od.product_id
JOIN orders o ON o.order_id = od.order_id
WHERE o.order_status != 'Canceled'
GROUP BY p.product_id, p.product_name, p.product_type
ORDER BY revenue DESC NULLS LAST
LIMIT 20;

\echo ''
\echo '=== COFFEE INVENTORY STOCK ==='
SELECT
  ci.origin_id,
  ci.in_stock_bags,
  ci.bag_size,
  ROUND((ci.in_stock_bags * ci.bag_size::numeric)::numeric, 2) AS stock_lbs,
  ROUND(ci.latest_cost::numeric, 4)     AS latest_cost_per_lb
FROM coffee_inventory ci
ORDER BY origin_id;

\echo ''
\echo '=== CONSUMABLE INVENTORY STOCK ==='
SELECT
  item_name,
  current_stock,
  unit
FROM consumable_inventory
ORDER BY item_name;

\echo ''
\echo '=== CUSTOMER COUNTS ==='
SELECT
  COUNT(*)                                                        AS total_customers,
  COUNT(*) FILTER (WHERE deal_open_closed = false)                AS signed_customers,
  COUNT(*) FILTER (WHERE deal_open_closed = true)                 AS prospects,
  COUNT(*) FILTER (WHERE is_active = true AND deal_open_closed = false) AS active_signed
FROM customers;

\echo ''
\echo '=== CONTACTS COUNT ==='
SELECT COUNT(*) AS total_contacts, COUNT(*) FILTER (WHERE is_active = true) AS active_contacts
FROM contacts;

\echo ''
\echo '=== ORDER DETAILS LINE ITEM COUNT ==='
SELECT COUNT(*) AS total_line_items FROM order_details;

\echo ''
\echo '=== PRICE LOG ENTRIES ==='
SELECT COUNT(*) AS total_price_log_entries FROM products_price_log;

\echo ''
\echo '=== ROAST LOG ==='
SELECT COUNT(*) AS total_roast_entries, ROUND(SUM(charge_weight_lbs)::numeric, 2) AS total_lbs_roasted
FROM roast_log;

\echo ''
\echo '=== RECIPE COMPONENTS ==='
SELECT COUNT(*) AS total_recipe_components FROM recipe_components;

\echo ''
\echo '=== PRODUCT CONSUMABLE BOM ROWS ==='
SELECT COUNT(*) AS total_bom_rows FROM product_consumables;
