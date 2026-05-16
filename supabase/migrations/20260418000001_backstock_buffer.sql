-- 00216: Backstock buffer
--
-- Adds a per-facility "backstock buffer" — a percentage of the 6-week rolling
-- order average that is added on top of each recipe's roast target so the
-- roaster carries forward extra stock for the next week / emergencies.
--
-- The buffer is a fixed multiplier applied to the AVERAGE (not current open
-- orders), so the displayed "Still to Roast" numbers don't shift every time
-- a new order comes in.
--
-- Storage:
--   standard_parameters('backstock_buffer_pct') — global default = 0
--   company_parameters('backstock_buffer_pct', facility_id) — per-facility
--
-- Schema:
--   roast_log.is_buffer — true when the row was created by Load From Queue
--                         to fulfill the buffer portion (vs the primary need).
--                         Lets the UI mark these rows visually.

BEGIN;

-- 1. Standard parameter row (global default 0%)
INSERT INTO standard_parameters (parameters_id, parameter, amount, data_type)
VALUES ('backstock_buffer_pct', 'Backstock buffer (% of weekly avg)', 0, 'number')
ON CONFLICT (parameters_id) DO NOTHING;

-- 2. roast_log.is_buffer column for the staged-batch buffer marker
ALTER TABLE roast_log
  ADD COLUMN IF NOT EXISTS is_buffer boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN roast_log.is_buffer IS
  'True when the row was created by Load From Queue to satisfy the backstock buffer (extra lbs above the primary order/avg need). UI shows a "BS" badge on these rows. Cleared on duplicate.';

-- 3. Recreate roast_detail_by_blend view to expose buffer_target +
--    buffer_left so the Still to Roast tables can show the inline split
--    without an extra query. Also includes the buffer in roasted_left so
--    every consumer that uses the view picks up the buffer math.
CREATE OR REPLACE VIEW roast_detail_by_blend AS
WITH facility_params AS (
  SELECT f.facility_id,
    f.company_id,
    COALESCE(NULLIF(f.time_zone, ''::text), 'Pacific/Honolulu'::text) AS timezone,
    COALESCE((
      SELECT cp.value_number::integer
      FROM company_parameters cp
      WHERE cp.parameter_id = 'RF1iFWjOh7'::text AND cp.facility_id = f.facility_id
      LIMIT 1
    ), 4) AS roast_reset_day,
    COALESCE((
      SELECT cp.value_number::integer
      FROM company_parameters cp
      WHERE cp.parameter_id = 'orders_reset_day'::text AND cp.facility_id = f.facility_id
      LIMIT 1
    ), (SELECT sp.amount::integer FROM standard_parameters sp WHERE sp.parameters_id = 'orders_reset_day'::text LIMIT 1), 6) AS orders_reset_day,
    COALESCE((
      SELECT cp.value_number
      FROM company_parameters cp
      WHERE cp.parameter_id = '761fd894'::text AND cp.facility_id = f.facility_id
      LIMIT 1
    ), 25::numeric) AS charge_weight,
    COALESCE((
      SELECT cp.value_number
      FROM company_parameters cp
      WHERE cp.parameter_id = '1de271df'::text AND cp.facility_id = f.facility_id
      LIMIT 1
    ), (SELECT sp.amount FROM standard_parameters sp WHERE sp.parameters_id = '1de271df'::text LIMIT 1), 0.82) AS retention_rate,
    -- New: backstock buffer percentage. Per-facility override or global default.
    COALESCE((
      SELECT cp.value_number
      FROM company_parameters cp
      WHERE cp.parameter_id = 'backstock_buffer_pct'::text AND cp.facility_id = f.facility_id
      LIMIT 1
    ), (SELECT sp.amount FROM standard_parameters sp WHERE sp.parameters_id = 'backstock_buffer_pct'::text LIMIT 1), 0::numeric) AS backstock_buffer_pct
  FROM facilities f
), calc AS (
  SELECT fp.*,
    (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date - (EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date)::integer - fp.roast_reset_day + 7) % 7 AS roast_week_start,
    (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date - (EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date)::integer - fp.orders_reset_day + 7) % 7 AS orders_week_start
  FROM facility_params fp
), recipe_facility AS (
  SELECT rr.recipe_id,
    rr.retention_factor,
    f.facility_id,
    f.company_id
  FROM roast_recipes rr
  JOIN facilities f ON f.company_id = rr.company_id AND (rr.facility_id IS NULL OR rr.facility_id = f.facility_id)
), per_recipe AS (
  SELECT rf.recipe_id,
    rf.facility_id,
    rf.company_id,
    c.backstock_buffer_pct,
    COALESCE(stock.in_stock_roasted, 0::numeric) AS in_stock_roasted,
    COALESCE(ordered.total_ordered, 0::double precision) AS total_ordered,
    COALESCE(roasted.total_roasted, 0::numeric) AS total_roasted,
    COALESCE(NULLIF(rf.retention_factor, 0::numeric), c.retention_rate) AS retention_rate,
    COALESCE((
      SELECT avg(rl.charge_weight_lbs) AS avg
      FROM (
        SELECT roast_log.charge_weight_lbs
        FROM roast_log
        WHERE roast_log.recipe_id = rf.recipe_id AND roast_log.facility_id = rf.facility_id AND roast_log.charge_weight_lbs > 0::numeric
        ORDER BY roast_log.roast_date DESC
        LIMIT 5
      ) rl
    ), c.charge_weight, 25::numeric) AS effective_charge_weight,
    -- Avg-with-zeros: last 6 ISO weeks of orders (excluding current orders week)
    -- → sum / 6. Used only for the buffer multiplier (and as the basis when the
    -- caller explicitly picks the avg source via Load From Queue). Never
    -- subtracted; never replaces total_ordered for the standard "Still to
    -- Roast" math.
    COALESCE(avg_lbs.avg_weekly_lbs, 0::numeric) AS avg_weekly_lbs
  FROM recipe_facility rf
  JOIN calc c ON c.facility_id = rf.facility_id
  LEFT JOIN LATERAL (
    SELECT COALESCE(sum(rsl.lbs_in_stock), 0::numeric) AS in_stock_roasted
    FROM roast_stock_log rsl
    WHERE rsl.blend_id = rf.recipe_id
      AND rsl.facility_id = rf.facility_id
      AND (rsl.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start
  ) stock ON true
  LEFT JOIN LATERAL (
    SELECT sum(od.roasted_weight) AS total_ordered
    FROM order_details od
    JOIN orders o ON od.order_id = o.order_id
    JOIN products p ON od.product_id = p.product_id
    WHERE p.recipe_id = rf.recipe_id
      AND o.order_status = 'Open'::text
      AND o.facility_id = rf.facility_id
  ) ordered ON true
  LEFT JOIN LATERAL (
    SELECT sum(rl.roasted_weight) AS total_roasted
    FROM roast_log rl
    WHERE rl.recipe_id = rf.recipe_id
      AND rl."charged?" = true
      AND rl.roast_date >= c.roast_week_start
      AND rl.facility_id = rf.facility_id
  ) roasted ON true
  LEFT JOIN LATERAL (
    -- Sum of weekly totals over the last 6 weeks BEFORE the current orders
    -- week. Divides by 6 (always) so weeks with zero orders pull the avg
    -- down honestly instead of being silently dropped.
    SELECT (COALESCE(sum(weekly.lbs), 0::numeric) / 6::numeric) AS avg_weekly_lbs
    FROM (
      SELECT date_trunc('week', o2.order_date) AS wk,
        sum(od2.quantity * COALESCE(p2.weight_lbs, 0::numeric)) AS lbs
      FROM order_details od2
      JOIN orders o2 ON od2.order_id = o2.order_id
      JOIN products p2 ON od2.product_id = p2.product_id
      WHERE p2.recipe_id = rf.recipe_id
        AND o2.facility_id = rf.facility_id
        AND o2.order_status <> 'Canceled'::text
        AND o2.order_date >= (c.orders_week_start - INTERVAL '42 days')
        AND o2.order_date < c.orders_week_start
      GROUP BY 1
    ) weekly
  ) avg_lbs ON true
)
SELECT
  -- ── Existing columns kept in original order so CREATE OR REPLACE works ─
  (recipe_id || '-'::text) || facility_id AS roast_blend_id,
  recipe_id,
  facility_id,
  company_id,
  in_stock_roasted,
  total_ordered,
  total_roasted,
  -- roasted_left now includes the buffer on top of orders. Existing pages
  -- that read this column automatically pick up the buffer.
  GREATEST(
    0::double precision,
    (total_ordered + (avg_weekly_lbs * backstock_buffer_pct / 100::numeric)::double precision)
      - in_stock_roasted::double precision
      - total_roasted::double precision
  ) AS roasted_left,
  GREATEST(
    0::double precision,
    (total_ordered + (avg_weekly_lbs * backstock_buffer_pct / 100::numeric)::double precision)
      - in_stock_roasted::double precision
      - total_roasted::double precision
  ) / NULLIF(retention_rate, 0::numeric)::double precision / NULLIF(effective_charge_weight, 0::numeric)::double precision AS roasts_remaining,
  -- ── New columns appended at the end ────────────────────────────────────
  avg_weekly_lbs,
  backstock_buffer_pct,
  -- Buffer target (lbs to add on top of primary need) = avg × buffer%
  (avg_weekly_lbs * backstock_buffer_pct / 100::numeric) AS buffer_target,
  -- Effective target = primary_need (orders) + buffer
  (total_ordered + (avg_weekly_lbs * backstock_buffer_pct / 100::numeric)::double precision) AS effective_target,
  -- Buffer-only portion of what's left (for the "+ N buf" inline label).
  -- Caps at the buffer_target, doesn't go negative.
  LEAST(
    GREATEST(
      0::double precision,
      (total_ordered + (avg_weekly_lbs * backstock_buffer_pct / 100::numeric)::double precision)
        - in_stock_roasted::double precision
        - total_roasted::double precision
    ),
    (avg_weekly_lbs * backstock_buffer_pct / 100::numeric)::double precision
  ) AS buffer_left
FROM per_recipe pr;

COMMIT;
