-- Migration 00149: Remove anchor_date from both stock views (internal implementation detail)

DROP VIEW IF EXISTS monthly_coffee_stock_by_origin;
DROP VIEW IF EXISTS monthly_consumable_stock_by_item;

-- ============================================================
-- monthly_coffee_stock_by_origin (no anchor_date)
-- ============================================================
CREATE VIEW monthly_coffee_stock_by_origin AS
WITH
all_roasts AS (
    SELECT rl.roast_date::date AS roast_date, rl.origin_id, rl.facility_id, rl.charge_weight AS green_lbs
    FROM roast_log rl
    WHERE rl.origin_id IS NOT NULL

    UNION ALL

    SELECT rl.roast_date::date, rc.coffee_item AS origin_id, rl.facility_id, rl.charge_weight * rc.percentage AS green_lbs
    FROM roast_log rl
    JOIN recipe_components rc ON rc.recipe_id = rl.recipe_id
    WHERE rl.origin_id IS NULL AND rl.recipe_id IS NOT NULL
),
all_purchases AS (
    SELECT sr.date_received::date AS received_date, p.origin AS origin_id, p.facility_id, p.amount AS purchased_lbs
    FROM coffee_inventory_purchased p
    JOIN shipment_received sr ON sr.shipment_id = p.shipment_id
    WHERE sr.date_received IS NOT NULL
),
origins AS (
    SELECT DISTINCT origin_id, facility_id, company_id, bag_size, origin AS origin_name
    FROM coffee_inventory
    WHERE origin_id IS NOT NULL
),
origin_first_event AS (
    SELECT origin_id, facility_id, MIN(event_date) AS first_event
    FROM (
        SELECT origin_id, facility_id, inventory_date AS event_date FROM coffee_inventory_history
        UNION ALL
        SELECT origin_id, facility_id, received_date  FROM all_purchases
        UNION ALL
        SELECT origin_id, facility_id, roast_date     FROM all_roasts
    ) events
    WHERE origin_id IS NOT NULL
    GROUP BY origin_id, facility_id
),
date_spine AS (
    SELECT o.origin_id, o.facility_id, o.company_id, o.bag_size, o.origin_name, gs.month_start::date AS month_start
    FROM origins o
    JOIN origin_first_event fe ON fe.origin_id = o.origin_id AND fe.facility_id = o.facility_id
    JOIN LATERAL generate_series(
        date_trunc('month', fe.first_event::timestamp),
        date_trunc('month', NOW()),
        INTERVAL '1 month'
    ) AS gs(month_start) ON true
    WHERE fe.first_event < 'infinity'::date
)
SELECT
    ds.facility_id || '_' || ds.origin_id || '_' || ds.month_start AS month_stock_id,
    ds.month_start,
    ds.origin_id,
    ds.origin_name,
    ds.facility_id,
    ds.company_id,
    ROUND(
        COALESCE(anchor.anchor_bags, 0) * ds.bag_size::numeric
        + COALESCE(purch.purchased_lbs, 0)
        - COALESCE(roasted.green_lbs,   0),
        1
    ) AS stock_lbs
FROM date_spine ds
LEFT JOIN LATERAL (
    SELECT h.inventory_date AS anchor_date, h.bag_count AS anchor_bags
    FROM coffee_inventory_history h
    WHERE h.origin_id = ds.origin_id AND h.facility_id = ds.facility_id
      AND h.inventory_date < (ds.month_start + INTERVAL '1 month')::date
    ORDER BY h.inventory_date DESC
    LIMIT 1
) anchor ON true
LEFT JOIN LATERAL (
    SELECT COALESCE(SUM(ap.purchased_lbs), 0) AS purchased_lbs
    FROM all_purchases ap
    WHERE ap.origin_id = ds.origin_id AND ap.facility_id = ds.facility_id
      AND ap.received_date >  COALESCE(anchor.anchor_date, '1900-01-01'::date)
      AND ap.received_date < (ds.month_start + INTERVAL '1 month')::date
) purch ON true
LEFT JOIN LATERAL (
    SELECT COALESCE(SUM(ar.green_lbs), 0) AS green_lbs
    FROM all_roasts ar
    WHERE ar.origin_id = ds.origin_id AND ar.facility_id = ds.facility_id
      AND ar.roast_date >  COALESCE(anchor.anchor_date, '1900-01-01'::date)
      AND ar.roast_date < (ds.month_start + INTERVAL '1 month')::date
) roasted ON true;

-- ============================================================
-- monthly_consumable_stock_by_item (no anchor_date)
-- ============================================================
CREATE VIEW monthly_consumable_stock_by_item AS
WITH
all_usage AS (
    SELECT o.order_date AS usage_date, pc.consumable_id, od.facility_id, SUM(od.quantity * pc.quantity) AS units_used
    FROM order_details od
    JOIN orders o ON o.order_id = od.order_id
    JOIN product_consumables pc ON pc.product_id = od.product_id
    WHERE o.order_status != 'Canceled'
    GROUP BY o.order_date, pc.consumable_id, od.facility_id
),
all_purchases AS (
    SELECT sr.date_received::date AS received_date, p.consumable_inventory_item AS consumable_id, p.facility_id, p.amount::numeric AS purchased_units
    FROM consumable_inventory_purchased p
    JOIN shipment_received sr ON sr.shipment_id = p.shipment_id
    WHERE sr.date_received IS NOT NULL
),
consumables AS (
    SELECT DISTINCT consumable_inventory_id AS consumable_id, facility_id, company_id, consumable_inventory_item AS item_name
    FROM consumable_inventory
),
consumable_first_event AS (
    SELECT consumable_id, facility_id, MIN(event_date) AS first_event
    FROM (
        SELECT consumable_id, facility_id, inventory_date AS event_date FROM consumable_inventory_history
        UNION ALL
        SELECT consumable_id, facility_id, received_date  FROM all_purchases
        UNION ALL
        SELECT consumable_id, facility_id, usage_date     FROM all_usage
    ) events
    GROUP BY consumable_id, facility_id
),
date_spine AS (
    SELECT c.consumable_id, c.facility_id, c.company_id, c.item_name, gs.month_start::date AS month_start
    FROM consumables c
    JOIN consumable_first_event fe ON fe.consumable_id = c.consumable_id AND fe.facility_id = c.facility_id
    JOIN LATERAL generate_series(
        date_trunc('month', fe.first_event::timestamp),
        date_trunc('month', NOW()),
        INTERVAL '1 month'
    ) AS gs(month_start) ON true
    WHERE fe.first_event < 'infinity'::date
)
SELECT
    ds.facility_id || '_' || ds.consumable_id || '_' || ds.month_start AS month_stock_id,
    ds.month_start,
    ds.consumable_id,
    ds.item_name,
    ds.facility_id,
    ds.company_id,
    ROUND(
        COALESCE(anchor.anchor_count, 0)::numeric
        + COALESCE(purch.purchased_units, 0)
        - COALESCE(used.units_used,       0),
        0
    ) AS in_stock
FROM date_spine ds
LEFT JOIN LATERAL (
    SELECT h.inventory_date AS anchor_date, h.inventory_count AS anchor_count
    FROM consumable_inventory_history h
    WHERE h.consumable_id = ds.consumable_id AND h.facility_id = ds.facility_id
      AND h.inventory_date < (ds.month_start + INTERVAL '1 month')::date
    ORDER BY h.inventory_date DESC
    LIMIT 1
) anchor ON true
LEFT JOIN LATERAL (
    SELECT COALESCE(SUM(ap.purchased_units), 0) AS purchased_units
    FROM all_purchases ap
    WHERE ap.consumable_id = ds.consumable_id AND ap.facility_id = ds.facility_id
      AND ap.received_date >  COALESCE(anchor.anchor_date, '1900-01-01'::date)
      AND ap.received_date < (ds.month_start + INTERVAL '1 month')::date
) purch ON true
LEFT JOIN LATERAL (
    SELECT COALESCE(SUM(au.units_used), 0) AS units_used
    FROM all_usage au
    WHERE au.consumable_id = ds.consumable_id AND au.facility_id = ds.facility_id
      AND au.usage_date >  COALESCE(anchor.anchor_date, '1900-01-01'::date)
      AND au.usage_date < (ds.month_start + INTERVAL '1 month')::date
) used ON true;
