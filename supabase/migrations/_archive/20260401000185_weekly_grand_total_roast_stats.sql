-- Add roast_count and roasting_hours to weekly_grand_total.
-- roasting_hours = roast_count × avg interval between consecutive charged roasts
--                  (gaps > 25 min excluded as they represent breaks, not roast cycles)

CREATE OR REPLACE VIEW public.weekly_grand_total AS
WITH facility_config AS (
    SELECT f.facility_id,
           f.company_id,
           COALESCE(NULLIF(f.time_zone, ''), 'UTC') AS timezone,
           COALESCE((SELECT cp.value_number::integer
                       FROM company_parameters cp
                      WHERE cp.parameter_id = 'RF1iFWjOh7' AND cp.facility_id = f.facility_id
                      LIMIT 1), 1) AS roast_target_day,
           COALESCE((SELECT cp.value_number
                       FROM company_parameters cp
                      WHERE cp.parameter_id = '1de271df' AND cp.facility_id = f.facility_id
                      LIMIT 1), 0.82) AS retention_rate,
           COALESCE((SELECT cp.value_number::integer
                       FROM company_parameters cp
                      WHERE cp.parameter_id = 'orders_reset_day' AND cp.facility_id = f.facility_id
                      LIMIT 1),
                    (SELECT sp.amount::integer
                       FROM standard_parameters sp
                      WHERE sp.parameters_id = 'orders_reset_day'
                      LIMIT 1), 6) AS orders_reset_day
      FROM facilities f
), calc AS (
    SELECT fc.facility_id,
           fc.company_id,
           fc.retention_rate,
           (CURRENT_TIMESTAMP AT TIME ZONE fc.timezone)::date
               - ((EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fc.timezone)::date)::integer
                   - fc.orders_reset_day + 7) % 7) AS order_week_start,
           (CURRENT_TIMESTAMP AT TIME ZONE fc.timezone)::date
               - ((EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fc.timezone)::date)::integer
                   - fc.roast_target_day + 7) % 7) AS roast_week_start
      FROM facility_config fc
)
SELECT facility_id AS open_order_total_id,
       facility_id,
       company_id,
       COALESCE((SELECT sum(od.roasted_weight)
                   FROM order_details od
                   JOIN orders o ON od.order_id = o.order_id
                  WHERE o.order_date >= c.order_week_start
                    AND o.facility_id = c.facility_id
                    AND o.order_status <> 'Canceled'), 0) AS total_ordered_roasted,
       COALESCE((SELECT sum(od.roasted_weight)
                   FROM order_details od
                   JOIN orders o ON od.order_id = o.order_id
                  WHERE o.order_date >= c.order_week_start
                    AND o.facility_id = c.facility_id
                    AND o.order_status <> 'Canceled'), 0)
           / NULLIF(retention_rate, 0)                    AS total_ordered_green,
       COALESCE((SELECT sum(rl.roasted_weight)
                   FROM roast_log rl
                  WHERE rl."charged?" = true
                    AND rl.roast_date >= c.roast_week_start
                    AND rl.facility_id = c.facility_id), 0) AS total_roasted,
       COALESCE((SELECT sum(rl.charge_weight_lbs)
                   FROM roast_log rl
                  WHERE rl."charged?" = true
                    AND rl.roast_date >= c.roast_week_start
                    AND rl.facility_id = c.facility_id), 0) AS total_roasted_green,
       (SELECT MAX(rl.batches_since_chaff)
          FROM roast_log rl
         WHERE rl.facility_id = c.facility_id)             AS batches_since_chaff,
       COALESCE((SELECT count(DISTINCT o.order_id)
                   FROM orders o
                  WHERE o.order_date >= c.order_week_start
                    AND o.facility_id = c.facility_id
                    AND o.order_status <> 'Canceled'), 0)  AS order_count,
       COALESCE((SELECT sum(od.quantity)
                   FROM order_details od
                   JOIN orders o ON od.order_id = o.order_id
                  WHERE o.order_date >= c.order_week_start
                    AND o.facility_id = c.facility_id
                    AND o.order_status <> 'Canceled'), 0)  AS products_sold,
       -- roast_count: charged roasts this week
       COALESCE((SELECT count(*)
                   FROM roast_log rl
                  WHERE rl."charged?" = true
                    AND rl.roast_date >= c.roast_week_start
                    AND rl.facility_id = c.facility_id), 0) AS roast_count,
       -- roasting_hours: roast_count × avg interval (gaps ≤ 25 min only) / 60
       ROUND(
           COALESCE((SELECT count(*)
                       FROM roast_log rl
                      WHERE rl."charged?" = true
                        AND rl.roast_date >= c.roast_week_start
                        AND rl.facility_id = c.facility_id), 0)
           *
           COALESCE((
               SELECT AVG(gap_minutes)
                 FROM (
                     SELECT EXTRACT(EPOCH FROM (
                                roast_date
                                - LAG(roast_date) OVER (ORDER BY roast_date)
                            )) / 60.0 AS gap_minutes
                       FROM roast_log
                      WHERE "charged?" = true
                        AND roast_date >= c.roast_week_start
                        AND facility_id = c.facility_id
                 ) gaps
                WHERE gap_minutes > 0
                  AND gap_minutes <= 25
           ), 0)
           / 60.0
       , 2) AS roasting_hours
  FROM calc c;
