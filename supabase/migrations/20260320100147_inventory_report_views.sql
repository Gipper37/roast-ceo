-- Migration 00147: Inventory report views
-- Creates 5 views:
--   monthly_coffee_usage              – aggregate green coffee roasted per facility per month
--   monthly_coffee_usage_by_origin    – same broken out per origin (blends allocated by %)
--   monthly_coffee_stock_by_origin    – reconstructed month-end green stock per origin,
--                                        pegged to manual inventory counts
--   monthly_consumable_usage_by_item  – consumable units consumed per item per month
--   monthly_consumable_stock_by_item  – reconstructed month-end consumable stock per item,
--                                        pegged to manual inventory counts

-- ============================================================
-- 1. monthly_coffee_usage
-- ============================================================
CREATE VIEW monthly_coffee_usage AS
SELECT
    rl.facility_id || '_' || date_trunc('month', rl.roast_date)::date AS month_usage_id,
    date_trunc('month', rl.roast_date)::date                          AS month_start,
    rl.facility_id,
    rl.company_id,
    ROUND(SUM(rl.charge_weight)::numeric,  2) AS green_used_lbs,
    ROUND(SUM(rl.roasted_weight)::numeric, 2) AS lbs_roasted,
    COUNT(*)::integer                          AS batch_count,
    ROUND(
        SUM(rl.roasted_weight) / NULLIF(SUM(rl.charge_weight), 0) * 100,
        1
    )                                          AS retention_pct
FROM roast_log rl
GROUP BY
    date_trunc('month', rl.roast_date),
    rl.facility_id,
    rl.company_id;

-- ============================================================
-- 2. monthly_coffee_usage_by_origin
-- ============================================================
CREATE VIEW monthly_coffee_usage_by_origin AS
WITH roast_by_origin AS (
    -- single-origin roasts
    SELECT
        rl.roast_date,
        rl.origin_id,
        rl.charge_weight  AS green_used_lbs,
        rl.roasted_weight AS lbs_roasted,
        rl.facility_id,
        rl.company_id
    FROM roast_log rl
    WHERE rl.origin_id IS NOT NULL

    UNION ALL

    -- blend roasts: allocate charge/roasted weight by recipe component percentage
    SELECT
        rl.roast_date,
        rc.coffee_item                    AS origin_id,
        rl.charge_weight  * rc.percentage AS green_used_lbs,
        rl.roasted_weight * rc.percentage AS lbs_roasted,
        rl.facility_id,
        rl.company_id
    FROM roast_log rl
    JOIN recipe_components rc ON rc.recipe_id = rl.recipe_id
    WHERE rl.origin_id IS NULL
      AND rl.recipe_id IS NOT NULL
)
SELECT
    r.facility_id || '_' || r.origin_id || '_' || date_trunc('month', r.roast_date)::date AS month_origin_id,
    date_trunc('month', r.roast_date)::date                  AS month_start,
    r.origin_id,
    ci.origin                                                AS origin_name,
    r.facility_id,
    r.company_id,
    ROUND(SUM(r.green_used_lbs)::numeric, 2)                 AS green_used_lbs,
    ROUND(SUM(r.lbs_roasted)::numeric,    2)                 AS lbs_roasted
FROM roast_by_origin r
LEFT JOIN coffee_inventory ci
    ON ci.origin_id = r.origin_id
   AND ci.facility_id = r.facility_id
GROUP BY
    date_trunc('month', r.roast_date),
    r.origin_id,
    ci.origin,
    r.facility_id,
    r.company_id;

-- ============================================================
-- 3. monthly_coffee_stock_by_origin
-- ============================================================
CREATE VIEW monthly_coffee_stock_by_origin AS
WITH
-- all green coffee roasted, per origin (single + blend allocated)
all_roasts AS (
    SELECT
        rl.roast_date::date AS roast_date,
        rl.origin_id,
        rl.facility_id,
        rl.charge_weight    AS green_lbs
    FROM roast_log rl
    WHERE rl.origin_id IS NOT NULL

    UNION ALL

    SELECT
        rl.roast_date::date,
        rc.coffee_item      AS origin_id,
        rl.facility_id,
        rl.charge_weight * rc.percentage AS green_lbs
    FROM roast_log rl
    JOIN recipe_components rc ON rc.recipe_id = rl.recipe_id
    WHERE rl.origin_id IS NULL
      AND rl.recipe_id IS NOT NULL
),
-- all green coffee received (shipment must be marked received)
all_purchases AS (
    SELECT
        sr.date_received::date AS received_date,
        p.origin               AS origin_id,
        p.facility_id,
        p.amount               AS purchased_lbs
    FROM coffee_inventory_purchased p
    JOIN shipment_received sr ON sr.shipment_id = p.shipment_id
    WHERE sr.date_received IS NOT NULL
),
-- distinct (origin, facility) pairs with bag_size for stock calc
origins AS (
    SELECT DISTINCT
        origin_id,
        facility_id,
        company_id,
        bag_size,
        origin AS origin_name
    FROM coffee_inventory
    WHERE origin_id IS NOT NULL
),
-- earliest event per origin+facility to anchor the date spine
origin_first_event AS (
    SELECT origin_id, facility_id, MIN(event_date) AS first_event
    FROM (
        SELECT origin_id, facility_id, inventory_date AS event_date
        FROM coffee_inventory_history

        UNION ALL

        SELECT origin_id, facility_id, received_date AS event_date
        FROM all_purchases

        UNION ALL

        SELECT origin_id, facility_id, roast_date AS event_date
        FROM all_roasts
    ) events
    WHERE origin_id IS NOT NULL
    GROUP BY origin_id, facility_id
),
-- month spine: one row per origin per facility from first event to current month
date_spine AS (
    SELECT
        o.origin_id,
        o.facility_id,
        o.company_id,
        o.bag_size,
        o.origin_name,
        gs.month_start::date AS month_start
    FROM origins o
    JOIN origin_first_event fe
        ON fe.origin_id   = o.origin_id
       AND fe.facility_id = o.facility_id
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
    anchor.anchor_date,
    CASE
        WHEN anchor.anchor_date IS NULL THEN NULL
        ELSE ROUND(
            anchor.anchor_bags * ds.bag_size::numeric
            + COALESCE(purch.purchased_lbs, 0)
            - COALESCE(roasted.green_lbs,   0),
            1
        )
    END AS stock_lbs
FROM date_spine ds

-- most recent manual count at or before month-end
LEFT JOIN LATERAL (
    SELECT h.inventory_date AS anchor_date, h.bag_count AS anchor_bags
    FROM coffee_inventory_history h
    WHERE h.origin_id   = ds.origin_id
      AND h.facility_id = ds.facility_id
      AND h.inventory_date < (ds.month_start + INTERVAL '1 month')::date
    ORDER BY h.inventory_date DESC
    LIMIT 1
) anchor ON true

-- purchases received after anchor through month-end
LEFT JOIN LATERAL (
    SELECT COALESCE(SUM(ap.purchased_lbs), 0) AS purchased_lbs
    FROM all_purchases ap
    WHERE ap.origin_id   = ds.origin_id
      AND ap.facility_id = ds.facility_id
      AND ap.received_date >  anchor.anchor_date
      AND ap.received_date < (ds.month_start + INTERVAL '1 month')::date
) purch ON true

-- green roasted after anchor through month-end
LEFT JOIN LATERAL (
    SELECT COALESCE(SUM(ar.green_lbs), 0) AS green_lbs
    FROM all_roasts ar
    WHERE ar.origin_id   = ds.origin_id
      AND ar.facility_id = ds.facility_id
      AND ar.roast_date >  anchor.anchor_date
      AND ar.roast_date < (ds.month_start + INTERVAL '1 month')::date
) roasted ON true;

-- ============================================================
-- 4. monthly_consumable_usage_by_item
-- ============================================================
CREATE VIEW monthly_consumable_usage_by_item AS
SELECT
    od.facility_id || '_' || pc.consumable_id || '_' || date_trunc('month', o.order_date)::date AS month_item_id,
    date_trunc('month', o.order_date)::date       AS month_start,
    pc.consumable_id,
    ci.consumable_inventory_item                  AS item_name,
    od.facility_id,
    od.company_id,
    ROUND(SUM(od.quantity * pc.quantity)::numeric, 2) AS units_used
FROM order_details od
JOIN orders o
    ON o.order_id = od.order_id
JOIN product_consumables pc
    ON pc.product_id = od.product_id
JOIN consumable_inventory ci
    ON ci.consumable_inventory_id = pc.consumable_id
   AND ci.facility_id             = od.facility_id
WHERE o.order_status != 'Canceled'
GROUP BY
    date_trunc('month', o.order_date),
    pc.consumable_id,
    ci.consumable_inventory_item,
    od.facility_id,
    od.company_id;

-- ============================================================
-- 5. monthly_consumable_stock_by_item
-- ============================================================
CREATE VIEW monthly_consumable_stock_by_item AS
WITH
-- consumable units used per item per facility per day (non-Canceled orders)
all_usage AS (
    SELECT
        o.order_date                      AS usage_date,
        pc.consumable_id,
        od.facility_id,
        SUM(od.quantity * pc.quantity)    AS units_used
    FROM order_details od
    JOIN orders o  ON o.order_id  = od.order_id
    JOIN product_consumables pc ON pc.product_id = od.product_id
    WHERE o.order_status != 'Canceled'
    GROUP BY o.order_date, pc.consumable_id, od.facility_id
),
-- consumable units received per item per facility per day
all_purchases AS (
    SELECT
        sr.date_received::date             AS received_date,
        p.consumable_inventory_item        AS consumable_id,
        p.facility_id,
        p.amount::numeric                  AS purchased_units
    FROM consumable_inventory_purchased p
    JOIN shipment_received sr ON sr.shipment_id = p.shipment_id
    WHERE sr.date_received IS NOT NULL
),
-- distinct (consumable, facility) pairs
consumables AS (
    SELECT DISTINCT
        consumable_inventory_id AS consumable_id,
        facility_id,
        company_id,
        consumable_inventory_item AS item_name
    FROM consumable_inventory
),
-- earliest event per consumable+facility to anchor the date spine
consumable_first_event AS (
    SELECT consumable_id, facility_id, MIN(event_date) AS first_event
    FROM (
        SELECT consumable_id, facility_id, inventory_date AS event_date
        FROM consumable_inventory_history

        UNION ALL

        SELECT consumable_id, facility_id, received_date AS event_date
        FROM all_purchases

        UNION ALL

        SELECT consumable_id, facility_id, usage_date AS event_date
        FROM all_usage
    ) events
    GROUP BY consumable_id, facility_id
),
-- month spine: one row per consumable per facility from first event to current month
date_spine AS (
    SELECT
        c.consumable_id,
        c.facility_id,
        c.company_id,
        c.item_name,
        gs.month_start::date AS month_start
    FROM consumables c
    JOIN consumable_first_event fe
        ON fe.consumable_id = c.consumable_id
       AND fe.facility_id   = c.facility_id
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
    anchor.anchor_date,
    CASE
        WHEN anchor.anchor_date IS NULL THEN NULL
        ELSE ROUND(
            anchor.anchor_count::numeric
            + COALESCE(purch.purchased_units, 0)
            - COALESCE(used.units_used,       0),
            0
        )
    END AS in_stock
FROM date_spine ds

-- most recent manual count at or before month-end
LEFT JOIN LATERAL (
    SELECT h.inventory_date AS anchor_date, h.inventory_count AS anchor_count
    FROM consumable_inventory_history h
    WHERE h.consumable_id = ds.consumable_id
      AND h.facility_id   = ds.facility_id
      AND h.inventory_date < (ds.month_start + INTERVAL '1 month')::date
    ORDER BY h.inventory_date DESC
    LIMIT 1
) anchor ON true

-- units purchased after anchor through month-end
LEFT JOIN LATERAL (
    SELECT COALESCE(SUM(ap.purchased_units), 0) AS purchased_units
    FROM all_purchases ap
    WHERE ap.consumable_id = ds.consumable_id
      AND ap.facility_id   = ds.facility_id
      AND ap.received_date >  anchor.anchor_date
      AND ap.received_date < (ds.month_start + INTERVAL '1 month')::date
) purch ON true

-- units used after anchor through month-end
LEFT JOIN LATERAL (
    SELECT COALESCE(SUM(au.units_used), 0) AS units_used
    FROM all_usage au
    WHERE au.consumable_id = ds.consumable_id
      AND au.facility_id   = ds.facility_id
      AND au.usage_date >  anchor.anchor_date
      AND au.usage_date < (ds.month_start + INTERVAL '1 month')::date
) used ON true;
