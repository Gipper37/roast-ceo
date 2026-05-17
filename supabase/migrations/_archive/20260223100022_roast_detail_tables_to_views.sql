-- Convert roast_detail_by_blend + roast_detail to views
--
-- Staleness bug: when the roast week rolls over, no trigger fires unless a roast/
-- order/recipe changes. Rows silently show last week's numbers. nudge_all_inventory()
-- only touches coffee_inventory / consumable_inventory, not these tables.
--
-- Solution: views are always live. Two new user-input tables replace the single
-- in_stock_roasted column that was the only user-input across both tables:
--
--   blend_in_stock  — Post-Blend / Single Origin facilities enter stock per recipe
--   origin_in_stock — Pre-Blend facilities enter stock per origin
--
-- roast_detail.in_stock_roasted = origin_in_stock + SUM(blend_in_stock × component %)
-- Both are additive: a mixed facility entering stock in both tables will see the
-- correct combined total.
--
-- Trigger chain (roast_log → order_details → recipe_components → tables) is removed.
-- AppSheet reads both views live; writes in_stock_roasted to blend_in_stock or
-- origin_in_stock depending on roast workflow.

-- ─── 1. Create blend_in_stock ────────────────────────────────────────────────

CREATE TABLE public.blend_in_stock (
    blend_stock_id   text        NOT NULL DEFAULT (gen_random_uuid()::text),
    recipe_id        text        NOT NULL,
    facility_id      text        NOT NULL,
    company_id       text,
    in_stock_roasted numeric     NOT NULL DEFAULT 0,
    updated_at       timestamptz NOT NULL DEFAULT now(),
    updated_by       text,
    CONSTRAINT blend_in_stock_pkey              PRIMARY KEY (blend_stock_id),
    CONSTRAINT blend_in_stock_recipe_facility   UNIQUE (recipe_id, facility_id)
);

-- ─── 2. Create origin_in_stock ───────────────────────────────────────────────

CREATE TABLE public.origin_in_stock (
    origin_stock_id  text        NOT NULL DEFAULT (gen_random_uuid()::text),
    origin_id        text        NOT NULL,   -- matches coffee_item in recipe_components
    facility_id      text        NOT NULL,
    company_id       text,
    in_stock_roasted numeric     NOT NULL DEFAULT 0,
    updated_at       timestamptz NOT NULL DEFAULT now(),
    updated_by       text,
    CONSTRAINT origin_in_stock_pkey             PRIMARY KEY (origin_stock_id),
    CONSTRAINT origin_in_stock_origin_facility  UNIQUE (origin_id, facility_id)
);

-- ─── 3. Migrate existing in_stock_roasted values ─────────────────────────────
-- blend_in_stock gets current values; origin_in_stock starts empty.

INSERT INTO public.blend_in_stock (recipe_id, facility_id, company_id, in_stock_roasted)
SELECT recipe_id, facility_id, company_id, COALESCE(in_stock_roasted, 0)
FROM public.roast_detail_by_blend
WHERE recipe_id IS NOT NULL AND facility_id IS NOT NULL
ON CONFLICT (recipe_id, facility_id) DO UPDATE
    SET in_stock_roasted = EXCLUDED.in_stock_roasted;

-- ─── 4. Drop trigger chain (triggers on other tables writing to these tables) ─

DROP TRIGGER IF EXISTS trg_roast_log_smart_update ON public.roast_log;
DROP TRIGGER IF EXISTS trigger_order_update        ON public.order_details;
DROP TRIGGER IF EXISTS trigger_recipe_update       ON public.recipe_components;

-- ─── 5. Drop both tables (CASCADE drops their own triggers) ──────────────────

DROP TABLE IF EXISTS public.roast_detail_by_blend CASCADE;
DROP TABLE IF EXISTS public.roast_detail CASCADE;

-- ─── 6. Drop orphaned functions ──────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.calculate_roast_by_blend();
DROP FUNCTION IF EXISTS public.calculate_roast_detail_origin();
DROP FUNCTION IF EXISTS public.update_roast_detail_by_components();
DROP FUNCTION IF EXISTS public.update_roast_detail_from_order_trigger();
DROP FUNCTION IF EXISTS public.update_roast_detail_from_recipe_trigger();

-- ─── 7. Create roast_detail_by_blend VIEW ────────────────────────────────────
-- Key: recipe_id || '-' || facility_id (stable, replaces old text roast_blend_id)
-- in_stock_roasted read from blend_in_stock (LEFT JOIN → 0 if no entry yet)
-- LATERAL joins compute total_ordered / total_roasted once; roasted_left and
-- roasts_remaining reuse those values.
-- Charge weight: average of last 5 charged roasts for that recipe (same logic
-- as the old trigger function).

CREATE VIEW public.roast_detail_by_blend
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
    -- Hybrid catalog: company-wide recipes (facility_id IS NULL) + facility-specific
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
        COALESCE(bis.in_stock_roasted, 0)  AS in_stock_roasted,
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
    LEFT JOIN public.blend_in_stock bis
           ON bis.recipe_id   = rf.recipe_id
          AND bis.facility_id = rf.facility_id
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

-- ─── 8. Create roast_detail VIEW ─────────────────────────────────────────────
-- Key: origin || '-' || facility_id
-- in_stock_roasted = origin_in_stock (direct) + blend_in_stock × component % (derived)
--   Both additive: a mixed facility entering stock in both tables sees correct total.
-- total_roasted = direct origin roasts + Pre-Blend component share (same split
--   as the old calculate_roast_detail_origin() trigger function).

CREATE VIEW public.roast_detail
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
    -- All distinct coffee origins used in recipes at each facility
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
        -- in_stock_roasted: direct origin stock + blend-derived stock (additive)
        COALESCE((
            SELECT ois.in_stock_roasted
            FROM public.origin_in_stock ois
            WHERE ois.origin_id   = of2.origin
              AND ois.facility_id = of2.facility_id
        ), 0)
        + COALESCE((
            SELECT SUM(bis.in_stock_roasted * rc.percentage)
            FROM public.blend_in_stock bis
            JOIN public.recipe_components rc ON bis.recipe_id = rc.recipe_id
            WHERE rc.coffee_item  = of2.origin
              AND bis.facility_id = of2.facility_id
        ), 0)                                                       AS in_stock_roasted,
        -- total_ordered: open order weight attributable to this origin
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
        -- total_roasted: direct (Single Origin / Post-Blend) + Pre-Blend component share
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
