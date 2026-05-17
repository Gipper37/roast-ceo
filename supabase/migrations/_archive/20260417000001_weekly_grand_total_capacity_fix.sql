-- weekly_grand_total: fix capacity calculation so the facility-level
-- roast_capacity_hrs parameter behaves as a TOTAL ceiling, not as a
-- per-roaster default that gets multiplied by the # of active roasters.
--
-- Before: SUM(COALESCE(ru.capacity_hrs_per_week, facility_capacity_hrs))
--   For SHC with 2 active roasters and no per-unit overrides:
--   35 + 35 = 70 total → 7.88 hrs roasted shows as 11.3% (was 22.5% intended).
--
-- After:
--   - Sum per-roaster capacity values that are explicitly SET (NULL = 0).
--   - If sum > 0, use it. Otherwise fall back to the facility-level value.
-- This way the facility default is the per-facility total, and per-roaster
-- overrides sum independently when populated.

CREATE OR REPLACE VIEW weekly_grand_total AS
WITH facility_config AS (
  SELECT
    f.facility_id,
    f.company_id,
    COALESCE(NULLIF(f.time_zone, ''), 'UTC') AS timezone,
    COALESCE(
      (SELECT cp.value_number::integer FROM company_parameters cp
        WHERE cp.parameter_id = 'RF1iFWjOh7' AND cp.facility_id = f.facility_id LIMIT 1),
      (SELECT sp.amount::integer FROM standard_parameters sp WHERE sp.parameters_id = 'RF1iFWjOh7' LIMIT 1),
      4
    ) AS roast_target_day,
    COALESCE(
      (SELECT cp.value_number FROM company_parameters cp
        WHERE cp.parameter_id = '1de271df' AND cp.facility_id = f.facility_id LIMIT 1),
      0.82
    ) AS retention_rate,
    COALESCE(
      (SELECT cp.value_number::integer FROM company_parameters cp
        WHERE cp.parameter_id = 'orders_reset_day' AND cp.facility_id = f.facility_id LIMIT 1),
      (SELECT sp.amount::integer FROM standard_parameters sp WHERE sp.parameters_id = 'orders_reset_day' LIMIT 1),
      6
    ) AS orders_reset_day,
    COALESCE(
      (SELECT cp.value_number FROM company_parameters cp
        WHERE cp.parameter_id = 'roast_capacity_hrs' AND cp.facility_id = f.facility_id LIMIT 1),
      (SELECT sp.amount FROM standard_parameters sp WHERE sp.parameters_id = 'roast_capacity_hrs' LIMIT 1),
      35::numeric
    ) AS facility_capacity_hrs
  FROM facilities f
), calc AS (
  SELECT
    fc.facility_id,
    fc.company_id,
    fc.retention_rate,
    fc.facility_capacity_hrs,
    -- Sum only roasters that have an explicit per-unit capacity. If none do,
    -- the facility-level value IS the total (no multiplication by roaster count).
    COALESCE(
      NULLIF(
        (SELECT sum(ru.capacity_hrs_per_week)
           FROM roaster_units ru
          WHERE ru.facility_id = fc.facility_id
            AND ru.is_active = true
            AND ru.capacity_hrs_per_week IS NOT NULL),
        0::numeric
      ),
      fc.facility_capacity_hrs
    ) AS total_capacity_hrs,
    (CURRENT_TIMESTAMP AT TIME ZONE fc.timezone)::date
      - (EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fc.timezone)::date)::integer
         - fc.orders_reset_day + 7) % 7 AS order_week_start,
    (CURRENT_TIMESTAMP AT TIME ZONE fc.timezone)::date
      - (EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fc.timezone)::date)::integer
         - fc.roast_target_day + 7) % 7 AS roast_week_start
  FROM facility_config fc
)
SELECT
  facility_id AS open_order_total_id,
  facility_id,
  company_id,
  COALESCE(
    (SELECT sum(od.roasted_weight)
       FROM order_details od
       JOIN orders o ON od.order_id = o.order_id
      WHERE o.order_date >= c.order_week_start
        AND o.facility_id = c.facility_id
        AND o.order_status <> 'Canceled'),
    0::double precision
  ) AS total_ordered_roasted,
  COALESCE(
    (SELECT sum(od.roasted_weight)
       FROM order_details od
       JOIN orders o ON od.order_id = o.order_id
      WHERE o.order_date >= c.order_week_start
        AND o.facility_id = c.facility_id
        AND o.order_status <> 'Canceled'),
    0::double precision
  ) / NULLIF(c.retention_rate, 0::numeric)::double precision AS total_ordered_green,
  COALESCE(
    (SELECT sum(rl.roasted_weight)
       FROM roast_log rl
      WHERE rl."charged?" = true
        AND rl.roast_date >= c.roast_week_start
        AND rl.facility_id = c.facility_id),
    0::numeric
  ) AS total_roasted,
  COALESCE(
    (SELECT sum(rl.charge_weight_lbs)
       FROM roast_log rl
      WHERE rl."charged?" = true
        AND rl.roast_date >= c.roast_week_start
        AND rl.facility_id = c.facility_id),
    0::numeric
  ) AS total_roasted_green,
  (SELECT max(rl.batches_since_chaff) FROM roast_log rl WHERE rl.facility_id = c.facility_id) AS batches_since_chaff,
  COALESCE(
    (SELECT count(DISTINCT o.order_id)
       FROM orders o
      WHERE o.order_date >= c.order_week_start
        AND o.facility_id = c.facility_id
        AND o.order_status <> 'Canceled'),
    0::bigint
  ) AS order_count,
  COALESCE(
    (SELECT sum(od.quantity)
       FROM order_details od
       JOIN orders o ON od.order_id = o.order_id
      WHERE o.order_date >= c.order_week_start
        AND o.facility_id = c.facility_id
        AND o.order_status <> 'Canceled'),
    0::numeric
  ) AS products_sold,
  COALESCE(
    (SELECT count(*) FROM roast_log rl
      WHERE rl."charged?" = true
        AND rl.roast_date >= c.roast_week_start
        AND rl.facility_id = c.facility_id),
    0::bigint
  ) AS roast_count,
  round(
    COALESCE(
      (SELECT count(*) FROM roast_log rl
        WHERE rl."charged?" = true
          AND rl.roast_date >= c.roast_week_start
          AND rl.facility_id = c.facility_id),
      0::bigint
    )::numeric * COALESCE(
      (SELECT avg(gaps.gap_minutes)
         FROM (SELECT EXTRACT(epoch FROM roast_log.roast_date - lag(roast_log.roast_date)
                                OVER (PARTITION BY roast_log.roaster_unit_id ORDER BY roast_log.roast_date)) / 60.0 AS gap_minutes
                 FROM roast_log
                WHERE roast_log."charged?" = true
                  AND roast_log.roast_date >= c.roast_week_start
                  AND roast_log.facility_id = c.facility_id) gaps
        WHERE gaps.gap_minutes > 0::numeric AND gaps.gap_minutes <= 25::numeric),
      0::numeric
    ) / 60.0,
    2
  ) AS roasting_hours,
  round(
    COALESCE(
      (SELECT count(*) FROM roast_log rl
        WHERE rl."charged?" = true
          AND rl.roast_date >= c.roast_week_start
          AND rl.facility_id = c.facility_id),
      0::bigint
    )::numeric * COALESCE(
      (SELECT avg(gaps.gap_minutes)
         FROM (SELECT EXTRACT(epoch FROM roast_log.roast_date - lag(roast_log.roast_date)
                                OVER (PARTITION BY roast_log.roaster_unit_id ORDER BY roast_log.roast_date)) / 60.0 AS gap_minutes
                 FROM roast_log
                WHERE roast_log."charged?" = true
                  AND roast_log.roast_date >= c.roast_week_start
                  AND roast_log.facility_id = c.facility_id) gaps
        WHERE gaps.gap_minutes > 0::numeric AND gaps.gap_minutes <= 25::numeric),
      0::numeric
    ) / 60.0 / NULLIF(c.total_capacity_hrs, 0::numeric) * 100::numeric,
    1
  ) AS capacity_pct
FROM calc c;
