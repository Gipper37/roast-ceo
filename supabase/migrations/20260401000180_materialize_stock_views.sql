-- Convert weekly_coffee_stock_by_origin and monthly_consumable_stock_by_item
-- from regular views to materialized views.
-- These views use generate_series + correlated subqueries and are ~2s each.
-- AppSheet queries them 1000+ times/session → massive cumulative slowness.
-- Materialized views are refreshed hourly via pg_cron instead.

-- ── 1. weekly_coffee_stock_by_origin ────────────────────────────────────────

DROP VIEW IF EXISTS public.weekly_coffee_stock_by_origin;

CREATE MATERIALIZED VIEW public.weekly_coffee_stock_by_origin AS
WITH direct_roasts AS (
    SELECT rl.roast_date::date AS roast_date,
           rl.origin_id,
           rl.facility_id,
           rl.charge_weight_lbs AS green_lbs
      FROM roast_log rl
      JOIN roast_recipes rr ON rr.recipe_id = rl.recipe_id
     WHERE rl.origin_id IS NOT NULL
       AND rl."charged?" = true
       AND rr.roast_type IS DISTINCT FROM 'Pre-Blend'
), blend_roasts AS (
    SELECT rl.roast_date::date AS roast_date,
           rc.coffee_item AS origin_id,
           rl.facility_id,
           rl.charge_weight_lbs * rc.percentage AS green_lbs
      FROM roast_log rl
      JOIN roast_recipes rr ON rr.recipe_id = rl.recipe_id
      JOIN recipe_components rc ON rc.recipe_id = rl.recipe_id
     WHERE rl.origin_id IS NULL
       AND rr.roast_type = 'Pre-Blend'
       AND rl."charged?" = true
), all_roasts AS (
    SELECT * FROM direct_roasts
    UNION ALL
    SELECT * FROM blend_roasts
), all_purchases AS (
    SELECT sr.date_received AS received_date,
           p.origin AS origin_id,
           p.facility_id,
           p.amount AS purchased_lbs
      FROM coffee_inventory_purchased p
      JOIN shipment_received sr ON sr.shipment_id = p.shipment_id
     WHERE sr.date_received IS NOT NULL
       AND COALESCE(sr.voided, false) = false
), origins AS (
    SELECT DISTINCT ci.origin_id,
           ci.facility_id,
           ci.company_id,
           ci.bag_size,
           ci.origin AS origin_name
      FROM coffee_inventory ci
     WHERE ci.origin_id IS NOT NULL
), date_spine AS (
    SELECT o.origin_id,
           o.facility_id,
           o.company_id,
           o.bag_size,
           o.origin_name,
           gs.week_start::date AS week_start
      FROM origins o
      JOIN LATERAL generate_series(
               date_trunc('week', now() - interval '1 year'),
               date_trunc('week', now()),
               interval '7 days'
           ) gs(week_start) ON true
)
SELECT (ds.facility_id || '_' || ds.origin_id || '_') || ds.week_start AS week_stock_id,
       ds.week_start,
       ds.origin_id,
       ds.origin_name,
       ds.facility_id,
       ds.company_id,
       GREATEST(0, COALESCE((
           SELECT ci.inventory_count_bags * ci.bag_size::numeric
             FROM coffee_inventory ci
            WHERE ci.origin_id = ds.origin_id AND ci.facility_id = ds.facility_id
            LIMIT 1
       ), 0)
       + COALESCE((
           SELECT sum(p.purchased_lbs)
             FROM all_purchases p
            WHERE p.origin_id = ds.origin_id
              AND p.facility_id = ds.facility_id
              AND p.received_date > (SELECT COALESCE(ci.last_inventory, '1970-01-01'::date)
                                       FROM coffee_inventory ci
                                      WHERE ci.origin_id = ds.origin_id AND ci.facility_id = ds.facility_id
                                      LIMIT 1)
              AND p.received_date <= ds.week_start
       ), 0)
       - COALESCE((
           SELECT sum(r.green_lbs)
             FROM all_roasts r
            WHERE r.origin_id = ds.origin_id
              AND r.facility_id = ds.facility_id
              AND r.roast_date > (SELECT COALESCE(ci.last_inventory, '1970-01-01'::date)
                                    FROM coffee_inventory ci
                                   WHERE ci.origin_id = ds.origin_id AND ci.facility_id = ds.facility_id
                                   LIMIT 1)
              AND r.roast_date <= ds.week_start
       ), 0)) AS stock_lbs
  FROM date_spine ds
WITH DATA;

CREATE UNIQUE INDEX idx_weekly_coffee_stock_id
    ON public.weekly_coffee_stock_by_origin (week_stock_id);

CREATE INDEX idx_weekly_coffee_stock_origin_facility
    ON public.weekly_coffee_stock_by_origin (origin_id, facility_id);

-- ── 2. monthly_consumable_stock_by_item ─────────────────────────────────────

DROP VIEW IF EXISTS public.monthly_consumable_stock_by_item;

CREATE MATERIALIZED VIEW public.monthly_consumable_stock_by_item AS
WITH all_usage AS (
    SELECT o.order_date AS usage_date,
           pc.consumable_id,
           od.facility_id,
           sum(od.quantity * pc.quantity) AS units_used
      FROM order_details od
      JOIN orders o ON o.order_id = od.order_id
      JOIN product_consumables pc ON pc.product_id = od.product_id
     WHERE o.order_status <> 'Canceled'
     GROUP BY o.order_date, pc.consumable_id, od.facility_id
), all_purchases AS (
    SELECT sr.date_received AS received_date,
           p.consumable_inventory_item AS consumable_id,
           p.facility_id,
           p.amount::numeric AS purchased_units
      FROM consumable_inventory_purchased p
      JOIN shipment_received sr ON sr.shipment_id = p.shipment_id
     WHERE sr.date_received IS NOT NULL
       AND COALESCE(sr.voided, false) = false
), consumables AS (
    SELECT DISTINCT consumable_inventory_id AS consumable_id,
           facility_id,
           company_id,
           consumable_inventory_item AS item_name
      FROM consumable_inventory
), consumable_first_event AS (
    SELECT consumable_id, facility_id, min(event_date) AS first_event
      FROM (
          SELECT consumable_id, facility_id, inventory_date AS event_date FROM consumable_inventory_history
          UNION ALL
          SELECT consumable_id, facility_id, received_date FROM all_purchases
          UNION ALL
          SELECT consumable_id, facility_id, usage_date FROM all_usage
      ) events
     GROUP BY consumable_id, facility_id
), date_spine AS (
    SELECT c.consumable_id,
           c.facility_id,
           c.company_id,
           c.item_name,
           gs.month_start::date AS month_start
      FROM consumables c
      JOIN consumable_first_event fe ON fe.consumable_id = c.consumable_id AND fe.facility_id = c.facility_id
      JOIN LATERAL generate_series(
               date_trunc('month', fe.first_event::timestamp),
               date_trunc('month', now()),
               interval '1 month'
           ) gs(month_start) ON true
     WHERE fe.first_event < 'infinity'::date
)
SELECT (ds.facility_id || '_' || ds.consumable_id || '_') || ds.month_start AS month_stock_id,
       ds.month_start,
       ds.consumable_id,
       ds.item_name,
       ds.facility_id,
       ds.company_id,
       GREATEST(0, round(
           COALESCE(anchor.anchor_count, 0)
           + COALESCE(purch.purchased_units, 0)
           - COALESCE(used.units_used, 0),
       0)) AS in_stock
  FROM date_spine ds
  LEFT JOIN LATERAL (
      SELECT h.inventory_date AS anchor_date, h.inventory_count AS anchor_count
        FROM consumable_inventory_history h
       WHERE h.consumable_id = ds.consumable_id
         AND h.facility_id = ds.facility_id
         AND h.inventory_date < (ds.month_start + interval '1 month')::date
       ORDER BY h.inventory_date DESC
       LIMIT 1
  ) anchor ON true
  LEFT JOIN LATERAL (
      SELECT COALESCE(sum(ap.purchased_units), 0) AS purchased_units
        FROM all_purchases ap
       WHERE ap.consumable_id = ds.consumable_id
         AND ap.facility_id = ds.facility_id
         AND ap.received_date > COALESCE(anchor.anchor_date, '2000-01-01'::date)
         AND ap.received_date < (ds.month_start + interval '1 month')::date
  ) purch ON true
  LEFT JOIN LATERAL (
      SELECT COALESCE(sum(au.units_used), 0) AS units_used
        FROM all_usage au
       WHERE au.consumable_id = ds.consumable_id
         AND au.facility_id = ds.facility_id
         AND au.usage_date > COALESCE(anchor.anchor_date, '2000-01-01'::date)
         AND au.usage_date < (ds.month_start + interval '1 month')::date
  ) used ON true
WITH DATA;

CREATE UNIQUE INDEX idx_monthly_consumable_stock_id
    ON public.monthly_consumable_stock_by_item (month_stock_id);

CREATE INDEX idx_monthly_consumable_stock_consumable_facility
    ON public.monthly_consumable_stock_by_item (consumable_id, facility_id);

-- ── 3. Hourly pg_cron refresh jobs ──────────────────────────────────────────

SELECT cron.schedule(
    'refresh_weekly_coffee_stock',
    '5 * * * *',
    'REFRESH MATERIALIZED VIEW CONCURRENTLY public.weekly_coffee_stock_by_origin'
);

SELECT cron.schedule(
    'refresh_monthly_consumable_stock',
    '10 * * * *',
    'REFRESH MATERIALIZED VIEW CONCURRENTLY public.monthly_consumable_stock_by_item'
);
