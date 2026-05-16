-- Replace roast_stock (single-row-per-recipe/origin) with roast_stock_log (append-only log)
--
-- Why a log:
--   • Entries are additive within the week — record multiple bins separately
--   • Corrections are possible via negative entries
--   • Auto-resets at roast-week boundary: only entries where
--     (created_at AT TIME ZONE facility_timezone)::date >= roast_week_start count
--   • Full audit trail of when stock was recorded and by whom
--
-- Views sum roast_stock_log entries for this roast-week only.
-- AppSheet UX: an "Add In-Stock Entry" form (select blend/origin, enter lbs).

-- ─── 1. Create roast_stock_log ────────────────────────────────────────────────

CREATE TABLE public.roast_stock_log (
    stock_log_id  text        NOT NULL DEFAULT (gen_random_uuid()::text),
    stock_type    text        NOT NULL,   -- 'blend' or 'origin'
    reference_id  text        NOT NULL,   -- recipe_id (blend) or origin_id (origin)
    facility_id   text        NOT NULL,
    company_id    text,
    lbs_in_stock  numeric     NOT NULL DEFAULT 0,
    created_at    timestamptz NOT NULL DEFAULT now(),
    created_by    text,
    updated_at    timestamptz NOT NULL DEFAULT now(),
    updated_by    text,
    CONSTRAINT roast_stock_log_pkey        PRIMARY KEY (stock_log_id),
    CONSTRAINT roast_stock_log_type_check  CHECK (stock_type IN ('blend', 'origin'))
);

-- ─── 2. Migrate existing roast_stock data as this-week opening entries ────────
-- Sets created_at = NOW() so entries appear in the current week's totals.
-- Users can verify and adjust; they will not carry forward past next week reset.

INSERT INTO public.roast_stock_log
    (stock_type, reference_id, facility_id, company_id, lbs_in_stock)
SELECT stock_type, reference_id, facility_id, company_id, in_stock_roasted
FROM public.roast_stock
WHERE in_stock_roasted > 0;

-- ─── 3. Drop views that depend on roast_stock, then drop roast_stock ─────────

DROP VIEW IF EXISTS public.roast_detail_by_blend;
DROP VIEW IF EXISTS public.roast_detail;
DROP TABLE IF EXISTS public.roast_stock;

-- ─── 4. Update roast_detail_by_blend VIEW ────────────────────────────────────
-- Sums roast_stock_log entries (stock_type = 'blend') for this roast-week.
-- timezone carried through calc CTE so the created_at comparison uses local date.

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
        -- Sum all blend-type log entries for this recipe recorded this roast-week
        SELECT COALESCE(SUM(rsl.lbs_in_stock), 0) AS in_stock_roasted
        FROM public.roast_stock_log rsl
        WHERE rsl.stock_type   = 'blend'
          AND rsl.reference_id = rf.recipe_id
          AND rsl.facility_id  = rf.facility_id
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

-- ─── 5. Update roast_detail VIEW ─────────────────────────────────────────────
-- in_stock_roasted = origin-type log entries this week
--                  + blend-type log entries × component percentage (additive)

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
        -- in_stock_roasted: origin-type log entries this week
        --                  + blend-type entries × component % (additive)
        COALESCE((
            SELECT SUM(rsl.lbs_in_stock)
            FROM public.roast_stock_log rsl
            WHERE rsl.stock_type   = 'origin'
              AND rsl.reference_id = of2.origin
              AND rsl.facility_id  = of2.facility_id
              AND (rsl.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start
        ), 0)
        + COALESCE((
            SELECT SUM(rsl.lbs_in_stock * rc.percentage)
            FROM public.roast_stock_log rsl
            JOIN public.recipe_components rc ON rsl.reference_id = rc.recipe_id
            WHERE rsl.stock_type   = 'blend'
              AND rc.coffee_item   = of2.origin
              AND rsl.facility_id  = of2.facility_id
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
