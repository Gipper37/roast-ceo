-- 20260504000003_recipe_weekly_targets.sql
-- Per-recipe per-week roast target overrides.
--
-- WHY
--   The auto-computed weekly target (open orders or 6-week wk-avg)
--   misses real-world planning context: wholesale prep weeks, market
--   prep, deliberate scaling-back of a recipe, etc. Roastmasters
--   need an explicit "this is what I want to roast for Hendrix this
--   week" lever that overrides the auto value, without polluting
--   underlying orders/history data.
--
-- DESIGN
--   - Per-week, NOT persistent. Most overrides are situational and
--     should naturally reset each roast week. Standing wholesale
--     belongs in the orders system as recurring orders, not here.
--   - Source-agnostic. When set, the override replaces BOTH
--     total_ordered (orders mode) AND avg_weekly_lbs (wk avg mode)
--     for that recipe. The toggle still applies to recipes WITHOUT
--     overrides.
--   - Buffer pct stacks ON TOP. effective_target = override + buffer.
--   - Post-blend recipes propagate via recipe_components × percentage
--     just like the rest of the planner. No special case.
--
-- VIEW
--   roast_detail_by_blend gains a new nullable column
--   `weekly_target_override`. Consumers (LFQ planner, page.tsx
--   demand calc, BS walk) check it: when present, prefer the override
--   over total_ordered / avg_weekly_lbs. When NULL, current behavior.

BEGIN;

-- ════════════════════════════════════════════════════════════════════
-- 1. New table for the per-week override entries.
-- ════════════════════════════════════════════════════════════════════
CREATE TABLE public.recipe_weekly_targets (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  recipe_id    text NOT NULL REFERENCES public.roast_recipes(recipe_id) ON DELETE CASCADE,
  facility_id  text NOT NULL REFERENCES public.facilities(facility_id) ON DELETE CASCADE,
  week_start   date NOT NULL,
  target_lbs   numeric NOT NULL CHECK (target_lbs >= 0),
  notes        text,
  created_by   text,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (recipe_id, facility_id, week_start)
);

-- Hot path: the view does a per-recipe lookup keyed by recipe + facility +
-- this-roast-week. PK already covers UNIQUE; add the (facility, week_start)
-- index for the "fetch all overrides for a facility this week" pull (used
-- by the Plan Inputs editor + the LC/RP indicator counts).
CREATE INDEX recipe_weekly_targets_facility_week_idx
  ON public.recipe_weekly_targets (facility_id, week_start);

COMMENT ON TABLE public.recipe_weekly_targets IS
  'Per-recipe per-week manual target overrides. When set, replaces the auto-computed target (orders or wk avg) for that recipe in roast_detail_by_blend. Buffer pct still stacks on top.';

-- ════════════════════════════════════════════════════════════════════
-- 2. Touch trigger to keep updated_at fresh on UPDATE.
-- ════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.touch_recipe_weekly_targets_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$fn$;

CREATE TRIGGER trg_recipe_weekly_targets_touch
  BEFORE UPDATE ON public.recipe_weekly_targets
  FOR EACH ROW EXECUTE FUNCTION public.touch_recipe_weekly_targets_updated_at();

-- ════════════════════════════════════════════════════════════════════
-- 3. Re-emit roast_detail_by_blend with the override exposed.
--    Only structural change vs prior version: new `weekly_target_override`
--    column on the SELECT (NULL when no row in recipe_weekly_targets).
--    Math/CTEs unchanged — consumers do the COALESCE in app code so the
--    view stays a clean projection of raw signals.
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
      AND (rsl.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start - INTERVAL '28 days'
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
                 SELECT SUM(rl.roasted_weight
                            * (rlr.lbs_allocated / NULLIF(rl.charge_weight_lbs, 0::numeric)))
                 FROM roast_log rl
                 JOIN roast_log_recipes rlr ON rlr.roast_log_id = rl.roast_log_id
                 WHERE rlr.recipe_id = ra.recipe_id
                   AND rl.facility_id = ra.facility_id
                   AND rl."charged?" = true
                   AND rl.roast_date >= COALESCE(ra.anchor_date, ra.roast_week_start - INTERVAL '28 days')
                   AND rl.roast_date < ra.roast_week_start
               ), 0::numeric)
             - COALESCE((
                 SELECT SUM(od.roasted_weight)::numeric
                 FROM order_details od
                 JOIN orders o ON od.order_id = o.order_id
                 JOIN products p ON od.product_id = p.product_id
                 WHERE p.recipe_id = ra.recipe_id
                   AND o.facility_id = ra.facility_id
                   AND o.order_status = 'Delivered'
                   AND COALESCE((o.status_changed_at AT TIME ZONE ra.timezone)::date, o.order_date)
                       >= COALESCE(ra.anchor_date, ra.orders_week_start - INTERVAL '28 days')
                   AND COALESCE((o.status_changed_at AT TIME ZONE ra.timezone)::date, o.order_date)
                       < ra.orders_week_start
               ), 0::numeric)
           )
         END AS in_stock_roasted
  FROM recipe_anchor ra
),
-- NEW: pull this-week's manual override per recipe (NULL when none).
recipe_override AS (
  SELECT rwt.recipe_id, rwt.facility_id, rwt.target_lbs, rwt.notes
  FROM recipe_weekly_targets rwt
  JOIN calc c ON c.facility_id = rwt.facility_id
  WHERE rwt.week_start = c.roast_week_start
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
         COALESCE(avg_lbs.avg_weekly_lbs, 0::numeric) AS avg_weekly_lbs,
         ovr.target_lbs AS weekly_target_override
  FROM recipe_facility rf
  JOIN calc c ON c.facility_id = rf.facility_id
  LEFT JOIN recipe_is ris ON ris.recipe_id = rf.recipe_id AND ris.facility_id = rf.facility_id
  LEFT JOIN recipe_override ovr ON ovr.recipe_id = rf.recipe_id AND ovr.facility_id = rf.facility_id
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
         COALESCE(avg_lbs.avg_weekly_lbs, 0::numeric) AS recipe_avg_weekly_lbs,
         ovr.target_lbs AS weekly_target_override
  FROM recipe_facility rf
  JOIN recipe_components rc ON rc.recipe_id = rf.recipe_id
  JOIN calc c ON c.facility_id = rf.facility_id
  LEFT JOIN recipe_is ris ON ris.recipe_id = rf.recipe_id AND ris.facility_id = rf.facility_id
  LEFT JOIN recipe_override ovr ON ovr.recipe_id = rf.recipe_id AND ovr.facility_id = rf.facility_id
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
               GREATEST(0::numeric, sum(cf.component_remaining) - sum(cf.component_remaining_orders_only))::double precision) AS buffer_left_calc,
         max(cf.weekly_target_override) AS weekly_target_override
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
         ) AS buffer_left,
         rl.weekly_target_override
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
         pbr.buffer_left_calc AS buffer_left,
         pbr.weekly_target_override
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
       buffer_left,
       weekly_target_override
FROM unioned;

COMMIT;
