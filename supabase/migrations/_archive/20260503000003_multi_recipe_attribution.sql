-- 20260503000003_multi_recipe_attribution.sql
-- Activate the multi-recipe attribution feature for boundary batches.
--
-- BACKGROUND
--   LFQ now uses greedy bin-packing per origin. Most batches are single
--   recipe (recipe_id set, ONE join row in roast_log_recipes). The
--   trailing/spillover batch where recipe A's demand ends and recipe B's
--   begins is "multi-recipe" — recipe_id IS NULL on the roast_log row,
--   and 2+ rows in roast_log_recipes carry the per-recipe lbs_allocated
--   (green lbs slice for that recipe).
--
--   Single-recipe batches keep recipe_id populated for back-compat with
--   any reader that hasn't been migrated. Boundary batches set NULL so
--   any naive `recipe_id = X` reader silently EXCLUDES them — predictable
--   under-counting that surfaces during testing rather than silent
--   double-count.
--
-- THIS MIGRATION
--   1. Rewrites three roasted-lbs LATERAL/sub-queries inside
--      roast_detail_by_blend to JOIN through roast_log_recipes and
--      weight each batch's roasted_weight by (lbs_allocated /
--      charge_weight_lbs). Single-recipe batches: weight = 1.0
--      (lbs_allocated == charge_weight_lbs by construction). Multi:
--      each recipe gets its proportional slice.
--        a. recipe_is running balance (anchor → week start)
--        b. recipe_level.total_roasted (this-week roasted)
--        c. component_raw.component_roasted (per recipe × origin)
--
--   2. Loosens 6 stock-calculation functions that INNER JOIN to
--      roast_recipes purely to filter pre-blend. The roast_type check
--      is redundant in the v_roasted_direct path (pre-blend rows have
--      origin_id IS NULL so `origin_id = p_origin_id` already excludes
--      them) but the INNER JOIN drops multi-recipe boundary rows
--      (recipe_id IS NULL → no FK match). Switch to LEFT JOIN +
--      tolerant filter so green inventory tracking by origin still
--      counts boundary batches:
--        - calculate_current_stock_lbs
--        - calculate_monthly_usage
--        - calculate_monthly_usage_facility
--        - trg_manual_inventory_update (trigger fn)
--      All retain identical math for normal single-recipe rows; the
--      only behavioural change is multi-recipe rows now contribute.
--
-- ROLLBACK
--   This migration is fully reversible by re-running the prior view
--   (20260423000007_in_stock_running_balance.sql) and the prior
--   function definitions. No data is mutated.

BEGIN;

-- ════════════════════════════════════════════════════════════════════
-- 1. View rewrite — roast_log_recipes-aware roasted attribution.
-- ════════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW public.roast_detail_by_blend AS
WITH facility_params AS (
  SELECT f.facility_id,
         f.company_id,
         COALESCE(NULLIF(f.time_zone, ''::text), 'Pacific/Honolulu'::text) AS timezone,
         COALESCE((SELECT cp.value_number::integer FROM company_parameters cp
                   WHERE cp.parameter_id = 'RF1iFWjOh7' AND cp.facility_id = f.facility_id LIMIT 1), 4) AS roast_reset_day,
         COALESCE((SELECT cp.value_number::integer FROM company_parameters cp
                   WHERE cp.parameter_id = 'orders_reset_day' AND cp.facility_id = f.facility_id LIMIT 1),
                  (SELECT sp.amount::integer FROM standard_parameters sp WHERE sp.parameters_id = 'orders_reset_day' LIMIT 1),
                  6) AS orders_reset_day,
         COALESCE((SELECT cp.value_number FROM company_parameters cp
                   WHERE cp.parameter_id = '761fd894' AND cp.facility_id = f.facility_id LIMIT 1),
                  25::numeric) AS charge_weight,
         COALESCE((SELECT cp.value_number FROM company_parameters cp
                   WHERE cp.parameter_id = '1de271df' AND cp.facility_id = f.facility_id LIMIT 1),
                  (SELECT sp.amount FROM standard_parameters sp WHERE sp.parameters_id = '1de271df' LIMIT 1),
                  0.82) AS retention_rate,
         COALESCE((SELECT cp.value_number FROM company_parameters cp
                   WHERE cp.parameter_id = 'backstock_buffer_pct' AND cp.facility_id = f.facility_id LIMIT 1),
                  (SELECT sp.amount FROM standard_parameters sp WHERE sp.parameters_id = 'backstock_buffer_pct' LIMIT 1),
                  0::numeric) AS backstock_buffer_pct
  FROM facilities f
),
calc AS (
  SELECT fp.*,
         ((CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date
           - (((EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date)::integer - fp.roast_reset_day) + 7) % 7)) AS roast_week_start,
         ((CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date
           - (((EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date)::integer - fp.orders_reset_day) + 7) % 7)) AS orders_week_start
  FROM facility_params fp
),
recipe_facility AS (
  SELECT rr.recipe_id, rr.roast_type, rr.retention_factor, f.facility_id, f.company_id
  FROM roast_recipes rr
  JOIN facilities f ON f.company_id = rr.company_id
    AND (rr.facility_id IS NULL OR rr.facility_id = f.facility_id)
),
recipe_anchor AS (
  SELECT rf.recipe_id,
         rf.facility_id,
         c.roast_week_start,
         c.orders_week_start,
         c.timezone,
         anchor.anchor_stock,
         anchor.anchor_date,
         anchor.in_current_week
  FROM recipe_facility rf
  JOIN calc c ON c.facility_id = rf.facility_id
  LEFT JOIN LATERAL (
    SELECT rsl.lbs_in_stock AS anchor_stock,
           (rsl.created_at AT TIME ZONE c.timezone)::date AS anchor_date,
           ((rsl.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start) AS in_current_week
    FROM roast_stock_log rsl
    WHERE rsl.stock_type = 'blend'
      AND rsl.blend_id = rf.recipe_id
      AND rsl.facility_id = rf.facility_id
      AND (rsl.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start - INTERVAL '56 days'
    ORDER BY rsl.created_at DESC
    LIMIT 1
  ) anchor ON true
),
recipe_is AS (
  SELECT ra.recipe_id,
         ra.facility_id,
         CASE
           WHEN ra.in_current_week THEN GREATEST(0::numeric, ra.anchor_stock)
           ELSE GREATEST(0::numeric,
             COALESCE(ra.anchor_stock, 0::numeric)
             + COALESCE((
                 -- Multi-recipe-aware: weight each batch's roasted_weight
                 -- by lbs_allocated / charge_weight_lbs. Single-recipe
                 -- rows: lbs_allocated == charge_weight_lbs (1.0×).
                 SELECT SUM(rl.roasted_weight
                            * (rlr.lbs_allocated / NULLIF(rl.charge_weight_lbs, 0::numeric)))
                 FROM roast_log rl
                 JOIN roast_log_recipes rlr ON rlr.roast_log_id = rl.roast_log_id
                 WHERE rlr.recipe_id = ra.recipe_id
                   AND rl.facility_id = ra.facility_id
                   AND rl."charged?" = true
                   AND rl.roast_date >= COALESCE(ra.anchor_date, ra.roast_week_start - INTERVAL '56 days')
                   AND rl.roast_date < ra.roast_week_start
               ), 0::numeric)
             - COALESCE((
                 SELECT SUM(od.roasted_weight)::numeric
                 FROM order_details od
                 JOIN orders o ON od.order_id = o.order_id
                 JOIN products p ON od.product_id = p.product_id
                 WHERE p.recipe_id = ra.recipe_id
                   AND o.facility_id = ra.facility_id
                   AND o.order_status <> 'Canceled'
                   AND o.order_date >= COALESCE(ra.anchor_date, ra.orders_week_start - INTERVAL '56 days')
                   AND o.order_date < ra.orders_week_start
               ), 0::numeric)
           )
         END AS in_stock_roasted
  FROM recipe_anchor ra
),
recipe_level AS (
  SELECT rf.recipe_id,
         rf.facility_id,
         rf.company_id,
         c.backstock_buffer_pct,
         COALESCE(ris.in_stock_roasted, 0::numeric) AS in_stock_roasted,
         COALESCE(ordered.total_ordered, 0::double precision) AS total_ordered,
         COALESCE(roasted.total_roasted, 0::numeric) AS total_roasted,
         COALESCE(NULLIF(rf.retention_factor, 0::numeric), c.retention_rate) AS retention_rate,
         COALESCE((SELECT avg(rl.charge_weight_lbs)
                   FROM (SELECT roast_log.charge_weight_lbs
                         FROM roast_log
                         WHERE roast_log.recipe_id = rf.recipe_id
                           AND roast_log.facility_id = rf.facility_id
                           AND roast_log.charge_weight_lbs > 0::numeric
                         ORDER BY roast_log.roast_date DESC
                         LIMIT 5) rl),
                  c.charge_weight, 25::numeric) AS effective_charge_weight,
         COALESCE(avg_lbs.avg_weekly_lbs, 0::numeric) AS avg_weekly_lbs
  FROM recipe_facility rf
  JOIN calc c ON c.facility_id = rf.facility_id
  LEFT JOIN recipe_is ris ON ris.recipe_id = rf.recipe_id AND ris.facility_id = rf.facility_id
  LEFT JOIN LATERAL (
    SELECT sum(od.roasted_weight) AS total_ordered
    FROM order_details od
    JOIN orders o ON od.order_id = o.order_id
    JOIN products p ON od.product_id = p.product_id
    WHERE p.recipe_id = rf.recipe_id
      AND o.order_status = 'Open'
      AND o.facility_id = rf.facility_id
  ) ordered ON true
  LEFT JOIN LATERAL (
    -- Multi-recipe-aware: weight by lbs_allocated / charge_weight_lbs.
    SELECT sum(rl.roasted_weight
               * (rlr.lbs_allocated / NULLIF(rl.charge_weight_lbs, 0::numeric))) AS total_roasted
    FROM roast_log rl
    JOIN roast_log_recipes rlr ON rlr.roast_log_id = rl.roast_log_id
    WHERE rlr.recipe_id = rf.recipe_id
      AND rl."charged?" = true
      AND rl.roast_date >= c.roast_week_start
      AND rl.facility_id = rf.facility_id
  ) roasted ON true
  LEFT JOIN LATERAL (
    SELECT COALESCE(sum(weekly.lbs), 0::numeric) / 6::numeric AS avg_weekly_lbs
    FROM (
      SELECT date_trunc('week', o2.order_date::timestamp with time zone) AS wk,
             sum(od2.quantity * COALESCE(p2.weight_lbs, 0::numeric)) AS lbs
      FROM order_details od2
      JOIN orders o2 ON od2.order_id = o2.order_id
      JOIN products p2 ON od2.product_id = p2.product_id
      WHERE p2.recipe_id = rf.recipe_id
        AND o2.facility_id = rf.facility_id
        AND o2.order_status <> 'Canceled'
        AND o2.order_date >= c.orders_week_start - INTERVAL '42 days'
        AND o2.order_date < c.orders_week_start
      GROUP BY date_trunc('week', o2.order_date::timestamp with time zone)
    ) weekly
  ) avg_lbs ON true
  WHERE rf.roast_type = 'Pre-Blend'
     OR NOT EXISTS (SELECT 1 FROM recipe_components rc WHERE rc.recipe_id = rf.recipe_id)
),
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
         COALESCE(ris.in_stock_roasted, 0::numeric) * COALESCE(rc.percentage, 0::numeric) AS this_week_stock,
         COALESCE(component_roasted.lbs, 0::numeric) AS component_roasted,
         COALESCE(charge_w.avg_w, recipe_charge_w.avg_w, origin_charge_w.avg_w, c.charge_weight, 25::numeric) AS component_charge_weight,
         COALESCE(avg_lbs.avg_weekly_lbs, 0::numeric) AS recipe_avg_weekly_lbs
  FROM recipe_facility rf
  JOIN recipe_components rc ON rc.recipe_id = rf.recipe_id
  JOIN calc c ON c.facility_id = rf.facility_id
  LEFT JOIN recipe_is ris ON ris.recipe_id = rf.recipe_id AND ris.facility_id = rf.facility_id
  LEFT JOIN LATERAL (
    SELECT sum(od.roasted_weight) AS total_ordered
    FROM order_details od
    JOIN orders o ON od.order_id = o.order_id
    JOIN products p ON od.product_id = p.product_id
    WHERE p.recipe_id = rf.recipe_id
      AND o.order_status = 'Open'
      AND o.facility_id = rf.facility_id
  ) ordered ON true
  LEFT JOIN LATERAL (
    -- Multi-recipe-aware per-component roasted: filter by recipe via
    -- the join table (so multi-recipe boundary rows still contribute),
    -- then filter by origin on the roast_log row itself. Weight by
    -- lbs_allocated / charge_weight_lbs as elsewhere.
    SELECT COALESCE(sum(rl.roasted_weight
                        * (rlr.lbs_allocated / NULLIF(rl.charge_weight_lbs, 0::numeric))),
                    0::numeric) AS lbs
    FROM roast_log rl
    JOIN roast_log_recipes rlr ON rlr.roast_log_id = rl.roast_log_id
    WHERE rlr.recipe_id = rf.recipe_id
      AND rl.origin_id = rc.coffee_item
      AND rl."charged?" = true
      AND rl.roast_date >= c.roast_week_start
      AND rl.facility_id = rf.facility_id
  ) component_roasted ON true
  LEFT JOIN LATERAL (
    SELECT avg(sub.charge_weight_lbs) AS avg_w
    FROM (SELECT roast_log.charge_weight_lbs
          FROM roast_log
          WHERE roast_log.recipe_id = rf.recipe_id
            AND roast_log.origin_id = rc.coffee_item
            AND roast_log.facility_id = rf.facility_id
            AND roast_log.charge_weight_lbs > 0::numeric
          ORDER BY roast_log.roast_date DESC LIMIT 5) sub
  ) charge_w ON true
  LEFT JOIN LATERAL (
    SELECT avg(sub.charge_weight_lbs) AS avg_w
    FROM (SELECT roast_log.charge_weight_lbs
          FROM roast_log
          WHERE roast_log.recipe_id = rf.recipe_id
            AND roast_log.facility_id = rf.facility_id
            AND roast_log.charge_weight_lbs > 0::numeric
          ORDER BY roast_log.roast_date DESC LIMIT 5) sub
  ) recipe_charge_w ON true
  LEFT JOIN LATERAL (
    SELECT avg(sub.charge_weight_lbs) AS avg_w
    FROM (SELECT roast_log.charge_weight_lbs
          FROM roast_log
          WHERE roast_log.origin_id = rc.coffee_item
            AND roast_log.facility_id = rf.facility_id
            AND roast_log.charge_weight_lbs > 0::numeric
          ORDER BY roast_log.roast_date DESC LIMIT 5) sub
  ) origin_charge_w ON true
  LEFT JOIN LATERAL (
    SELECT COALESCE(sum(weekly.lbs), 0::numeric) / 6::numeric AS avg_weekly_lbs
    FROM (
      SELECT date_trunc('week', o2.order_date::timestamp with time zone) AS wk,
             sum(od2.quantity * COALESCE(p2.weight_lbs, 0::numeric)) AS lbs
      FROM order_details od2
      JOIN orders o2 ON od2.order_id = o2.order_id
      JOIN products p2 ON od2.product_id = p2.product_id
      WHERE p2.recipe_id = rf.recipe_id
        AND o2.facility_id = rf.facility_id
        AND o2.order_status <> 'Canceled'
        AND o2.order_date >= c.orders_week_start - INTERVAL '42 days'
        AND o2.order_date < c.orders_week_start
      GROUP BY date_trunc('week', o2.order_date::timestamp with time zone)
    ) weekly
  ) avg_lbs ON true
  WHERE rf.roast_type IS DISTINCT FROM 'Pre-Blend'
    AND EXISTS (SELECT 1 FROM recipe_components rc2 WHERE rc2.recipe_id = rf.recipe_id)
),
component_alloc AS (
  SELECT cr.*,
         (cr.recipe_avg_weekly_lbs * cr.backstock_buffer_pct) / 100::numeric AS recipe_buffer_target,
         cr.percentage * (cr.recipe_demand + (cr.recipe_avg_weekly_lbs * cr.backstock_buffer_pct) / 100::numeric) AS component_demand_buf,
         cr.percentage * cr.recipe_demand AS component_demand_orders,
         cr.this_week_stock AS effective_stock
  FROM component_raw cr
),
component_split AS (
  SELECT ca.*,
         ca.effective_stock AS applied_stock,
         GREATEST(0::numeric, ca.component_demand_buf - ca.effective_stock) AS demand_after_stock
  FROM component_alloc ca
),
component_final AS (
  SELECT cs.*,
         LEAST(cs.demand_after_stock, cs.component_roasted) AS applied_roasted,
         GREATEST(0::numeric, cs.demand_after_stock - cs.component_roasted) AS component_remaining,
         GREATEST(0::numeric, (cs.component_demand_orders - cs.effective_stock) - cs.component_roasted) AS component_remaining_orders_only
  FROM component_split cs
),
post_blend_recipe AS (
  SELECT cf.recipe_id,
         cf.facility_id,
         cf.company_id,
         max(cf.retention_rate) AS retention_rate,
         max(cf.recipe_demand)::double precision AS total_ordered,
         sum(cf.applied_stock) AS in_stock_roasted,
         sum(cf.applied_roasted) AS total_roasted,
         sum(cf.component_remaining)::double precision AS roasted_left,
         sum(ceil((cf.component_remaining / NULLIF(cf.retention_rate, 0::numeric))
                  / NULLIF(cf.component_charge_weight, 0::numeric)))::double precision AS roasts_remaining,
         max(cf.recipe_avg_weekly_lbs) AS avg_weekly_lbs,
         max(cf.backstock_buffer_pct) AS backstock_buffer_pct,
         max(cf.recipe_buffer_target) AS buffer_target,
         LEAST(max(cf.recipe_buffer_target)::double precision,
               GREATEST(0::numeric, sum(cf.component_remaining) - sum(cf.component_remaining_orders_only))::double precision) AS buffer_left_calc
  FROM component_final cf
  GROUP BY cf.recipe_id, cf.facility_id, cf.company_id
),
unioned AS (
  SELECT rl.recipe_id,
         rl.facility_id,
         rl.company_id,
         rl.in_stock_roasted,
         rl.total_ordered,
         rl.total_roasted,
         GREATEST(0::double precision,
           (rl.total_ordered + ((rl.avg_weekly_lbs * rl.backstock_buffer_pct) / 100::numeric)::double precision)
           - rl.in_stock_roasted::double precision
           - rl.total_roasted::double precision) AS roasted_left,
         (GREATEST(0::double precision,
             (rl.total_ordered + ((rl.avg_weekly_lbs * rl.backstock_buffer_pct) / 100::numeric)::double precision)
             - rl.in_stock_roasted::double precision
             - rl.total_roasted::double precision)
          / NULLIF(rl.retention_rate, 0::numeric)::double precision)
         / NULLIF(rl.effective_charge_weight, 0::numeric)::double precision AS roasts_remaining,
         rl.avg_weekly_lbs,
         rl.backstock_buffer_pct,
         (rl.avg_weekly_lbs * rl.backstock_buffer_pct) / 100::numeric AS buffer_target,
         LEAST(
           GREATEST(0::double precision,
             (rl.total_ordered + ((rl.avg_weekly_lbs * rl.backstock_buffer_pct) / 100::numeric)::double precision)
             - rl.in_stock_roasted::double precision
             - rl.total_roasted::double precision),
           ((rl.avg_weekly_lbs * rl.backstock_buffer_pct) / 100::numeric)::double precision
         ) AS buffer_left
  FROM recipe_level rl
  UNION ALL
  SELECT pbr.recipe_id,
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
SELECT (recipe_id || '-' || facility_id) AS roast_blend_id,
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
       total_ordered + buffer_target::double precision AS effective_target,
       buffer_left
FROM unioned;

-- ════════════════════════════════════════════════════════════════════
-- 2. Stock function JOIN loosening — INNER → LEFT so multi-recipe
--    boundary batches (recipe_id IS NULL, origin_id set) still
--    contribute to v_roasted_direct / v_usage_direct.
--
--    The roast_recipes JOIN was only used to filter pre-blend via
--    roast_type. Pre-blend rows have origin_id IS NULL, so they're
--    already excluded by `origin_id = X`. The tolerant filter
--    (`rr.roast_type IS DISTINCT FROM 'Pre-Blend' OR rr.roast_type IS NULL`)
--    keeps the same defensive intent while accepting multi-recipe
--    boundary rows that lack a recipe FK.
-- ════════════════════════════════════════════════════════════════════

-- Helper note: we patch the function bodies in-place via CREATE OR
-- REPLACE. Each function below is recreated with identical signature
-- and body except for the affected JOIN/WHERE pair.

DO $$
DECLARE
  v_count integer;
BEGIN
  -- Sanity check: confirm join table exists before we wire the view to it.
  SELECT COUNT(*) INTO v_count FROM information_schema.tables
   WHERE table_schema = 'public' AND table_name = 'roast_log_recipes';
  IF v_count = 0 THEN
    RAISE EXCEPTION 'roast_log_recipes table missing — run 20260503000001 first';
  END IF;

  RAISE NOTICE 'multi_recipe_attribution: view rewritten to use roast_log_recipes';
END $$;

-- ────────────────────────────────────────────────────────────────────
-- 2a. calculate_current_stock_lbs — green stock by origin.
-- ────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.calculate_current_stock_lbs(p_origin_id text, p_facility_id text)
 RETURNS numeric
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_purchased_lbs       NUMERIC;
    v_starting_lbs        NUMERIC;
    v_bag_size            NUMERIC;
    v_inventory_bags      NUMERIC;
    v_last_inventory_date DATE;
    v_roasted_direct_lbs  NUMERIC;
    v_roasted_blend_lbs   NUMERIC;
BEGIN
    SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
    FROM coffee_inventory WHERE origin_id = p_origin_id AND facility_id = p_facility_id LIMIT 1;

    SELECT last_inventory::DATE, COALESCE(inventory_count_bags, 0)
    INTO v_last_inventory_date, v_inventory_bags
    FROM coffee_inventory WHERE origin_id = p_origin_id AND facility_id = p_facility_id;

    IF v_last_inventory_date IS NULL THEN v_last_inventory_date := '2000-01-01'; END IF;
    v_starting_lbs := v_inventory_bags * v_bag_size;

    SELECT COALESCE(SUM(p.amount), 0) INTO v_purchased_lbs
    FROM coffee_inventory_purchased p
    JOIN shipment_received s ON p.shipment_id = s.shipment_id
    WHERE p.origin = p_origin_id
      AND s.date_received IS NOT NULL
      AND s.date_received::DATE > v_last_inventory_date
      AND COALESCE(s.voided, false) = false
      AND p.facility_id = p_facility_id;

    -- LEFT JOIN + tolerant filter: multi-recipe boundary batches have
    -- recipe_id IS NULL (no FK match) but origin_id IS set; they're
    -- never pre-blend so they SHOULD count toward green-by-origin
    -- consumption. Old INNER JOIN dropped them silently.
    SELECT COALESCE(SUM(rl.charge_weight_lbs), 0) INTO v_roasted_direct_lbs
    FROM roast_log rl
    LEFT JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    WHERE rl.origin_id = p_origin_id
      AND rl.roast_date::DATE > v_last_inventory_date
      AND rl."charged?" = TRUE
      AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend' OR rr.roast_type IS NULL)
      AND rl.facility_id = p_facility_id;

    -- Blend (pre-blend) path unchanged: pre-blend rows always carry a
    -- single recipe_id (boundary batches are never pre-blend).
    SELECT COALESCE(SUM(rl.charge_weight_lbs * rc.percentage), 0) INTO v_roasted_blend_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
    WHERE rc.coffee_item = p_origin_id
      AND rr.roast_type = 'Pre-Blend'
      AND rl.roast_date::DATE > v_last_inventory_date
      AND rl."charged?" = TRUE
      AND rl.facility_id = p_facility_id;

    RETURN GREATEST(0, (v_starting_lbs + v_purchased_lbs - v_roasted_direct_lbs - v_roasted_blend_lbs));
END;
$function$;

-- ────────────────────────────────────────────────────────────────────
-- 2b. calculate_par — par level (bags) per origin.
-- ────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.calculate_par(p_origin_id text)
 RETURNS numeric
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_facility_id   text;
  v_usage_direct  numeric;
  v_usage_blend   numeric;
  v_monthly_usage numeric;
  v_target_months numeric;
  v_buffer        numeric;
  v_bag_size      numeric;
BEGIN
  SELECT facility_id INTO v_facility_id
  FROM coffee_inventory WHERE origin_id = p_origin_id LIMIT 1;

  SELECT COALESCE(SUM(rl.charge_weight_lbs), 0) INTO v_usage_direct
  FROM roast_log rl
  LEFT JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
  WHERE rl.origin_id = p_origin_id
    AND rl.roast_date::date >= (CURRENT_DATE - interval '92 days')
    AND rl."charged?" = true
    AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend' OR rr.roast_type IS NULL)
    AND rl.facility_id = v_facility_id;

  SELECT COALESCE(SUM(rl.charge_weight_lbs * rc.percentage), 0) INTO v_usage_blend
  FROM roast_log rl
  JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
  JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
  WHERE rc.coffee_item = p_origin_id
    AND rr.roast_type = 'Pre-Blend'
    AND rl.roast_date::date >= (CURRENT_DATE - interval '92 days')
    AND rl."charged?" = true
    AND rl.facility_id = v_facility_id;

  v_monthly_usage := (v_usage_direct + v_usage_blend) / 3.0;

  SELECT COALESCE(rc.target_months, 3)
  INTO v_target_months
  FROM coffee_inventory ci
  LEFT JOIN restock_category rc ON rc.restock_category_id = ci.restock_category_id
  WHERE ci.origin_id = p_origin_id
  LIMIT 1;

  IF v_target_months IS NULL THEN v_target_months := 3; END IF;

  SELECT COALESCE(
    (SELECT cp.value_number FROM company_parameters cp
     WHERE cp.parameter_id = '5131610b' AND cp.facility_id = v_facility_id LIMIT 1),
    1.3
  ) INTO v_buffer;

  SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
  FROM coffee_inventory WHERE origin_id = p_origin_id AND facility_id = v_facility_id LIMIT 1;

  RETURN ROUND((v_monthly_usage * v_target_months * v_buffer) / NULLIF(v_bag_size, 0));
END;
$function$;

-- ────────────────────────────────────────────────────────────────────
-- 2c. calculate_restock_level — restock threshold per origin.
-- ────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.calculate_restock_level(p_origin_id text)
 RETURNS numeric
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_facility_id      text;
  v_usage_direct     numeric;
  v_usage_blend      numeric;
  v_monthly_usage    numeric;
  v_reorder_months   numeric;
  v_buffer           numeric;
  v_bag_size         numeric;
  v_current_date     date;
  v_timezone         text;
  v_par              numeric;
  v_result           numeric;
BEGIN
  SELECT facility_id INTO v_facility_id
  FROM coffee_inventory WHERE origin_id = p_origin_id LIMIT 1;

  SELECT time_zone INTO v_timezone FROM facilities WHERE facility_id = v_facility_id;
  IF v_timezone IS NULL OR v_timezone = '' THEN v_timezone := 'Pacific/Honolulu'; END IF;
  v_current_date := (CURRENT_TIMESTAMP AT TIME ZONE v_timezone)::date;

  SELECT COALESCE(SUM(rl.charge_weight_lbs), 0) INTO v_usage_direct
  FROM roast_log rl
  LEFT JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
  WHERE rl.origin_id = p_origin_id
    AND rl.roast_date::date >= (v_current_date - interval '92 days')
    AND rl."charged?" = true
    AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend' OR rr.roast_type IS NULL)
    AND rl.facility_id = v_facility_id;

  SELECT COALESCE(SUM(rl.charge_weight_lbs * rc.percentage), 0) INTO v_usage_blend
  FROM roast_log rl
  JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
  JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
  WHERE rc.coffee_item = p_origin_id
    AND rr.roast_type = 'Pre-Blend'
    AND rl.roast_date::date >= (v_current_date - interval '92 days')
    AND rl."charged?" = true
    AND rl.facility_id = v_facility_id;

  v_monthly_usage := (v_usage_direct + v_usage_blend) / 3.0;

  IF v_monthly_usage <= 0 THEN RETURN 0; END IF;

  SELECT COALESCE(rc.reorder_months, 1.5)
  INTO v_reorder_months
  FROM coffee_inventory ci
  LEFT JOIN restock_category rc ON rc.restock_category_id = ci.restock_category_id
  WHERE ci.origin_id = p_origin_id
  LIMIT 1;
  IF v_reorder_months IS NULL THEN v_reorder_months := 1.5; END IF;

  SELECT COALESCE(
    (SELECT cp.value_number FROM company_parameters cp
     WHERE cp.parameter_id = '5131610b' AND cp.facility_id = v_facility_id LIMIT 1),
    1.3
  ) INTO v_buffer;

  SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
  FROM coffee_inventory WHERE origin_id = p_origin_id AND facility_id = v_facility_id LIMIT 1;

  v_result := CEILING((v_monthly_usage * v_reorder_months * v_buffer) / NULLIF(v_bag_size, 0));

  v_par := calculate_par(p_origin_id);
  IF v_par <= 0 THEN RETURN 0; END IF;

  RETURN LEAST(v_result, v_par);
END;
$function$;

-- ────────────────────────────────────────────────────────────────────
-- 2d. handle_manual_inventory_update — trigger on coffee_inventory.
-- ────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.handle_manual_inventory_update()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_bag_size            NUMERIC;
    v_purchased_lbs       NUMERIC;
    v_roasted_direct_lbs  NUMERIC;
    v_roasted_blend_lbs   NUMERIC;
    v_last_inventory_date DATE;
BEGIN
    v_bag_size := COALESCE(NEW.bag_size::numeric, 154);
    NEW.par           := public.calculate_par(NEW.origin_id);
    NEW.restock_level := public.calculate_restock_level(NEW.origin_id);
    v_last_inventory_date := COALESCE(NEW.last_inventory::DATE, '2000-01-01');
    NEW.inventory_lbs     := COALESCE(NEW.inventory_count_bags, 0) * v_bag_size;

    SELECT COALESCE(SUM(p.amount), 0) INTO v_purchased_lbs
    FROM coffee_inventory_purchased p
    JOIN shipment_received s ON p.shipment_id = s.shipment_id
    WHERE p.origin = NEW.origin_id
      AND s.date_received IS NOT NULL
      AND s.date_received::DATE > v_last_inventory_date
      AND COALESCE(s.voided, false) = false
      AND p.facility_id = NEW.facility_id;

    SELECT COALESCE(SUM(rl.charge_weight_lbs), 0) INTO v_roasted_direct_lbs
    FROM roast_log rl
    LEFT JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    WHERE rl.origin_id = NEW.origin_id
      AND rl.roast_date::DATE > v_last_inventory_date
      AND rl."charged?" = TRUE
      AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend' OR rr.roast_type IS NULL)
      AND rl.facility_id = NEW.facility_id;

    SELECT COALESCE(SUM(rl.charge_weight_lbs * rc.percentage), 0) INTO v_roasted_blend_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
    WHERE rc.coffee_item = NEW.origin_id
      AND rr.roast_type = 'Pre-Blend'
      AND rl.roast_date::DATE > v_last_inventory_date
      AND rl."charged?" = TRUE
      AND rl.facility_id = NEW.facility_id;

    NEW.in_stock_lbs  := GREATEST(0, (NEW.inventory_lbs + v_purchased_lbs - v_roasted_direct_lbs - v_roasted_blend_lbs));
    NEW.in_stock      := NEW.in_stock_lbs / NULLIF(v_bag_size, 0);
    NEW.to_order_bags := GREATEST(0, COALESCE(NEW.par, 0) - NEW.in_stock);

    RETURN NEW;
END;
$function$;

-- ────────────────────────────────────────────────────────────────────
-- 2e. trg_recalc_coffee_on_category_change — restock-category trigger.
-- ────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.trg_recalc_coffee_on_category_change()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_par numeric;
  v_restock numeric;
BEGIN
  IF OLD.restock_category_id IS DISTINCT FROM NEW.restock_category_id THEN
    IF pg_trigger_depth() > 1 THEN
      RETURN NEW;
    END IF;

    PERFORM set_config('app.skip_coffee_recalc', 'true', true);

    DECLARE
      v_facility_id text := NEW.facility_id;
      v_usage_direct numeric;
      v_usage_blend numeric;
      v_monthly_usage numeric;
      v_target_months numeric;
      v_reorder_months numeric;
      v_buffer numeric;
      v_bag_size numeric;
    BEGIN
      SELECT COALESCE(SUM(rl.charge_weight_lbs), 0) INTO v_usage_direct
      FROM roast_log rl LEFT JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
      WHERE rl.origin_id = NEW.origin_id
        AND rl.roast_date::date >= (CURRENT_DATE - interval '92 days')
        AND rl."charged?" = true
        AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend' OR rr.roast_type IS NULL)
        AND rl.facility_id = v_facility_id;

      SELECT COALESCE(SUM(rl.charge_weight_lbs * rc.percentage), 0) INTO v_usage_blend
      FROM roast_log rl JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
      JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
      WHERE rc.coffee_item = NEW.origin_id
        AND rr.roast_type = 'Pre-Blend'
        AND rl.roast_date::date >= (CURRENT_DATE - interval '92 days')
        AND rl."charged?" = true
        AND rl.facility_id = v_facility_id;

      v_monthly_usage := (v_usage_direct + v_usage_blend) / 3.0;

      SELECT COALESCE(rc2.target_months, 3), COALESCE(rc2.reorder_months, 1.5)
      INTO v_target_months, v_reorder_months
      FROM restock_category rc2
      WHERE rc2.restock_category_id = NEW.restock_category_id;

      IF v_target_months IS NULL THEN v_target_months := 3; END IF;
      IF v_reorder_months IS NULL THEN v_reorder_months := 1.5; END IF;

      SELECT COALESCE(
        (SELECT cp.value_number FROM company_parameters cp
         WHERE cp.parameter_id = '5131610b' AND cp.facility_id = v_facility_id LIMIT 1),
        1.3) INTO v_buffer;

      SELECT COALESCE(NEW.bag_size::numeric, 154) INTO v_bag_size;

      NEW.par := FLOOR((v_monthly_usage * v_target_months * v_buffer) / NULLIF(v_bag_size, 0));

      v_restock := CEILING((v_monthly_usage * v_reorder_months * v_buffer) / NULLIF(v_bag_size, 0));
      IF NEW.par <= 0 THEN v_restock := 0; END IF;
      NEW.restock_level := LEAST(v_restock, NEW.par);

      NEW.to_order := GREATEST(0, NEW.par - COALESCE(NEW.in_stock, 0));
    END;
  END IF;
  RETURN NEW;
END;
$function$;

-- ────────────────────────────────────────────────────────────────────
-- 2f. trg_recalc_coffee_on_nudge — hourly cron-touch trigger.
-- ────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.trg_recalc_coffee_on_nudge()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_usage_direct  numeric;
  v_usage_blend   numeric;
  v_total_usage   numeric;
BEGIN
  IF pg_trigger_depth() > 1 THEN RETURN NEW; END IF;

  SELECT COALESCE(SUM(rl.charge_weight_lbs), 0) INTO v_usage_direct
  FROM roast_log rl
  LEFT JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
  WHERE rl.origin_id = NEW.origin_id
    AND rl.roast_date::date >= (CURRENT_DATE - interval '92 days')
    AND rl."charged?" = true
    AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend' OR rr.roast_type IS NULL)
    AND rl.facility_id = NEW.facility_id;

  SELECT COALESCE(SUM(rl.charge_weight_lbs * rc.percentage), 0) INTO v_usage_blend
  FROM roast_log rl
  JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
  JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
  WHERE rc.coffee_item = NEW.origin_id
    AND rr.roast_type = 'Pre-Blend'
    AND rl.roast_date::date >= (CURRENT_DATE - interval '92 days')
    AND rl."charged?" = true
    AND rl.facility_id = NEW.facility_id;

  v_total_usage := v_usage_direct + v_usage_blend;
  NEW.daily_usage_lbs := v_total_usage / 92.0;

  NEW.par := calculate_par(NEW.origin_id);
  NEW.restock_level := calculate_restock_level(NEW.origin_id);
  NEW.to_order := GREATEST(0, NEW.par - COALESCE(NEW.in_stock, 0));
  RETURN NEW;
END;
$function$;

COMMIT;
