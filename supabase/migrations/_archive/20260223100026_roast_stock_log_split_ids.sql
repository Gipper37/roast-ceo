-- Replace roast_stock_log.reference_id with blend_id + origin_id
--
-- reference_id was polymorphic (recipe_id or origin_id depending on stock_type).
-- Split into two explicit FK columns so AppSheet can show a proper dropdown for
-- each type (blend → roast_recipes, origin → coffee_inventory).
-- AppSheet UX: select stock_type first, then the relevant column appears.
-- No data migration needed — no history exists yet.

-- ─── 1. Drop views that depend on roast_stock_log ────────────────────────────

DROP VIEW IF EXISTS public.roast_detail_by_blend;
DROP VIEW IF EXISTS public.roast_detail;

-- ─── 2. Drop and recreate roast_stock_log ────────────────────────────────────

DROP TABLE IF EXISTS public.roast_stock_log;

CREATE TABLE public.roast_stock_log (
    stock_log_id  text        NOT NULL DEFAULT (gen_random_uuid()::text),
    stock_type    text        NOT NULL,   -- 'blend' or 'origin'
    blend_id      text,                  -- recipe_id from roast_recipes (when stock_type = 'blend')
    origin_id     text,                  -- origin_id from coffee_inventory (when stock_type = 'origin')
    facility_id   text        NOT NULL,
    company_id    text,
    lbs_in_stock  numeric     NOT NULL DEFAULT 0,
    created_at    timestamptz NOT NULL DEFAULT now(),
    created_by    text,
    updated_at    timestamptz NOT NULL DEFAULT now(),
    updated_by    text,
    CONSTRAINT roast_stock_log_pkey        PRIMARY KEY (stock_log_id),
    CONSTRAINT roast_stock_log_type_check  CHECK (stock_type IN ('blend', 'origin')),
    CONSTRAINT roast_stock_log_ids_check   CHECK (
        (stock_type = 'blend'  AND blend_id  IS NOT NULL AND origin_id IS NULL) OR
        (stock_type = 'origin' AND origin_id IS NOT NULL AND blend_id  IS NULL)
    ),
    CONSTRAINT roast_stock_log_blend_fk    FOREIGN KEY (blend_id)
        REFERENCES public.roast_recipes (recipe_id),
    CONSTRAINT roast_stock_log_origin_fk   FOREIGN KEY (origin_id)
        REFERENCES public.coffee_inventory (origin_id)
);

-- ─── 3. Recreate roast_detail_by_blend VIEW ───────────────────────────────────

CREATE OR REPLACE VIEW public.roast_detail_by_blend
WITH (security_invoker='true') AS
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
                - fp.roast_reset_day + 7) % 7))  AS roast_week_start
    FROM facility_params fp
),
recipe_facility AS (
    SELECT rr.recipe_id, f.facility_id, f.company_id
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
        COALESCE(stock.in_stock_roasted, 0) AS in_stock_roasted,
        COALESCE(ordered.total_ordered, 0)  AS total_ordered,
        COALESCE(roasted.total_roasted, 0)  AS total_roasted,
        c.retention_rate,
        COALESCE(
            (SELECT AVG(charge_weight)
             FROM (
                 SELECT charge_weight
                 FROM public.roast_log
                 WHERE recipe_id    = rf.recipe_id
                   AND facility_id  = rf.facility_id
                   AND charge_weight > 0
                 ORDER BY roast_date DESC
                 LIMIT 5
             ) recent),
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
    recipe_id || '-' || facility_id                                AS roast_blend_id,
    recipe_id,
    facility_id,
    company_id,
    in_stock_roasted,
    total_ordered,
    total_roasted,
    GREATEST(0, total_ordered - in_stock_roasted - total_roasted) AS roasted_left,
    GREATEST(0, total_ordered - in_stock_roasted - total_roasted)
        / NULLIF(retention_rate, 0)
        / NULLIF(effective_charge_weight, 0)                       AS roasts_remaining
FROM per_recipe;

-- ─── 4. Recreate roast_detail VIEW ───────────────────────────────────────────

CREATE OR REPLACE VIEW public.roast_detail
WITH (security_invoker='true') AS
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
                - fp.roast_reset_day + 7) % 7))  AS roast_week_start
    FROM facility_params fp
),
origin_facility AS (
    SELECT DISTINCT
        rc.coffee_item AS origin,
        f.facility_id,
        f.company_id
    FROM public.recipe_components rc
    JOIN public.roast_recipes rr ON rc.recipe_id = rr.recipe_id
    JOIN public.facilities f
      ON f.company_id = rr.company_id
     AND (rr.facility_id IS NULL OR rr.facility_id = f.facility_id)
),
per_origin AS (
    SELECT
        of2.origin,
        of2.facility_id,
        of2.company_id,
        COALESCE((
            SELECT SUM(rsl.lbs_in_stock)
            FROM public.roast_stock_log rsl
            WHERE rsl.origin_id   = of2.origin
              AND rsl.facility_id = of2.facility_id
              AND (rsl.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start
        ), 0)
        + COALESCE((
            SELECT SUM(rsl.lbs_in_stock * rc.percentage)
            FROM public.roast_stock_log rsl
            JOIN public.recipe_components rc ON rsl.blend_id = rc.recipe_id
            WHERE rc.coffee_item  = of2.origin
              AND rsl.facility_id = of2.facility_id
              AND (rsl.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start
        ), 0)                                                       AS in_stock_roasted,
        COALESCE((
            SELECT SUM(od.quantity * p.weight_lbs * rc.percentage)
            FROM public.order_details od
            JOIN public.orders o   ON od.order_id  = o.order_id
            JOIN public.products p ON od.product_id = p.product_id
            JOIN public.recipe_components rc ON p.recipe_id = rc.recipe_id
            WHERE rc.coffee_item  = of2.origin
              AND o.order_status  = 'Open'
              AND o.facility_id   = of2.facility_id
        ), 0)                                                       AS total_ordered,
        COALESCE((
            SELECT SUM(rl.roasted_weight)
            FROM public.roast_log rl
            WHERE rl.origin_id   = of2.origin
              AND rl."charged?"  = true
              AND rl.roast_date >= c.roast_week_start
              AND rl.facility_id = of2.facility_id
        ), 0)
        + COALESCE((
            SELECT SUM(rl.roasted_weight * rc.percentage)
            FROM public.roast_log rl
            JOIN public.roast_recipes rr ON rl.recipe_id = rr.recipe_id
            JOIN public.recipe_components rc ON rl.recipe_id = rc.recipe_id
            WHERE rr.roast_type  = 'Pre-Blend'
              AND rc.coffee_item = of2.origin
              AND rl."charged?"  = true
              AND rl.roast_date >= c.roast_week_start
              AND rl.facility_id = of2.facility_id
        ), 0)                                                       AS total_roasted,
        c.retention_rate,
        COALESCE(
            (SELECT AVG(charge_weight)
             FROM (
                 SELECT charge_weight
                 FROM public.roast_log
                 WHERE origin_id   = of2.origin
                   AND facility_id = of2.facility_id
                   AND charge_weight > 0
                 ORDER BY roast_date DESC
                 LIMIT 5
             ) recent),
            c.charge_weight,
            25
        ) AS effective_charge_weight
    FROM origin_facility of2
    JOIN calc c ON c.facility_id = of2.facility_id
)
SELECT
    origin || '-' || facility_id                                   AS roast_detail_id,
    origin,
    facility_id,
    company_id,
    in_stock_roasted,
    total_roasted,
    total_ordered,
    GREATEST(0, total_ordered - in_stock_roasted - total_roasted) AS final_roasted_weight,
    GREATEST(0, total_ordered - in_stock_roasted - total_roasted)
        / NULLIF(retention_rate, 0)                                AS green_to_roast,
    GREATEST(0, total_ordered - in_stock_roasted - total_roasted)
        / NULLIF(retention_rate, 0)
        / NULLIF(effective_charge_weight, 0)                       AS roasts_remaining
FROM per_origin;
