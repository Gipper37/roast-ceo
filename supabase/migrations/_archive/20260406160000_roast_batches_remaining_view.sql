-- Migration: roast_batches_remaining view
--
-- Handles Pre-Blend and Post-Blend recipes correctly for batch counting:
--
--   Pre-Blend        → one row per recipe, CEIL per recipe
--   Post-Blend + BOM → one row per origin per recipe, CEIL per component
--   Post-Blend, solo → one row per recipe (no components), CEIL per recipe
--
-- Stock is sourced from roast_stock_log (week-scoped, matching existing views).
-- Does NOT modify existing roast_detail or roast_detail_by_blend views.

CREATE OR REPLACE VIEW public.roast_batches_remaining AS
WITH facility_params AS (
    SELECT
        f.facility_id,
        f.company_id,
        COALESCE(NULLIF(f.time_zone, ''), 'Pacific/Honolulu') AS timezone,
        COALESCE(
            (SELECT cp.value_number::integer
             FROM public.company_parameters cp
             WHERE cp.parameter_id = 'RF1iFWjOh7'
               AND cp.facility_id  = f.facility_id
             LIMIT 1),
            4
        ) AS roast_reset_day,
        COALESCE(
            (SELECT cp.value_number
             FROM public.company_parameters cp
             WHERE cp.parameter_id = '761fd894'
               AND cp.facility_id  = f.facility_id
             LIMIT 1),
            25
        ) AS default_charge_weight,
        COALESCE(
            (SELECT cp.value_number
             FROM public.company_parameters cp
             WHERE cp.parameter_id = '1de271df'
               AND cp.facility_id  = f.facility_id
             LIMIT 1),
            0.82
        ) AS retention_rate
    FROM public.facilities f
),
calc AS (
    SELECT
        fp.facility_id,
        fp.company_id,
        fp.default_charge_weight,
        fp.retention_rate,
        ((CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date
            - ((EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date)::integer
                - fp.roast_reset_day + 7) % 7)) AS roast_week_start,
        fp.timezone
    FROM facility_params fp
),

-- ── PRE-BLEND: one row per recipe ────────────────────────────────────────────
-- in_stock_roasted = blend stock logged this week
-- effective_charge_weight = avg last 5 roasts for this recipe
pre_blend AS (
    SELECT
        rr.recipe_id,
        f.facility_id,
        f.company_id,
        NULL::text AS origin_id,
        -- Blend stock logged this week
        COALESCE((
            SELECT SUM(rsl.lbs_in_stock)
            FROM public.roast_stock_log rsl
            WHERE rsl.blend_id    = rr.recipe_id
              AND rsl.facility_id = f.facility_id
              AND (rsl.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start
        ), 0) AS in_stock_roasted,
        -- Open order roasted weight for this recipe
        COALESCE((
            SELECT SUM(od.roasted_weight)
            FROM public.order_details od
            JOIN public.orders o   ON od.order_id  = o.order_id
            JOIN public.products p ON od.product_id = p.product_id
            WHERE p.recipe_id    = rr.recipe_id
              AND o.order_status = 'Open'
              AND o.facility_id  = f.facility_id
        ), 0) AS total_ordered,
        -- Roasted this week for this recipe
        COALESCE((
            SELECT SUM(rl.roasted_weight)
            FROM public.roast_log rl
            WHERE rl.recipe_id   = rr.recipe_id
              AND rl."charged?"  = true
              AND rl.roast_date >= c.roast_week_start
              AND rl.facility_id = f.facility_id
        ), 0) AS total_roasted,
        -- Per-recipe retention factor, falling back to facility/standard/default
        COALESCE(NULLIF(rr.retention_factor, 0), c.retention_rate) AS retention_rate,
        -- Avg charge weight of last 5 roasts for this recipe
        COALESCE(
            (SELECT AVG(sub.charge_weight_lbs)
             FROM (
                 SELECT charge_weight_lbs
                 FROM public.roast_log
                 WHERE recipe_id         = rr.recipe_id
                   AND facility_id       = f.facility_id
                   AND charge_weight_lbs > 0
                 ORDER BY roast_date DESC
                 LIMIT 5
             ) sub),
            c.default_charge_weight,
            25
        ) AS effective_charge_weight
    FROM public.roast_recipes rr
    JOIN public.facilities f
      ON f.company_id = rr.company_id
     AND (rr.facility_id IS NULL OR rr.facility_id = f.facility_id)
    JOIN calc c ON c.facility_id = f.facility_id
    WHERE rr.roast_type = 'Pre-Blend'
),

-- ── POST-BLEND WITH COMPONENTS: one row per origin per recipe ─────────────────
-- in_stock = origin stock this week + share of blend stock this week
-- total_ordered = open order weight × component percentage
-- total_roasted = roasts for this origin AND this recipe this week
-- effective_charge_weight = avg last 5 origin-level roasts at this facility
post_blend_with_components AS (
    SELECT
        rr.recipe_id,
        f.facility_id,
        f.company_id,
        rc.coffee_item AS origin_id,
        -- Origin roasted stock this week + share of assembled blend stock this week
        COALESCE((
            SELECT SUM(rsl.lbs_in_stock)
            FROM public.roast_stock_log rsl
            WHERE rsl.origin_id   = rc.coffee_item
              AND rsl.facility_id = f.facility_id
              AND (rsl.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start
        ), 0)
        + rc.percentage * COALESCE((
            SELECT SUM(rsl.lbs_in_stock)
            FROM public.roast_stock_log rsl
            WHERE rsl.blend_id    = rr.recipe_id
              AND rsl.facility_id = f.facility_id
              AND (rsl.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start
        ), 0) AS in_stock_roasted,
        -- Open order weight scaled to this component's share
        rc.percentage * COALESCE((
            SELECT SUM(od.roasted_weight)
            FROM public.order_details od
            JOIN public.orders o   ON od.order_id  = o.order_id
            JOIN public.products p ON od.product_id = p.product_id
            WHERE p.recipe_id    = rr.recipe_id
              AND o.order_status = 'Open'
              AND o.facility_id  = f.facility_id
        ), 0) AS total_ordered,
        -- Roasts for this specific origin under this recipe this week
        COALESCE((
            SELECT SUM(rl.roasted_weight)
            FROM public.roast_log rl
            WHERE rl.origin_id   = rc.coffee_item
              AND rl.recipe_id   = rr.recipe_id
              AND rl."charged?"  = true
              AND rl.roast_date >= c.roast_week_start
              AND rl.facility_id = f.facility_id
        ), 0) AS total_roasted,
        COALESCE(NULLIF(rr.retention_factor, 0), c.retention_rate) AS retention_rate,
        -- Origin-level effective charge weight (avg last 5 for this origin)
        COALESCE(
            (SELECT AVG(sub.charge_weight_lbs)
             FROM (
                 SELECT charge_weight_lbs
                 FROM public.roast_log
                 WHERE origin_id         = rc.coffee_item
                   AND facility_id       = f.facility_id
                   AND charge_weight_lbs > 0
                 ORDER BY roast_date DESC
                 LIMIT 5
             ) sub),
            c.default_charge_weight,
            25
        ) AS effective_charge_weight
    FROM public.roast_recipes rr
    JOIN public.facilities f
      ON f.company_id = rr.company_id
     AND (rr.facility_id IS NULL OR rr.facility_id = f.facility_id)
    JOIN public.recipe_components rc ON rc.recipe_id = rr.recipe_id
    JOIN calc c ON c.facility_id = f.facility_id
    WHERE rr.roast_type != 'Pre-Blend'
),

-- ── POST-BLEND WITHOUT COMPONENTS: recipe-level fallback ─────────────────────
-- Single-origin post-blend with no recipe_components rows — recipe-level calc
post_blend_no_components AS (
    SELECT
        rr.recipe_id,
        f.facility_id,
        f.company_id,
        NULL::text AS origin_id,
        COALESCE((
            SELECT SUM(rsl.lbs_in_stock)
            FROM public.roast_stock_log rsl
            WHERE rsl.blend_id    = rr.recipe_id
              AND rsl.facility_id = f.facility_id
              AND (rsl.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start
        ), 0) AS in_stock_roasted,
        COALESCE((
            SELECT SUM(od.roasted_weight)
            FROM public.order_details od
            JOIN public.orders o   ON od.order_id  = o.order_id
            JOIN public.products p ON od.product_id = p.product_id
            WHERE p.recipe_id    = rr.recipe_id
              AND o.order_status = 'Open'
              AND o.facility_id  = f.facility_id
        ), 0) AS total_ordered,
        COALESCE((
            SELECT SUM(rl.roasted_weight)
            FROM public.roast_log rl
            WHERE rl.recipe_id   = rr.recipe_id
              AND rl."charged?"  = true
              AND rl.roast_date >= c.roast_week_start
              AND rl.facility_id = f.facility_id
        ), 0) AS total_roasted,
        COALESCE(NULLIF(rr.retention_factor, 0), c.retention_rate) AS retention_rate,
        COALESCE(
            (SELECT AVG(sub.charge_weight_lbs)
             FROM (
                 SELECT charge_weight_lbs
                 FROM public.roast_log
                 WHERE recipe_id         = rr.recipe_id
                   AND facility_id       = f.facility_id
                   AND charge_weight_lbs > 0
                 ORDER BY roast_date DESC
                 LIMIT 5
             ) sub),
            c.default_charge_weight,
            25
        ) AS effective_charge_weight
    FROM public.roast_recipes rr
    JOIN public.facilities f
      ON f.company_id = rr.company_id
     AND (rr.facility_id IS NULL OR rr.facility_id = f.facility_id)
    JOIN calc c ON c.facility_id = f.facility_id
    WHERE rr.roast_type != 'Pre-Blend'
      AND NOT EXISTS (
          SELECT 1
          FROM public.recipe_components rc2
          WHERE rc2.recipe_id = rr.recipe_id
      )
),

all_rows AS (
    SELECT * FROM pre_blend
    UNION ALL
    SELECT * FROM post_blend_with_components
    UNION ALL
    SELECT * FROM post_blend_no_components
)

SELECT
    recipe_id || '-' || facility_id
        || COALESCE('-' || origin_id, '') AS batch_row_id,
    recipe_id,
    facility_id,
    company_id,
    origin_id,
    in_stock_roasted,
    total_ordered,
    total_roasted,
    GREATEST(0, total_ordered - in_stock_roasted - total_roasted) AS roasted_left,
    GREATEST(0, total_ordered - in_stock_roasted - total_roasted)
        / NULLIF(retention_rate, 0)
        / NULLIF(effective_charge_weight, 0)                        AS roasts_remaining,
    CEIL(
        GREATEST(0, total_ordered - in_stock_roasted - total_roasted)
        / NULLIF(retention_rate, 0)
        / NULLIF(effective_charge_weight, 0)
    )                                                               AS batches_remaining
FROM all_rows;
