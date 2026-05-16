-- Revert: drop roast_batches_remaining and restore roast_detail_by_blend
-- to its original form (no batches_remaining column).
-- The per-component approach caused over-crediting of shared-origin roasting.
-- roast_detail_by_blend with CEIL(roasts_remaining) was correct and stable.

DROP VIEW IF EXISTS public.roast_detail_by_blend CASCADE;
DROP VIEW IF EXISTS public.roast_batches_remaining CASCADE;

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
    pr.recipe_id || '-' || pr.facility_id  AS roast_blend_id,
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
        / NULLIF(pr.effective_charge_weight, 0)
                                           AS roasts_remaining
FROM per_recipe pr;
