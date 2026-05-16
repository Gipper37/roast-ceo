-- ============================================================
-- Replace monthly_coffee_stock_by_origin with
-- weekly_coffee_stock_by_origin — weekly spine, 1-year lookback
-- ============================================================
DROP VIEW IF EXISTS monthly_coffee_stock_by_origin;

CREATE VIEW weekly_coffee_stock_by_origin AS
WITH
direct_roasts AS (
    SELECT rl.roast_date::date AS roast_date, rl.origin_id, rl.facility_id, rl.charge_weight AS green_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rr.recipe_id = rl.recipe_id
    WHERE rl.origin_id IS NOT NULL
      AND rl."charged?" = TRUE
      AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend')
),
blend_roasts AS (
    SELECT rl.roast_date::date AS roast_date, rc.coffee_item AS origin_id, rl.facility_id,
           rl.charge_weight * rc.percentage AS green_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rr.recipe_id = rl.recipe_id
    JOIN recipe_components rc ON rc.recipe_id = rl.recipe_id
    WHERE rl.origin_id IS NULL
      AND rr.roast_type = 'Pre-Blend'
      AND rl."charged?" = TRUE
),
all_roasts AS (
    SELECT * FROM direct_roasts
    UNION ALL
    SELECT * FROM blend_roasts
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
date_spine AS (
    SELECT o.origin_id, o.facility_id, o.company_id, o.bag_size, o.origin_name,
           gs.week_start::date AS week_start
    FROM origins o
    JOIN LATERAL generate_series(
        date_trunc('week', NOW() - INTERVAL '1 year'),
        date_trunc('week', NOW()),
        INTERVAL '1 week'
    ) AS gs(week_start) ON true
)
SELECT
    ds.facility_id || '_' || ds.origin_id || '_' || ds.week_start AS week_stock_id,
    ds.week_start,
    ds.origin_id,
    ds.origin_name,
    ds.facility_id,
    ds.company_id,
    GREATEST(0, ROUND(
        COALESCE(anchor.anchor_bags, 0) * ds.bag_size::numeric
        + COALESCE(purch.purchased_lbs, 0)
        - COALESCE(roasted.green_lbs,   0),
    1)) AS stock_lbs
FROM date_spine ds
LEFT JOIN LATERAL (
    SELECT h.inventory_date AS anchor_date, h.bag_count AS anchor_bags
    FROM coffee_inventory_history h
    WHERE h.origin_id   = ds.origin_id
      AND h.facility_id = ds.facility_id
      AND h.inventory_date < (ds.week_start + INTERVAL '1 week')::date
    ORDER BY h.inventory_date DESC
    LIMIT 1
) anchor ON true
LEFT JOIN LATERAL (
    SELECT COALESCE(SUM(ap.purchased_lbs), 0) AS purchased_lbs
    FROM all_purchases ap
    WHERE ap.origin_id   = ds.origin_id
      AND ap.facility_id = ds.facility_id
      AND ap.received_date >  COALESCE(anchor.anchor_date, '2000-01-01'::date)
      AND ap.received_date < (ds.week_start + INTERVAL '1 week')::date
) purch ON true
LEFT JOIN LATERAL (
    SELECT COALESCE(SUM(ar.green_lbs), 0) AS green_lbs
    FROM all_roasts ar
    WHERE ar.origin_id   = ds.origin_id
      AND ar.facility_id = ds.facility_id
      AND ar.roast_date >  COALESCE(anchor.anchor_date, '2000-01-01'::date)
      AND ar.roast_date < (ds.week_start + INTERVAL '1 week')::date
) roasted ON true;
