-- Consolidate blend_in_stock + origin_in_stock into a single roast_stock table
--
-- One table, stock_type distinguishes the two workflows:
--   stock_type = 'blend'  → reference_id is a recipe_id  (Post-Blend / Single Origin)
--   stock_type = 'origin' → reference_id is an origin_id (Pre-Blend)
--
-- UNIQUE (stock_type, reference_id, facility_id) ensures one row per
-- recipe-facility pair and one row per origin-facility pair.

-- ─── 1. Create roast_stock ────────────────────────────────────────────────────

CREATE TABLE public.roast_stock (
    stock_id         text        NOT NULL DEFAULT (gen_random_uuid()::text),
    stock_type       text        NOT NULL,  -- 'blend' or 'origin'
    reference_id     text        NOT NULL,  -- recipe_id (blend) or origin_id (origin)
    facility_id      text        NOT NULL,
    company_id       text,
    in_stock_roasted numeric     NOT NULL DEFAULT 0,
    updated_at       timestamptz NOT NULL DEFAULT now(),
    updated_by       text,
    CONSTRAINT roast_stock_pkey                 PRIMARY KEY (stock_id),
    CONSTRAINT roast_stock_type_ref_facility    UNIQUE (stock_type, reference_id, facility_id),
    CONSTRAINT roast_stock_type_check           CHECK (stock_type IN ('blend', 'origin'))
);

-- ─── 2. Migrate blend_in_stock data ──────────────────────────────────────────

INSERT INTO public.roast_stock (stock_type, reference_id, facility_id, company_id, in_stock_roasted)
SELECT 'blend', recipe_id, facility_id, company_id, in_stock_roasted
FROM public.blend_in_stock
ON CONFLICT (stock_type, reference_id, facility_id) DO UPDATE
    SET in_stock_roasted = EXCLUDED.in_stock_roasted;

-- origin_in_stock was empty (just created in 00022); no data to migrate.

-- ─── 3. Drop views that depend on the old tables, then drop the tables ────────
-- Views from migration 00022 reference blend_in_stock directly; must go first.

DROP VIEW IF EXISTS public.roast_detail_by_blend;
DROP VIEW IF EXISTS public.roast_detail;
DROP TABLE IF EXISTS public.blend_in_stock;
DROP TABLE IF EXISTS public.origin_in_stock;

-- ─── 4. Update roast_detail_by_blend VIEW ────────────────────────────────────

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
        COALESCE(rs.in_stock_roasted, 0)   AS in_stock_roasted,
        COALESCE(ordered.total_ordered, 0) AS total_ordered,
        COALESCE(roasted.total_roasted, 0) AS total_roasted,
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
    LEFT JOIN public.roast_stock rs
           ON rs.stock_type   = 'blend'
          AND rs.reference_id = rf.recipe_id
          AND rs.facility_id  = rf.facility_id
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

-- ─── 5. Update roast_detail VIEW ─────────────────────────────────────────────

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
        -- in_stock_roasted: direct origin entry + blend-derived (additive)
        COALESCE((
            SELECT rs.in_stock_roasted
            FROM public.roast_stock rs
            WHERE rs.stock_type   = 'origin'
              AND rs.reference_id = of2.origin
              AND rs.facility_id  = of2.facility_id
        ), 0)
        + COALESCE((
            SELECT SUM(rs.in_stock_roasted * rc.percentage)
            FROM public.roast_stock rs
            JOIN public.recipe_components rc ON rs.reference_id = rc.recipe_id
            WHERE rs.stock_type   = 'blend'
              AND rc.coffee_item  = of2.origin
              AND rs.facility_id  = of2.facility_id
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
