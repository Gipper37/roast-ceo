-- 00220: roast_detail_by_blend lbs side uses per-component allocation
--        for Post-Blend recipes (matches the old roast_batches_remaining
--        attribution that was lost when that view got dropped).
--
-- Problem: today's view uses a strict recipe_id match for total_roasted /
-- in_stock_roasted. That breaks Post-Blend recipes both ways:
--
--   * Roast Brazil tagged recipe="Et Al" (50% Brazil + 50% Other), 20 lbs:
--     - view counts 20 lbs as if Et Al blend was already finished
--     - roasted_left under-reports remaining work (other component ignored)
--
--   * Roast Brazil tagged recipe="Brazil" while Et Al also needs Brazil:
--     - view sees 0 lbs roasted toward Et Al even though the bin has Brazil
--       that can satisfy Et Al's Brazil component
--
-- New behavior for Post-Blend recipes that have recipe_components rows:
--   per-component demand   = rc.percentage × (recipe demand + recipe buffer)
--   per-component stock    = SUM(roast_stock_log) for the origin
--                            + rc.percentage × SUM(roast_stock_log) for the blend
--                            (last-week per-component overage when zero)
--   per-component roasted  = SUM(roast_log.roasted_weight) for the origin,
--                            ANY recipe_id this roast week (cross-recipe)
--   per-component remaining = max(0, demand − stock − roasted)
--
-- Recipe-level columns are aggregated up:
--   in_stock_roasted = SUM(LEAST(component_demand, component_stock))
--   total_roasted    = SUM(LEAST(remaining_demand_after_stock, component_roasted))
--   roasted_left     = SUM(component_remaining)
--   roasts_remaining = SUM(CEIL(component_remaining / retention
--                                                  / per-origin charge weight))
--
-- Pre-Blend recipes and Post-Blend recipes with no recipe_components keep
-- the recipe-level direct logic from migration 20260418000003.
--
-- Note: the cross-recipe origin pool can be claimed by multiple blends that
-- share the same component (matches the permissive model the lost
-- roast_batches_remaining view used). If you want strict allocation
-- (one origin lb satisfies one blend lb only), that requires a real
-- bin/lot-tracking model — out of scope here.

BEGIN;

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
    rr.roast_type,
    rr.retention_factor,
    f.facility_id,
    f.company_id
  FROM roast_recipes rr
  JOIN facilities f ON f.company_id = rr.company_id AND (rr.facility_id IS NULL OR rr.facility_id = f.facility_id)
),
-- ── Branch A: Pre-Blend OR Post-Blend without recipe_components.
--    Recipe-level direct totals (today's logic, preserved verbatim).
recipe_level AS (
  SELECT rf.recipe_id,
    rf.facility_id,
    rf.company_id,
    c.backstock_buffer_pct,
    COALESCE(
      NULLIF(stock.in_stock_roasted, 0::numeric),
      GREATEST(0::numeric, COALESCE(last_wk_roasted.lbs, 0::numeric) - COALESCE(last_wk_ordered.lbs, 0::numeric))
    ) AS in_stock_roasted,
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
    SELECT COALESCE(sum(rl.roasted_weight), 0::numeric) AS lbs
    FROM roast_log rl
    WHERE rl.recipe_id = rf.recipe_id
      AND rl."charged?" = true
      AND rl.facility_id = rf.facility_id
      AND rl.roast_date >= (c.roast_week_start - INTERVAL '7 days')
      AND rl.roast_date < c.roast_week_start
  ) last_wk_roasted ON true
  LEFT JOIN LATERAL (
    SELECT COALESCE(sum(od.roasted_weight), 0::double precision)::numeric AS lbs
    FROM order_details od
    JOIN orders o ON od.order_id = o.order_id
    JOIN products p ON od.product_id = p.product_id
    WHERE p.recipe_id = rf.recipe_id
      AND o.facility_id = rf.facility_id
      AND o.order_status <> 'Canceled'::text
      AND o.order_date >= (c.orders_week_start - INTERVAL '7 days')
      AND o.order_date < c.orders_week_start
  ) last_wk_ordered ON true
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
  WHERE rf.roast_type = 'Pre-Blend'::text
     OR NOT EXISTS (
       SELECT 1 FROM recipe_components rc
       WHERE rc.recipe_id = rf.recipe_id
     )
),
-- ── Branch B: Post-Blend WITH recipe_components.
--    Walk components, allocate per-origin, then aggregate back to recipe rows.
component_raw AS (
  SELECT rf.recipe_id,
    rf.facility_id,
    rf.company_id,
    rc.coffee_item AS origin_id,
    COALESCE(rc.percentage, 0::numeric) AS percentage,
    c.backstock_buffer_pct,
    COALESCE(NULLIF(rf.retention_factor, 0::numeric), c.retention_rate) AS retention_rate,
    c.charge_weight AS facility_charge_weight,
    COALESCE(ordered.total_ordered, 0::double precision)::numeric AS recipe_demand,
    COALESCE(stock_origin.lbs, 0::numeric)
      + COALESCE(rc.percentage, 0::numeric) * COALESCE(stock_blend.lbs, 0::numeric) AS this_week_stock,
    GREATEST(
      0::numeric,
      COALESCE(last_wk_origin_roasted.lbs, 0::numeric)
        - COALESCE(rc.percentage, 0::numeric) * COALESCE(last_wk_recipe_ordered.lbs, 0::numeric)
    ) AS last_week_overage,
    COALESCE(origin_roasted.lbs, 0::numeric) AS component_roasted,
    COALESCE(charge_w.avg_w, c.charge_weight, 25::numeric) AS component_charge_weight,
    COALESCE(avg_lbs.avg_weekly_lbs, 0::numeric) AS recipe_avg_weekly_lbs
  FROM recipe_facility rf
  JOIN recipe_components rc ON rc.recipe_id = rf.recipe_id
  JOIN calc c ON c.facility_id = rf.facility_id
  LEFT JOIN LATERAL (
    -- Recipe-level open order demand (same number all components share)
    SELECT sum(od.roasted_weight) AS total_ordered
    FROM order_details od
    JOIN orders o ON od.order_id = o.order_id
    JOIN products p ON od.product_id = p.product_id
    WHERE p.recipe_id = rf.recipe_id
      AND o.order_status = 'Open'::text
      AND o.facility_id = rf.facility_id
  ) ordered ON true
  LEFT JOIN LATERAL (
    -- This-week origin-level stock (manual log entries against the origin)
    SELECT COALESCE(sum(rsl.lbs_in_stock), 0::numeric) AS lbs
    FROM roast_stock_log rsl
    WHERE rsl.origin_id = rc.coffee_item
      AND rsl.facility_id = rf.facility_id
      AND (rsl.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start
  ) stock_origin ON true
  LEFT JOIN LATERAL (
    -- This-week blend-level stock (assembled blend logged against this recipe)
    SELECT COALESCE(sum(rsl.lbs_in_stock), 0::numeric) AS lbs
    FROM roast_stock_log rsl
    WHERE rsl.blend_id = rf.recipe_id
      AND rsl.facility_id = rf.facility_id
      AND (rsl.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start
  ) stock_blend ON true
  LEFT JOIN LATERAL (
    -- Last-week origin roasted (any recipe) — used for overage fallback
    SELECT COALESCE(sum(rl.roasted_weight), 0::numeric) AS lbs
    FROM roast_log rl
    WHERE rl.origin_id = rc.coffee_item
      AND rl."charged?" = true
      AND rl.facility_id = rf.facility_id
      AND rl.roast_date >= (c.roast_week_start - INTERVAL '7 days')
      AND rl.roast_date < c.roast_week_start
  ) last_wk_origin_roasted ON true
  LEFT JOIN LATERAL (
    -- Last-week recipe ordered (used to size the per-component overage)
    SELECT COALESCE(sum(od.roasted_weight), 0::double precision)::numeric AS lbs
    FROM order_details od
    JOIN orders o ON od.order_id = o.order_id
    JOIN products p ON od.product_id = p.product_id
    WHERE p.recipe_id = rf.recipe_id
      AND o.facility_id = rf.facility_id
      AND o.order_status <> 'Canceled'::text
      AND o.order_date >= (c.orders_week_start - INTERVAL '7 days')
      AND o.order_date < c.orders_week_start
  ) last_wk_recipe_ordered ON true
  LEFT JOIN LATERAL (
    -- This-week ALL roasts of this origin (recipe-tag agnostic). This is
    -- the cross-recipe coverage rule: a Brazil batch counts toward every
    -- blend that needs Brazil, regardless of which recipe was selected
    -- when the roast was logged.
    SELECT COALESCE(sum(rl.roasted_weight), 0::numeric) AS lbs
    FROM roast_log rl
    WHERE rl.origin_id = rc.coffee_item
      AND rl."charged?" = true
      AND rl.roast_date >= c.roast_week_start
      AND rl.facility_id = rf.facility_id
  ) origin_roasted ON true
  LEFT JOIN LATERAL (
    -- Per-origin effective charge weight (avg of last 5 batches of this
    -- origin). Falls back to facility default if the origin has no history.
    SELECT avg(sub.charge_weight_lbs) AS avg_w
    FROM (
      SELECT charge_weight_lbs
      FROM roast_log
      WHERE origin_id = rc.coffee_item
        AND facility_id = rf.facility_id
        AND charge_weight_lbs > 0::numeric
      ORDER BY roast_date DESC
      LIMIT 5
    ) sub
  ) charge_w ON true
  LEFT JOIN LATERAL (
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
  WHERE rf.roast_type IS DISTINCT FROM 'Pre-Blend'::text
    AND EXISTS (
      SELECT 1 FROM recipe_components rc2
      WHERE rc2.recipe_id = rf.recipe_id
    )
), component_alloc AS (
  -- Allocate the per-component effective stock (with last-week overage
  -- fallback) and split demand into stock-applied + roasted-applied +
  -- still-needed buckets. Buffer is baked into demand so the recipe-level
  -- columns balance: in_stock + roasted + remaining = demand_with_buffer.
  SELECT cr.*,
    (cr.recipe_avg_weekly_lbs * cr.backstock_buffer_pct / 100::numeric) AS recipe_buffer_target,
    -- Per-component demand WITH buffer (rc.percentage of total recipe need)
    cr.percentage * (
      cr.recipe_demand
      + (cr.recipe_avg_weekly_lbs * cr.backstock_buffer_pct / 100::numeric)
    ) AS component_demand_buf,
    -- Per-component demand WITHOUT buffer (for buffer_left calculation)
    cr.percentage * cr.recipe_demand AS component_demand_orders,
    -- This-week stock with last-week overage fallback (per component)
    COALESCE(NULLIF(cr.this_week_stock, 0::numeric), cr.last_week_overage) AS effective_stock
  FROM component_raw cr
), component_split AS (
  SELECT ca.*,
    LEAST(ca.component_demand_buf, ca.effective_stock) AS applied_stock,
    GREATEST(0::numeric, ca.component_demand_buf - ca.effective_stock) AS demand_after_stock
  FROM component_alloc ca
), component_final AS (
  SELECT cs.*,
    LEAST(cs.demand_after_stock, cs.component_roasted) AS applied_roasted,
    GREATEST(0::numeric, cs.demand_after_stock - cs.component_roasted) AS component_remaining,
    -- "Orders-only" remaining (without buffer) — used to derive buffer_left
    GREATEST(
      0::numeric,
      cs.component_demand_orders - cs.effective_stock - cs.component_roasted
    ) AS component_remaining_orders_only
  FROM component_split cs
), post_blend_recipe AS (
  SELECT recipe_id, facility_id, company_id,
    MAX(retention_rate) AS retention_rate,
    MAX(recipe_demand)::double precision AS total_ordered,
    SUM(applied_stock) AS in_stock_roasted,
    SUM(applied_roasted) AS total_roasted,
    SUM(component_remaining)::double precision AS roasted_left,
    -- Per-component CEIL of batches, summed up (matches the old
    -- roast_batches_remaining behaviour). NULLIF guards prevent 0/0.
    SUM(
      CEIL(
        component_remaining
        / NULLIF(retention_rate, 0::numeric)
        / NULLIF(component_charge_weight, 0::numeric)
      )
    )::double precision AS roasts_remaining,
    MAX(recipe_avg_weekly_lbs) AS avg_weekly_lbs,
    MAX(backstock_buffer_pct) AS backstock_buffer_pct,
    MAX(recipe_buffer_target) AS buffer_target,
    -- buffer_left = SUM of per-component "extra remaining beyond order need"
    -- capped at recipe-level buffer_target so it can't exceed the buffer pool.
    LEAST(
      MAX(recipe_buffer_target)::double precision,
      GREATEST(0::numeric, SUM(component_remaining) - SUM(component_remaining_orders_only))::double precision
    ) AS buffer_left_calc
  FROM component_final
  GROUP BY recipe_id, facility_id, company_id
), unioned AS (
  -- Pre-Blend / no-components branch: today's recipe-level math with
  -- buffer added to demand, exactly as migration 20260418000003 had it.
  SELECT
    rl.recipe_id,
    rl.facility_id,
    rl.company_id,
    rl.in_stock_roasted,
    rl.total_ordered,
    rl.total_roasted,
    GREATEST(
      0::double precision,
      (rl.total_ordered + (rl.avg_weekly_lbs * rl.backstock_buffer_pct / 100::numeric)::double precision)
        - rl.in_stock_roasted::double precision
        - rl.total_roasted::double precision
    ) AS roasted_left,
    GREATEST(
      0::double precision,
      (rl.total_ordered + (rl.avg_weekly_lbs * rl.backstock_buffer_pct / 100::numeric)::double precision)
        - rl.in_stock_roasted::double precision
        - rl.total_roasted::double precision
    ) / NULLIF(rl.retention_rate, 0::numeric)::double precision
      / NULLIF(rl.effective_charge_weight, 0::numeric)::double precision AS roasts_remaining,
    rl.avg_weekly_lbs,
    rl.backstock_buffer_pct,
    (rl.avg_weekly_lbs * rl.backstock_buffer_pct / 100::numeric) AS buffer_target,
    LEAST(
      GREATEST(
        0::double precision,
        (rl.total_ordered + (rl.avg_weekly_lbs * rl.backstock_buffer_pct / 100::numeric)::double precision)
          - rl.in_stock_roasted::double precision
          - rl.total_roasted::double precision
      ),
      (rl.avg_weekly_lbs * rl.backstock_buffer_pct / 100::numeric)::double precision
    ) AS buffer_left
  FROM recipe_level rl
  UNION ALL
  -- Post-Blend with components branch: per-component aggregated.
  SELECT
    pbr.recipe_id,
    pbr.facility_id,
    pbr.company_id,
    pbr.in_stock_roasted,
    pbr.total_ordered,
    pbr.total_roasted,
    pbr.roasted_left,
    pbr.roasts_remaining,
    pbr.avg_weekly_lbs,
    pbr.backstock_buffer_pct,
    pbr.buffer_target,
    pbr.buffer_left_calc AS buffer_left
  FROM post_blend_recipe pbr
)
SELECT
  (recipe_id || '-'::text) || facility_id AS roast_blend_id,
  recipe_id,
  facility_id,
  company_id,
  in_stock_roasted,
  total_ordered,
  total_roasted,
  roasted_left,
  roasts_remaining,
  avg_weekly_lbs,
  backstock_buffer_pct,
  buffer_target,
  (total_ordered + buffer_target::double precision) AS effective_target,
  buffer_left
FROM unioned;

COMMIT;
