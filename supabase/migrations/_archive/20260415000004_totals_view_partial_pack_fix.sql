-- Fix: `totals.left_to_pack` and `totals.open_backlog` missed Open line items on
-- partially-packed orders. The view required `o.order_status = 'Open'` AND
-- `od.item_status = 'Open'`, so when a user flips an order to Packed but then
-- unchecks a single line item (back to item_status='Open'), that item was not
-- counted as unpacked. Drop the order_status='Open' requirement — the per-item
-- status is authoritative. Exclude Canceled orders.

CREATE OR REPLACE VIEW totals AS
WITH facility_params AS (
  SELECT f.facility_id,
    f.company_id,
    COALESCE(NULLIF(f.time_zone, ''::text), 'Pacific/Honolulu'::text) AS timezone,
    COALESCE(
      (SELECT cp.value_number::integer FROM company_parameters cp
         WHERE cp.parameter_id = 'orders_reset_day' AND cp.facility_id = f.facility_id LIMIT 1),
      (SELECT sp.amount::integer FROM standard_parameters sp
         WHERE sp.parameters_id = 'orders_reset_day' LIMIT 1),
      6
    ) AS orders_reset_day
  FROM facilities f
), calc AS (
  SELECT fp.facility_id,
    fp.company_id,
    fp.timezone,
    (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date
      - (EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date)::integer
         - fp.orders_reset_day + 7) % 7 AS orders_week_start
  FROM facility_params fp
), product_facility AS (
  SELECT p.product_id, f.facility_id, f.company_id
  FROM products p
  JOIN facilities f
    ON p.company_id = f.company_id
   AND (p.facility_id IS NULL OR p.facility_id = f.facility_id)
)
SELECT (pf.product_id || '-'::text) || pf.facility_id AS totals_id,
  pf.product_id,
  pf.facility_id,
  pf.company_id,
  COALESCE((SELECT sum(od.quantity) FROM order_details od
              JOIN orders o ON od.order_id = o.order_id
             WHERE od.product_id = pf.product_id
               AND o.order_date >= c.orders_week_start
               AND o.facility_id = pf.facility_id
               AND o.order_status <> 'Canceled'), 0::numeric) AS total,
  -- left_to_pack: any Open line item, regardless of the order's header status
  -- (Canceled still excluded so canceled items don't pollute the bucket).
  COALESCE((SELECT sum(od.quantity) FROM order_details od
              JOIN orders o ON od.order_id = o.order_id
             WHERE od.product_id = pf.product_id
               AND od.item_status = 'Open'
               AND o.facility_id = pf.facility_id
               AND o.order_status <> 'Canceled'), 0::numeric) AS left_to_pack,
  -- open_backlog: Open line items dated before this week
  COALESCE((SELECT sum(od.quantity) FROM order_details od
              JOIN orders o ON od.order_id = o.order_id
             WHERE od.product_id = pf.product_id
               AND od.item_status = 'Open'
               AND o.order_date < c.orders_week_start
               AND o.facility_id = pf.facility_id
               AND o.order_status <> 'Canceled'), 0::numeric) AS open_backlog,
  COALESCE((SELECT sum(od.quantity) FROM order_details od
              JOIN orders o ON od.order_id = o.order_id
             WHERE od.product_id = pf.product_id
               AND od.item_status = 'Packed'
               AND o.order_date >= c.orders_week_start
               AND o.facility_id = pf.facility_id
               AND o.order_status <> 'Canceled'), 0::numeric) AS packed_qty,
  COALESCE((SELECT sum(od.quantity) FROM order_details od
              JOIN orders o ON od.order_id = o.order_id
             WHERE od.product_id = pf.product_id
               AND o.order_status = 'Delivered'
               AND o.order_date >= c.orders_week_start
               AND o.facility_id = pf.facility_id), 0::numeric) AS delivered_qty,
  COALESCE((SELECT avg(sub.weekly_sum) FROM (
    SELECT sum(od2.quantity) AS weekly_sum
    FROM order_details od2
    JOIN orders o2 ON od2.order_id = o2.order_id
    WHERE od2.product_id = pf.product_id
      AND o2.order_date >= (c.orders_week_start - INTERVAL '42 days')
      AND o2.order_date < c.orders_week_start
      AND o2.facility_id = pf.facility_id
      AND o2.order_status <> 'Canceled'
    GROUP BY date_trunc('week', o2.order_date::timestamptz)
  ) sub), 0::numeric) AS recent_avg_week
FROM product_facility pf
JOIN calc c ON c.facility_id = pf.facility_id;
