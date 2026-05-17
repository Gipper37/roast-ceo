-- 00222: roast_detail_by_blend lbs side uses per-component allocation for
--        Post-Blend recipes. STRICT recipe-tag-respecting (not cross-recipe
--        pooled like the failed 00220).
--
-- ───────────────────────────────────────────────────────────────────────
-- Why this exists
-- ───────────────────────────────────────────────────────────────────────
-- Today's view uses a strict recipe_id match for total_roasted /
-- in_stock_roasted, then derives roasted_left = ordered − stock − roasted.
-- That formula treats EVERY lb tagged with the blend recipe as if it were
-- finished blend, which over-credits when a user roasts one component
-- past its share. Example:
--
--   Et Al = 50 % Brazil + 50 % Other, ordered 50 lbs (component need = 25 ea)
--   User roasts 50 lbs Brazil tagged recipe=Et Al.
--   Today: total_roasted = 50, roasted_left = 0.   ← says you're done.
--          Reality: you still need 25 lbs Other.
--
-- ───────────────────────────────────────────────────────────────────────
-- New behaviour (Post-Blend WITH recipe_components only)
-- ───────────────────────────────────────────────────────────────────────
-- For each (recipe R, component c):
--   component_demand    = c.percentage × (recipe demand + recipe buffer)
--   component_roasted   = SUM(rl.roasted_weight)
--                         WHERE rl.recipe_id = R AND rl.origin_id = c.origin
--                         (this week, charged) — STRICT TAG MATCH
--   component_stock     = blend-tagged stock for R, distributed by c.%
--                         + (blend+origin)-tagged stock that names c.origin
--                         (origin-only stock entries are NOT counted here;
--                         they belong to the origin view)
--   component_remaining = max(0, component_demand − stock − roasted)
--
-- Recipe-level columns are aggregated up:
--   in_stock_roasted = SUM(LEAST(component_demand, effective_stock))
--   total_roasted    = SUM(LEAST(component_demand − applied_stock,
--                                 component_roasted))
--   roasted_left     = SUM(component_remaining)
--   roasts_remaining = SUM(CEIL(component_remaining / retention
--                                                  / per-origin charge weight))
--
-- Pre-Blend recipes and Post-Blend recipes with no recipe_components keep
-- the recipe-level direct logic from migration 00219.
--
-- ───────────────────────────────────────────────────────────────────────
-- Why this is safe (vs the over-crediting that killed 00220 / 00190)
-- ───────────────────────────────────────────────────────────────────────
-- 00220 used cross-recipe origin pooling: any Brazil roast counted toward
-- every blend that uses Brazil. If Brazil was in 3 blends, one Brazil
-- roast got credited 3 times across the system → IS jumped 70→444.
--
-- This migration only counts a roast toward blend R when the roast is
-- explicitly tagged with recipe_id = R. The origin filter is just a
-- per-component partitioning inside that recipe's roasts. No pooling,
-- no double-counting. Worst case: a user mis-tags a roast and it's
-- silently invisible to the intended blend — easy to spot, easy to fix
-- by editing the roast.
--
-- ───────────────────────────────────────────────────────────────────────
-- Trade-off
-- ───────────────────────────────────────────────────────────────────────
-- Origin-level stock (rsl with origin_id set, blend_id null) does NOT
-- contribute to a blend's in_stock here. Rationale: a single bin of
-- Brazil cannot satisfy multiple blends simultaneously, and we have no
-- way to know which blend the user "means" without a tag. Workaround
-- for users who want loose Brazil stock to count toward Et Al: log it
-- with blend_id = Et Al's recipe (and optionally origin_id = Brazil).

BEGIN;

CREATE OR REPLACE VIEW roast_detail_by_blend AS
WITH facility_params AS (
  SELECT f.facility_id,
    f.company_id,
    COALESCE(NULLIF(f.time_zone, ''::text), 'Pacific/Honolulu'::text) AS timezone,
    COALESCE((
      SELECT cp.value_number::integer FROM company_parameters cp
      WHERE cp.parameter_id = 'RF1iFWjOh7'::text AND cp.facility_id = f.facility_id LIMIT 1
    ), 4) AS roast_reset_day,
    COALESCE((
      SELECT cp.value_number::integer FROM company_parameters cp
      WHERE cp.parameter_id = 'orders_reset_day'::text AND cp.facility_id = f.facility_id LIMIT 1
    ), (SELECT sp.amount::integer FROM standard_parameters sp WHERE sp.parameters_id = 'orders_reset_day'::text LIMIT 1), 6) AS orders_reset_day,
    COALESCE((
      SELECT cp.value_number FROM company_parameters cp
      WHERE cp.parameter_id = '761fd894'::text AND cp.facility_id = f.facility_id LIMIT 1
    ), 25::numeric) AS charge_weight,
    COALESCE((
      SELECT cp.value_number FROM company_parameters cp
      WHERE cp.parameter_id = '1de271df'::text AND cp.facility_id = f.facility_id LIMIT 1
    ), (SELECT sp.amount FROM standard_parameters sp WHERE sp.parameters_id = '1de271df'::text LIMIT 1), 0.82) AS retention_rate,
    COALESCE((
      SELECT cp.value_number FROM company_parameters cp
      WHERE cp.parameter_id = 'backstock_buffer_pct'::text AND cp.facility_id = f.facility_id LIMIT 1
    ), (SELECT sp.amount FROM standard_parameters sp WHERE sp.parameters_id = 'backstock_buffer_pct'::text LIMIT 1), 0::numeric) AS backstock_buffer_pct
  FROM facilities f
), calc AS (
  SELECT fp.*,
    (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date - (EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date)::integer - fp.roast_reset_day + 7) % 7 AS roast_week_start,
    (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date - (EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date)::integer - fp.orders_reset_day + 7) % 7 AS orders_week_start
  FROM facility_params fp
), recipe_facility AS (
  SELECT rr.recipe_id, rr.roast_type, rr.retention_factor,
    f.facility_id, f.company_id
  FROM roast_recipes rr
  JOIN facilities f ON f.company_id = rr.company_id AND (rr.facility_id IS NULL OR rr.facility_id = f.facility_id)
),
-- ═══════════════════════════════════════════════════════════════════════
-- Branch A: Pre-Blend OR Post-Blend without recipe_components
-- Recipe-level direct totals (verbatim from migration 00219)
-- ═══════════════════════════════════════════════════════════════════════
recipe_level AS (
  SELECT rf.recipe_id, rf.facility_id, rf.company_id,
    c.backstock_buffer_pct,
    COALESCE(
      NULLIF(stock.in_stock_roasted, 0::numeric),
      GREATEST(0::numeric, COALESCE(last_wk_roasted.lbs, 0::numeric) - COALESCE(last_wk_ordered.lbs, 0::numeric))
    ) AS in_stock_roasted,
    COALESCE(ordered.total_ordered, 0::double precision) AS total_ordered,
    COALESCE(roasted.total_roasted, 0::numeric) AS total_roasted,
    COALESCE(NULLIF(rf.retention_factor, 0::numeric), c.retention_rate) AS retention_rate,
    COALESCE((
      SELECT avg(rl.charge_weight_lbs) FROM (
        SELECT roast_log.charge_weight_lbs FROM roast_log
        WHERE roast_log.recipe_id = rf.recipe_id AND roast_log.facility_id = rf.facility_id AND roast_log.charge_weight_lbs > 0::numeric
        ORDER BY roast_log.roast_date DESC LIMIT 5
      ) rl
    ), c.charge_weight, 25::numeric) AS effective_charge_weight,
    COALESCE(avg_lbs.avg_weekly_lbs, 0::numeric) AS avg_weekly_lbs
  FROM recipe_facility rf
  JOIN calc c ON c.facility_id = rf.facility_id
  LEFT JOIN LATERAL (
    SELECT COALESCE(sum(rsl.lbs_in_stock), 0::numeric) AS in_stock_roasted
    FROM roast_stock_log rsl
    WHERE rsl.blend_id = rf.recipe_id AND rsl.facility_id = rf.facility_id
      AND (rsl.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start
  ) stock ON true
  LEFT JOIN LATERAL (
    SELECT COALESCE(sum(rl.roasted_weight), 0::numeric) AS lbs FROM roast_log rl
    WHERE rl.recipe_id = rf.recipe_id AND rl."charged?" = true AND rl.facility_id = rf.facility_id
      AND rl.roast_date >= (c.roast_week_start - INTERVAL '7 days')
      AND rl.roast_date < c.roast_week_start
  ) last_wk_roasted ON true
  LEFT JOIN LATERAL (
    SELECT COALESCE(sum(od.roasted_weight), 0::double precision)::numeric AS lbs
    FROM order_details od
    JOIN orders o ON od.order_id = o.order_id
    JOIN products p ON od.product_id = p.product_id
    WHERE p.recipe_id = rf.recipe_id AND o.facility_id = rf.facility_id
      AND o.order_status <> 'Canceled'::text
      AND o.order_date >= (c.orders_week_start - INTERVAL '7 days')
      AND o.order_date < c.orders_week_start
  ) last_wk_ordered ON true
  LEFT JOIN LATERAL (
    SELECT sum(od.roasted_weight) AS total_ordered FROM order_details od
    JOIN orders o ON od.order_id = o.order_id
    JOIN products p ON od.product_id = p.product_id
    WHERE p.recipe_id = rf.recipe_id AND o.order_status = 'Open'::text AND o.facility_id = rf.facility_id
  ) ordered ON true
  LEFT JOIN LATERAL (
    SELECT sum(rl.roasted_weight) AS total_roasted FROM roast_log rl
    WHERE rl.recipe_id = rf.recipe_id AND rl."charged?" = true
      AND rl.roast_date >= c.roast_week_start AND rl.facility_id = rf.facility_id
  ) roasted ON true
  LEFT JOIN LATERAL (
    SELECT (COALESCE(sum(weekly.lbs), 0::numeric) / 6::numeric) AS avg_weekly_lbs
    FROM (
      SELECT date_trunc('week', o2.order_date) AS wk,
        sum(od2.quantity * COALESCE(p2.weight_lbs, 0::numeric)) AS lbs
      FROM order_details od2
      JOIN orders o2 ON od2.order_id = o2.order_id
      JOIN products p2 ON od2.product_id = p2.product_id
      WHERE p2.recipe_id = rf.recipe_id AND o2.facility_id = rf.facility_id
        AND o2.order_status <> 'Canceled'::text
        AND o2.order_date >= (c.orders_week_start - INTERVAL '42 days')
        AND o2.order_date < c.orders_week_start
      GROUP BY 1
    ) weekly
  ) avg_lbs ON true
  WHERE rf.roast_type = 'Pre-Blend'::text
     OR NOT EXISTS (SELECT 1 FROM recipe_components rc WHERE rc.recipe_id = rf.recipe_id)
),
-- ═══════════════════════════════════════════════════════════════════════
-- Branch B: Post-Blend WITH recipe_components
-- Per-component allocation, STRICT recipe-tag match (no cross-recipe pooling)
-- ═══════════════════════════════════════════════════════════════════════
component_raw AS (
  SELECT rf.recipe_id, rf.facility_id, rf.company_id,
    rc.coffee_item AS origin_id,
    COALESCE(rc.percentage, 0::numeric) AS percentage,
    c.backstock_buffer_pct,
    COALESCE(NULLIF(rf.retention_factor, 0::numeric), c.retention_rate) AS retention_rate,
    c.charge_weight AS facility_charge_weight,
    COALESCE(ordered.total_ordered, 0::double precision)::numeric AS recipe_demand,
    -- Per-component STOCK (this week):
    --   1) blend-tagged + origin-tagged stock that names this origin → 100 %
    --   2) blend-tagged stock with NO origin (assembled blend) → distribute by c.%
    -- Origin-only stock entries (no blend tag) are NOT counted — they belong
    -- to the origin view because we can't know which blend they're for.
    COALESCE(stock_blend_origin.lbs, 0::numeric)
      + COALESCE(rc.percentage, 0::numeric) * COALESCE(stock_blend_only.lbs, 0::numeric) AS this_week_stock,
    -- Per-component ROASTED (this week, STRICT tag match):
    --   only roasts tagged recipe=R AND origin=c count toward this component
    COALESCE(component_roasted.lbs, 0::numeric) AS component_roasted,
    -- Last-week per-component overage (for the in-stock fallback):
    --   roasted last week with the same strict tag − component's share of
    --   last-week orders. Stays internally consistent.
    GREATEST(
      0::numeric,
      COALESCE(last_wk_component_roasted.lbs, 0::numeric)
        - COALESCE(rc.percentage, 0::numeric) * COALESCE(last_wk_recipe_ordered.lbs, 0::numeric)
    ) AS last_week_overage,
    -- Per-component effective charge weight (avg of last 5 batches that
    -- match BOTH this recipe AND this origin). Falls back to recipe avg,
    -- then origin avg, then facility default.
    COALESCE(charge_w.avg_w, recipe_charge_w.avg_w, origin_charge_w.avg_w, c.charge_weight, 25::numeric) AS component_charge_weight,
    COALESCE(avg_lbs.avg_weekly_lbs, 0::numeric) AS recipe_avg_weekly_lbs
  FROM recipe_facility rf
  JOIN recipe_components rc ON rc.recipe_id = rf.recipe_id
  JOIN calc c ON c.facility_id = rf.facility_id
  LEFT JOIN LATERAL (
    SELECT sum(od.roasted_weight) AS total_ordered FROM order_details od
    JOIN orders o ON od.order_id = o.order_id
    JOIN products p ON od.product_id = p.product_id
    WHERE p.recipe_id = rf.recipe_id AND o.order_status = 'Open'::text AND o.facility_id = rf.facility_id
  ) ordered ON true
  LEFT JOIN LATERAL (
    SELECT COALESCE(sum(rsl.lbs_in_stock), 0::numeric) AS lbs FROM roast_stock_log rsl
    WHERE rsl.blend_id = rf.recipe_id
      AND rsl.origin_id = rc.coffee_item
      AND rsl.facility_id = rf.facility_id
      AND (rsl.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start
  ) stock_blend_origin ON true
  LEFT JOIN LATERAL (
    SELECT COALESCE(sum(rsl.lbs_in_stock), 0::numeric) AS lbs FROM roast_stock_log rsl
    WHERE rsl.blend_id = rf.recipe_id
      AND rsl.origin_id IS NULL
      AND rsl.facility_id = rf.facility_id
      AND (rsl.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start
  ) stock_blend_only ON true
  LEFT JOIN LATERAL (
    -- STRICT tag match: this recipe AND this origin only
    SELECT COALESCE(sum(rl.roasted_weight), 0::numeric) AS lbs FROM roast_log rl
    WHERE rl.recipe_id = rf.recipe_id
      AND rl.origin_id = rc.coffee_item
      AND rl."charged?" = true
      AND rl.roast_date >= c.roast_week_start
      AND rl.facility_id = rf.facility_id
  ) component_roasted ON true
  LEFT JOIN LATERAL (
    -- Last-week strict tag-matched roasts (for fallback overage)
    SELECT COALESCE(sum(rl.roasted_weight), 0::numeric) AS lbs FROM roast_log rl
    WHERE rl.recipe_id = rf.recipe_id
      AND rl.origin_id = rc.coffee_item
      AND rl."charged?" = true
      AND rl.facility_id = rf.facility_id
      AND rl.roast_date >= (c.roast_week_start - INTERVAL '7 days')
      AND rl.roast_date < c.roast_week_start
  ) last_wk_component_roasted ON true
  LEFT JOIN LATERAL (
    SELECT COALESCE(sum(od.roasted_weight), 0::double precision)::numeric AS lbs
    FROM order_details od
    JOIN orders o ON od.order_id = o.order_id
    JOIN products p ON od.product_id = p.product_id
    WHERE p.recipe_id = rf.recipe_id AND o.facility_id = rf.facility_id
      AND o.order_status <> 'Canceled'::text
      AND o.order_date >= (c.orders_week_start - INTERVAL '7 days')
      AND o.order_date < c.orders_week_start
  ) last_wk_recipe_ordered ON true
  LEFT JOIN LATERAL (
    -- Charge weight history scoped to (recipe, origin)
    SELECT avg(sub.charge_weight_lbs) AS avg_w FROM (
      SELECT charge_weight_lbs FROM roast_log
      WHERE recipe_id = rf.recipe_id AND origin_id = rc.coffee_item
        AND facility_id = rf.facility_id AND charge_weight_lbs > 0::numeric
      ORDER BY roast_date DESC LIMIT 5
    ) sub
  ) charge_w ON true
  LEFT JOIN LATERAL (
    SELECT avg(sub.charge_weight_lbs) AS avg_w FROM (
      SELECT charge_weight_lbs FROM roast_log
      WHERE recipe_id = rf.recipe_id AND facility_id = rf.facility_id AND charge_weight_lbs > 0::numeric
      ORDER BY roast_date DESC LIMIT 5
    ) sub
  ) recipe_charge_w ON true
  LEFT JOIN LATERAL (
    SELECT avg(sub.charge_weight_lbs) AS avg_w FROM (
      SELECT charge_weight_lbs FROM roast_log
      WHERE origin_id = rc.coffee_item AND facility_id = rf.facility_id AND charge_weight_lbs > 0::numeric
      ORDER BY roast_date DESC LIMIT 5
    ) sub
  ) origin_charge_w ON true
  LEFT JOIN LATERAL (
    SELECT (COALESCE(sum(weekly.lbs), 0::numeric) / 6::numeric) AS avg_weekly_lbs
    FROM (
      SELECT date_trunc('week', o2.order_date) AS wk,
        sum(od2.quantity * COALESCE(p2.weight_lbs, 0::numeric)) AS lbs
      FROM order_details od2
      JOIN orders o2 ON od2.order_id = o2.order_id
      JOIN products p2 ON od2.product_id = p2.product_id
      WHERE p2.recipe_id = rf.recipe_id AND o2.facility_id = rf.facility_id
        AND o2.order_status <> 'Canceled'::text
        AND o2.order_date >= (c.orders_week_start - INTERVAL '42 days')
        AND o2.order_date < c.orders_week_start
      GROUP BY 1
    ) weekly
  ) avg_lbs ON true
  WHERE rf.roast_type IS DISTINCT FROM 'Pre-Blend'::text
    AND EXISTS (SELECT 1 FROM recipe_components rc2 WHERE rc2.recipe_id = rf.recipe_id)
), component_alloc AS (
  -- Bake buffer into per-component demand so the recipe-level columns
  -- balance: in_stock + roasted + remaining = demand_with_buffer.
  SELECT cr.*,
    (cr.recipe_avg_weekly_lbs * cr.backstock_buffer_pct / 100::numeric) AS recipe_buffer_target,
    cr.percentage * (
      cr.recipe_demand + (cr.recipe_avg_weekly_lbs * cr.backstock_buffer_pct / 100::numeric)
    ) AS component_demand_buf,
    cr.percentage * cr.recipe_demand AS component_demand_orders,
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
    SUM(
      CEIL(component_remaining / NULLIF(retention_rate, 0::numeric) / NULLIF(component_charge_weight, 0::numeric))
    )::double precision AS roasts_remaining,
    MAX(recipe_avg_weekly_lbs) AS avg_weekly_lbs,
    MAX(backstock_buffer_pct) AS backstock_buffer_pct,
    MAX(recipe_buffer_target) AS buffer_target,
    LEAST(
      MAX(recipe_buffer_target)::double precision,
      GREATEST(0::numeric, SUM(component_remaining) - SUM(component_remaining_orders_only))::double precision
    ) AS buffer_left_calc
  FROM component_final
  GROUP BY recipe_id, facility_id, company_id
), unioned AS (
  SELECT
    rl.recipe_id, rl.facility_id, rl.company_id,
    rl.in_stock_roasted, rl.total_ordered, rl.total_roasted,
    GREATEST(
      0::double precision,
      (rl.total_ordered + (rl.avg_weekly_lbs * rl.backstock_buffer_pct / 100::numeric)::double precision)
        - rl.in_stock_roasted::double precision - rl.total_roasted::double precision
    ) AS roasted_left,
    GREATEST(
      0::double precision,
      (rl.total_ordered + (rl.avg_weekly_lbs * rl.backstock_buffer_pct / 100::numeric)::double precision)
        - rl.in_stock_roasted::double precision - rl.total_roasted::double precision
    ) / NULLIF(rl.retention_rate, 0::numeric)::double precision
      / NULLIF(rl.effective_charge_weight, 0::numeric)::double precision AS roasts_remaining,
    rl.avg_weekly_lbs, rl.backstock_buffer_pct,
    (rl.avg_weekly_lbs * rl.backstock_buffer_pct / 100::numeric) AS buffer_target,
    LEAST(
      GREATEST(
        0::double precision,
        (rl.total_ordered + (rl.avg_weekly_lbs * rl.backstock_buffer_pct / 100::numeric)::double precision)
          - rl.in_stock_roasted::double precision - rl.total_roasted::double precision
      ),
      (rl.avg_weekly_lbs * rl.backstock_buffer_pct / 100::numeric)::double precision
    ) AS buffer_left
  FROM recipe_level rl
  UNION ALL
  SELECT
    pbr.recipe_id, pbr.facility_id, pbr.company_id,
    pbr.in_stock_roasted, pbr.total_ordered, pbr.total_roasted,
    pbr.roasted_left, pbr.roasts_remaining,
    pbr.avg_weekly_lbs, pbr.backstock_buffer_pct,
    pbr.buffer_target, pbr.buffer_left_calc AS buffer_left
  FROM post_blend_recipe pbr
)
SELECT
  (recipe_id || '-'::text) || facility_id AS roast_blend_id,
  recipe_id, facility_id, company_id,
  in_stock_roasted, total_ordered, total_roasted,
  roasted_left, roasts_remaining,
  avg_weekly_lbs, backstock_buffer_pct, buffer_target,
  (total_ordered + buffer_target::double precision) AS effective_target,
  buffer_left
FROM unioned;

COMMIT;
