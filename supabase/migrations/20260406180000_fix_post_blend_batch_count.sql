-- Migration: fix post-blend batch count in roast_batches_remaining
-- Must drop both views and recreate due to column changes (roasts_remaining removed)
-- and roast_detail_by_blend depending on roast_batches_remaining.

DROP VIEW IF EXISTS public.roast_detail_by_blend CASCADE;
DROP VIEW IF EXISTS public.roast_batches_remaining CASCADE;

-- Migration: fix post-blend batch count in roast_batches_remaining
--
-- Problem: post_blend_with_components was filtering total_roasted by
-- recipe_id AND origin_id. Roasters log Chocolate roasts under the recipe
-- they're making (Pohaku, Nova) not under Vinyl — so Vinyl saw 0 Chocolate
-- roasted and inflated its batch count.
--
-- Fix: use origin-level total_roasted (all recipes, any recipe_id) for
-- post-blend components. This correctly sees that Chocolate is fully covered
-- by cross-recipe roasting. Vinyl's remaining = only its unmet Fruit demand.
--
-- Also drops roasts_remaining from roast_batches_remaining (batches_remaining
-- is the ceiled integer; roasts_remaining was a redundant intermediate).

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
pre_blend AS (
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
    WHERE rr.roast_type = 'Pre-Blend'
),

-- ── POST-BLEND WITH COMPONENTS: one row per origin per recipe ─────────────────
-- total_roasted uses ALL roasts for this origin (any recipe_id).
-- This correctly attributes cross-recipe roasting — e.g. Chocolate roasted
-- for Pohaku/Nova counts toward Vinyl's Chocolate component.
post_blend_with_components AS (
    SELECT
        rr.recipe_id,
        f.facility_id,
        f.company_id,
        rc.coffee_item AS origin_id,
        -- Origin stock this week + share of assembled blend stock this week
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
        -- This recipe's open order demand for this component
        rc.percentage * COALESCE((
            SELECT SUM(od.roasted_weight)
            FROM public.order_details od
            JOIN public.orders o   ON od.order_id  = o.order_id
            JOIN public.products p ON od.product_id = p.product_id
            WHERE p.recipe_id    = rr.recipe_id
              AND o.order_status = 'Open'
              AND o.facility_id  = f.facility_id
        ), 0) AS total_ordered,
        -- ALL roasts for this origin this week (any recipe) — cross-recipe coverage
        COALESCE((
            SELECT SUM(rl.roasted_weight)
            FROM public.roast_log rl
            WHERE rl.origin_id   = rc.coffee_item
              AND rl."charged?"  = true
              AND rl.roast_date >= c.roast_week_start
              AND rl.facility_id = f.facility_id
        ), 0) AS total_roasted,
        COALESCE(NULLIF(rr.retention_factor, 0), c.retention_rate) AS retention_rate,
        -- Origin-level effective charge weight
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
    CEIL(
        GREATEST(0, total_ordered - in_stock_roasted - total_roasted)
        / NULLIF(retention_rate, 0)
        / NULLIF(effective_charge_weight, 0)
    ) AS batches_remaining
FROM all_rows;

-- Recreate roast_detail_by_blend (was dropped by CASCADE above).
-- Identical to the version in migration 20260406170000 except we preserve
-- existing column names and still pull batches_remaining from the fixed view.
CREATE VIEW public.roast_detail_by_blend AS
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
        ) AS charge_weight,
        COALESCE(
            (SELECT cp.value_number
             FROM public.company_parameters cp
             WHERE cp.parameter_id = '1de271df'
               AND cp.facility_id  = f.facility_id
             LIMIT 1),
            ( SELECT sp.amount
              FROM public.standard_parameters sp
              WHERE sp.parameters_id = '1de271df'
              LIMIT 1),
            0.82
        ) AS retention_rate
    FROM public.facilities f
),
calc AS (
    SELECT
        fp.facility_id,
        fp.company_id,
        fp.timezone,
        fp.charge_weight,
        fp.retention_rate,
        ((CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date
            - ((EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date)::integer
                - fp.roast_reset_day + 7) % 7)) AS roast_week_start
    FROM facility_params fp
),
recipe_facility AS (
    SELECT rr.recipe_id, rr.retention_factor, f.facility_id, f.company_id
    FROM public.roast_recipes rr
    JOIN public.facilities f
      ON f.company_id = rr.company_id
     AND (rr.facility_id IS NULL OR rr.facility_id = f.facility_id)
),
per_recipe AS (
    SELECT
        rf.recipe_id,
        rf.facility_id,
        rf.company_id,
        COALESCE(stock.in_stock_roasted, 0)  AS in_stock_roasted,
        COALESCE(ordered.total_ordered, 0)   AS total_ordered,
        COALESCE(roasted.total_roasted, 0)   AS total_roasted,
        COALESCE(NULLIF(rf.retention_factor, 0), c.retention_rate) AS retention_rate,
        COALESCE(
            (SELECT AVG(rl.charge_weight_lbs)
             FROM (
                 SELECT charge_weight_lbs
                 FROM public.roast_log
                 WHERE recipe_id         = rf.recipe_id
                   AND facility_id       = rf.facility_id
                   AND charge_weight_lbs > 0
                 ORDER BY roast_date DESC
                 LIMIT 5
             ) rl),
            c.charge_weight,
            25
        ) AS effective_charge_weight
    FROM recipe_facility rf
    JOIN calc c ON c.facility_id = rf.facility_id
    LEFT JOIN LATERAL (
        SELECT COALESCE(SUM(rsl.lbs_in_stock), 0) AS in_stock_roasted
        FROM public.roast_stock_log rsl
        WHERE rsl.blend_id    = rf.recipe_id
          AND rsl.facility_id = rf.facility_id
          AND (rsl.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start
    ) stock ON true
    LEFT JOIN LATERAL (
        SELECT SUM(od.roasted_weight) AS total_ordered
        FROM public.order_details od
        JOIN public.orders o   ON od.order_id  = o.order_id
        JOIN public.products p ON od.product_id = p.product_id
        WHERE p.recipe_id    = rf.recipe_id
          AND o.order_status = 'Open'
          AND o.facility_id  = rf.facility_id
    ) ordered ON true
    LEFT JOIN LATERAL (
        SELECT SUM(rl.roasted_weight) AS total_roasted
        FROM public.roast_log rl
        WHERE rl.recipe_id   = rf.recipe_id
          AND rl."charged?"  = true
          AND rl.roast_date >= c.roast_week_start
          AND rl.facility_id = rf.facility_id
    ) roasted ON true
)
SELECT
    pr.recipe_id || '-' || pr.facility_id                               AS roast_blend_id,
    pr.recipe_id,
    pr.facility_id,
    pr.company_id,
    pr.in_stock_roasted,
    pr.total_ordered,
    pr.total_roasted,
    GREATEST(0, pr.total_ordered - pr.in_stock_roasted - pr.total_roasted)
                                                                        AS roasted_left,
    GREATEST(0, pr.total_ordered - pr.in_stock_roasted - pr.total_roasted)
        / NULLIF(pr.retention_rate, 0)
        / NULLIF(pr.effective_charge_weight, 0)                         AS roasts_remaining,
    COALESCE((
        SELECT SUM(rbr.batches_remaining)
        FROM public.roast_batches_remaining rbr
        WHERE rbr.recipe_id   = pr.recipe_id
          AND rbr.facility_id = pr.facility_id
    ), 0)                                                               AS batches_remaining
FROM per_recipe pr;
