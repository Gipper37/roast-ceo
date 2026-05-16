-- Drop all views that depend on roast_log.charge_weight as numeric
DROP VIEW IF EXISTS public.roast_detail_by_blend;
DROP VIEW IF EXISTS public.roast_detail;
DROP VIEW IF EXISTS public.weekly_grand_total;
DROP VIEW IF EXISTS public.weekly_coffee_stock_by_origin;
DROP VIEW IF EXISTS public.monthly_coffee_usage;
DROP VIEW IF EXISTS public.monthly_coffee_usage_by_origin;

-- Change charge_weight to text so it can accept a UUID ref from AppSheet
-- The trigger resolves UUID → numeric and stamps the number back before saving
ALTER TABLE public.roast_log
    ALTER COLUMN charge_weight TYPE text USING charge_weight::text;

-- Update trigger to resolve UUID ref → numeric, stamp back, then compute roasted_weight
CREATE OR REPLACE FUNCTION public.trg_stamp_roasted_weight()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_retention     numeric;
    v_charge_weight numeric;
BEGIN
    -- Try to resolve charge_weight as a charge_weight_options.id UUID ref
    SELECT charge_weight INTO v_charge_weight
    FROM public.charge_weight_options
    WHERE id = NEW.charge_weight
    LIMIT 1;

    -- Fall back to casting directly if it's already a numeric string
    IF v_charge_weight IS NULL AND NEW.charge_weight ~ '^[0-9]+(\.[0-9]+)?$' THEN
        v_charge_weight := NEW.charge_weight::numeric;
    END IF;

    -- Stamp the resolved numeric value back so the column stores the number, not the UUID
    IF v_charge_weight IS NOT NULL THEN
        NEW.charge_weight := v_charge_weight::text;
    END IF;

    -- Tier 1: facility-specific retention override
    SELECT value_number INTO v_retention FROM company_parameters
    WHERE parameter_id = '1de271df' AND facility_id = NEW.facility_id LIMIT 1;

    -- Tier 2: system default
    IF v_retention IS NULL OR v_retention = 0 THEN
        SELECT amount INTO v_retention FROM standard_parameters WHERE parameters_id = '1de271df' LIMIT 1;
    END IF;

    -- Tier 3: hardcoded fallback
    IF v_retention IS NULL OR v_retention = 0 THEN v_retention := 0.82; END IF;

    NEW.roasted_weight := ROUND(COALESCE(v_charge_weight, 0) * v_retention, 2);
    RETURN NEW;
END;
$$;

-- Recreate monthly_coffee_usage with ::numeric casts
CREATE OR REPLACE VIEW public.monthly_coffee_usage AS
SELECT
    (facility_id || '_' || date_trunc('month', roast_date)::date) AS month_usage_id,
    date_trunc('month', roast_date)::date                          AS month_start,
    facility_id,
    company_id,
    ROUND(SUM(charge_weight::numeric), 2)                          AS green_used_lbs,
    ROUND(SUM(roasted_weight), 2)                                  AS lbs_roasted,
    COUNT(*)::integer                                              AS batch_count,
    ROUND((SUM(roasted_weight) / NULLIF(SUM(charge_weight::numeric), 0)) * 100, 1) AS retention_pct
FROM public.roast_log rl
GROUP BY date_trunc('month', roast_date), facility_id, company_id;

-- Recreate monthly_coffee_usage_by_origin with ::numeric casts
CREATE OR REPLACE VIEW public.monthly_coffee_usage_by_origin AS
WITH roast_by_origin AS (
    SELECT
        rl.roast_date,
        rl.origin_id,
        rl.charge_weight::numeric          AS green_used_lbs,
        rl.roasted_weight                  AS lbs_roasted,
        rl.facility_id,
        rl.company_id
    FROM public.roast_log rl
    WHERE rl.origin_id IS NOT NULL

    UNION ALL

    SELECT
        rl.roast_date,
        rc.coffee_item                          AS origin_id,
        (rl.charge_weight::numeric * rc.percentage) AS green_used_lbs,
        (rl.roasted_weight * rc.percentage)     AS lbs_roasted,
        rl.facility_id,
        rl.company_id
    FROM public.roast_log rl
    JOIN public.recipe_components rc ON rc.recipe_id = rl.recipe_id
    WHERE rl.origin_id IS NULL AND rl.recipe_id IS NOT NULL
)
SELECT
    (r.facility_id || '_' || r.origin_id || '_' || date_trunc('month', r.roast_date)::date) AS month_origin_id,
    date_trunc('month', r.roast_date)::date AS month_start,
    r.origin_id,
    ci.origin                               AS origin_name,
    r.facility_id,
    r.company_id,
    ROUND(SUM(r.green_used_lbs), 2)         AS green_used_lbs,
    ROUND(SUM(r.lbs_roasted), 2)            AS lbs_roasted
FROM roast_by_origin r
LEFT JOIN public.coffee_inventory ci ON ci.origin_id = r.origin_id AND ci.facility_id = r.facility_id
GROUP BY date_trunc('month', r.roast_date), r.origin_id, ci.origin, r.facility_id, r.company_id;

-- Recreate weekly_grand_total with ::numeric cast
CREATE OR REPLACE VIEW public.weekly_grand_total AS
WITH facility_config AS (
    SELECT
        f.facility_id,
        f.company_id,
        COALESCE(NULLIF(f.time_zone, ''), 'UTC') AS timezone,
        COALESCE((
            SELECT cp.value_number::integer FROM company_parameters cp
            WHERE cp.parameter_id = 'RF1iFWjOh7' AND cp.facility_id = f.facility_id LIMIT 1
        ), 1) AS roast_target_day,
        COALESCE((
            SELECT cp.value_number FROM company_parameters cp
            WHERE cp.parameter_id = '1de271df' AND cp.facility_id = f.facility_id LIMIT 1
        ), 0.82) AS retention_rate,
        COALESCE((
            SELECT cp.value_number::integer FROM company_parameters cp
            WHERE cp.parameter_id = 'orders_reset_day' AND cp.facility_id = f.facility_id LIMIT 1
        ), (
            SELECT sp.amount::integer FROM standard_parameters sp
            WHERE sp.parameters_id = 'orders_reset_day' LIMIT 1
        ), 6) AS orders_reset_day
    FROM public.facilities f
),
calc AS (
    SELECT
        fc.facility_id,
        fc.company_id,
        fc.retention_rate,
        (CURRENT_TIMESTAMP AT TIME ZONE fc.timezone)::date
            - (((EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fc.timezone)::date)::integer
                - fc.orders_reset_day) + 7) % 7) AS order_week_start,
        (CURRENT_TIMESTAMP AT TIME ZONE fc.timezone)::date
            - (((EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fc.timezone)::date)::integer
                - fc.roast_target_day) + 7) % 7) AS roast_week_start
    FROM facility_config fc
)
SELECT
    c.facility_id                                         AS open_order_total_id,
    c.facility_id,
    c.company_id,
    COALESCE((
        SELECT SUM(od.roasted_weight)
        FROM order_details od JOIN orders o ON od.order_id = o.order_id
        WHERE o.order_date >= c.order_week_start AND o.facility_id = c.facility_id
    ), 0)                                                 AS total_ordered_roasted,
    COALESCE((
        SELECT SUM(od.roasted_weight)
        FROM order_details od JOIN orders o ON od.order_id = o.order_id
        WHERE o.order_date >= c.order_week_start AND o.facility_id = c.facility_id
    ), 0) / NULLIF(c.retention_rate::double precision, 0) AS total_ordered_green,
    COALESCE((
        SELECT SUM(rl.roasted_weight)
        FROM roast_log rl
        WHERE rl."charged?" = true AND rl.roast_date >= c.roast_week_start AND rl.facility_id = c.facility_id
    ), 0)                                                 AS total_roasted,
    COALESCE((
        SELECT SUM(rl.charge_weight::numeric)
        FROM roast_log rl
        WHERE rl."charged?" = true AND rl.roast_date >= c.roast_week_start AND rl.facility_id = c.facility_id
    ), 0)                                                 AS total_roasted_green
FROM calc c;

-- Recreate weekly_coffee_stock_by_origin with ::numeric casts
CREATE OR REPLACE VIEW public.weekly_coffee_stock_by_origin AS
WITH direct_roasts AS (
    SELECT
        rl.roast_date::date  AS roast_date,
        rl.origin_id,
        rl.facility_id,
        rl.charge_weight::numeric AS green_lbs
    FROM public.roast_log rl
    JOIN public.roast_recipes rr ON rr.recipe_id = rl.recipe_id
    WHERE rl.origin_id IS NOT NULL
      AND rl."charged?" = true
      AND rr.roast_type IS DISTINCT FROM 'Pre-Blend'
),
blend_roasts AS (
    SELECT
        rl.roast_date::date                      AS roast_date,
        rc.coffee_item                           AS origin_id,
        rl.facility_id,
        (rl.charge_weight::numeric * rc.percentage) AS green_lbs
    FROM public.roast_log rl
    JOIN public.roast_recipes rr ON rr.recipe_id = rl.recipe_id
    JOIN public.recipe_components rc ON rc.recipe_id = rl.recipe_id
    WHERE rl.origin_id IS NULL
      AND rr.roast_type = 'Pre-Blend'
      AND rl."charged?" = true
),
all_roasts AS (
    SELECT * FROM direct_roasts
    UNION ALL
    SELECT * FROM blend_roasts
),
all_purchases AS (
    SELECT
        sr.date_received AS received_date,
        p.origin         AS origin_id,
        p.facility_id,
        p.amount         AS purchased_lbs
    FROM public.coffee_inventory_purchased p
    JOIN public.shipment_received sr ON sr.shipment_id = p.shipment_id
    WHERE sr.date_received IS NOT NULL
      AND COALESCE(sr.voided, false) = false
),
origins AS (
    SELECT DISTINCT
        ci.origin_id,
        ci.facility_id,
        ci.company_id,
        ci.bag_size,
        ci.origin AS origin_name
    FROM public.coffee_inventory ci
    WHERE ci.origin_id IS NOT NULL
),
date_spine AS (
    SELECT
        o.origin_id,
        o.facility_id,
        o.company_id,
        o.bag_size,
        o.origin_name,
        gs.week_start::date AS week_start
    FROM origins o
    JOIN LATERAL generate_series(
        date_trunc('week', now() - interval '1 year'),
        date_trunc('week', now()),
        interval '7 days'
    ) gs(week_start) ON true
)
SELECT
    (ds.facility_id || '_' || ds.origin_id || '_' || ds.week_start) AS week_stock_id,
    ds.week_start,
    ds.origin_id,
    ds.origin_name,
    ds.facility_id,
    ds.company_id,
    GREATEST(0,
        COALESCE((
            SELECT ci.inventory_count_bags * ci.bag_size::numeric
            FROM public.coffee_inventory ci
            WHERE ci.origin_id = ds.origin_id AND ci.facility_id = ds.facility_id LIMIT 1
        ), 0)
        + COALESCE((
            SELECT SUM(p.purchased_lbs)
            FROM all_purchases p
            WHERE p.origin_id = ds.origin_id AND p.facility_id = ds.facility_id
              AND p.received_date > (
                SELECT COALESCE(ci.last_inventory, '1970-01-01'::date)
                FROM public.coffee_inventory ci
                WHERE ci.origin_id = ds.origin_id AND ci.facility_id = ds.facility_id LIMIT 1
              )
              AND p.received_date <= ds.week_start
        ), 0)
        - COALESCE((
            SELECT SUM(r.green_lbs)
            FROM all_roasts r
            WHERE r.origin_id = ds.origin_id AND r.facility_id = ds.facility_id
              AND r.roast_date > (
                SELECT COALESCE(ci.last_inventory, '1970-01-01'::date)
                FROM public.coffee_inventory ci
                WHERE ci.origin_id = ds.origin_id AND ci.facility_id = ds.facility_id LIMIT 1
              )
              AND r.roast_date <= ds.week_start
        ), 0)
    ) AS stock_lbs
FROM date_spine ds;

-- Recreate roast_detail with ::numeric casts
CREATE OR REPLACE VIEW public.roast_detail AS
WITH facility_params AS (
    SELECT
        f.facility_id,
        f.company_id,
        COALESCE(NULLIF(f.time_zone, ''), 'Pacific/Honolulu') AS timezone,
        COALESCE((
            SELECT cp.value_number::integer FROM company_parameters cp
            WHERE cp.parameter_id = 'RF1iFWjOh7' AND cp.facility_id = f.facility_id LIMIT 1
        ), 4) AS roast_reset_day,
        COALESCE((
            SELECT cp.value_number FROM company_parameters cp
            WHERE cp.parameter_id = '761fd894' AND cp.facility_id = f.facility_id LIMIT 1
        ), 25) AS charge_weight,
        COALESCE((
            SELECT cp.value_number FROM company_parameters cp
            WHERE cp.parameter_id = '1de271df' AND cp.facility_id = f.facility_id LIMIT 1
        ), 0.82) AS retention_rate
    FROM public.facilities f
),
calc AS (
    SELECT
        fp.facility_id,
        fp.company_id,
        fp.timezone,
        fp.charge_weight,
        fp.retention_rate,
        (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date
            - (((EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date)::integer
                - fp.roast_reset_day) + 7) % 7) AS roast_week_start
    FROM facility_params fp
),
origin_facility AS (
    SELECT DISTINCT
        rc.coffee_item AS origin,
        f.facility_id,
        f.company_id
    FROM public.recipe_components rc
    JOIN public.roast_recipes rr ON rc.recipe_id = rr.recipe_id
    JOIN public.facilities f ON f.company_id = rr.company_id
        AND (rr.facility_id IS NULL OR rr.facility_id = f.facility_id)
),
per_origin AS (
    SELECT
        of2.origin,
        of2.facility_id,
        of2.company_id,
        (
            COALESCE((
                SELECT SUM(rsl.lbs_in_stock)
                FROM public.roast_stock_log rsl
                WHERE rsl.origin_id = of2.origin AND rsl.facility_id = of2.facility_id
                  AND (rsl.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start
            ), 0)
            + COALESCE((
                SELECT SUM(rsl.lbs_in_stock * rc.percentage)
                FROM public.roast_stock_log rsl
                JOIN public.recipe_components rc ON rsl.blend_id = rc.recipe_id
                WHERE rc.coffee_item = of2.origin AND rsl.facility_id = of2.facility_id
                  AND (rsl.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start
            ), 0)
        ) AS in_stock_roasted,
        COALESCE((
            SELECT SUM(od.quantity * p.weight_lbs * rc.percentage)
            FROM order_details od
            JOIN orders o ON od.order_id = o.order_id
            JOIN products p ON od.product_id = p.product_id
            JOIN public.recipe_components rc ON p.recipe_id = rc.recipe_id
            WHERE rc.coffee_item = of2.origin AND o.order_status = 'Open'
              AND o.facility_id = of2.facility_id
        ), 0) AS total_ordered,
        (
            COALESCE((
                SELECT SUM(rl.roasted_weight)
                FROM public.roast_log rl
                WHERE rl.origin_id = of2.origin AND rl."charged?" = true
                  AND rl.roast_date >= c.roast_week_start AND rl.facility_id = of2.facility_id
            ), 0)
            + COALESCE((
                SELECT SUM(rl.roasted_weight * rc.percentage)
                FROM public.roast_log rl
                JOIN public.roast_recipes rr ON rl.recipe_id = rr.recipe_id
                JOIN public.recipe_components rc ON rl.recipe_id = rc.recipe_id
                WHERE rr.roast_type = 'Pre-Blend' AND rc.coffee_item = of2.origin
                  AND rl."charged?" = true AND rl.roast_date >= c.roast_week_start
                  AND rl.facility_id = of2.facility_id
            ), 0)
        ) AS total_roasted,
        c.retention_rate,
        COALESCE((
            SELECT AVG(recent.charge_weight_num)
            FROM (
                SELECT rl.charge_weight::numeric AS charge_weight_num
                FROM public.roast_log rl
                WHERE rl.origin_id = of2.origin AND rl.facility_id = of2.facility_id
                  AND rl.charge_weight ~ '^[0-9]+(\.[0-9]+)?$'
                  AND rl.charge_weight::numeric > 0
                ORDER BY rl.roast_date DESC
                LIMIT 5
            ) recent
        ), c.charge_weight, 25) AS effective_charge_weight
    FROM origin_facility of2
    JOIN calc c ON c.facility_id = of2.facility_id
)
SELECT
    (origin || '-' || facility_id)                         AS roast_detail_id,
    origin,
    facility_id,
    company_id,
    in_stock_roasted,
    total_roasted,
    total_ordered,
    GREATEST(0, total_ordered - in_stock_roasted - total_roasted) AS final_roasted_weight,
    GREATEST(0, total_ordered - in_stock_roasted - total_roasted)
        / NULLIF(retention_rate, 0)                        AS green_to_roast,
    GREATEST(0, total_ordered - in_stock_roasted - total_roasted)
        / NULLIF(retention_rate, 0)
        / NULLIF(effective_charge_weight, 0)               AS roasts_remaining
FROM per_origin;

-- Recreate roast_detail_by_blend with ::numeric casts
CREATE OR REPLACE VIEW public.roast_detail_by_blend AS
WITH facility_params AS (
    SELECT
        f.facility_id,
        f.company_id,
        COALESCE(NULLIF(f.time_zone, ''), 'Pacific/Honolulu') AS timezone,
        COALESCE((
            SELECT cp.value_number::integer FROM company_parameters cp
            WHERE cp.parameter_id = 'RF1iFWjOh7' AND cp.facility_id = f.facility_id LIMIT 1
        ), 4) AS roast_reset_day,
        COALESCE((
            SELECT cp.value_number FROM company_parameters cp
            WHERE cp.parameter_id = '761fd894' AND cp.facility_id = f.facility_id LIMIT 1
        ), 25) AS charge_weight,
        COALESCE((
            SELECT cp.value_number FROM company_parameters cp
            WHERE cp.parameter_id = '1de271df' AND cp.facility_id = f.facility_id LIMIT 1
        ), 0.82) AS retention_rate
    FROM public.facilities f
),
calc AS (
    SELECT
        fp.facility_id,
        fp.company_id,
        fp.timezone,
        fp.charge_weight,
        fp.retention_rate,
        (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date
            - (((EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date)::integer
                - fp.roast_reset_day) + 7) % 7) AS roast_week_start
    FROM facility_params fp
),
recipe_facility AS (
    SELECT
        rr.recipe_id,
        f.facility_id,
        f.company_id
    FROM public.roast_recipes rr
    JOIN public.facilities f ON f.company_id = rr.company_id
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
        COALESCE((
            SELECT AVG(recent.charge_weight_num)
            FROM (
                SELECT rl.charge_weight::numeric AS charge_weight_num
                FROM public.roast_log rl
                WHERE rl.recipe_id = rf.recipe_id AND rl.facility_id = rf.facility_id
                  AND rl.charge_weight ~ '^[0-9]+(\.[0-9]+)?$'
                  AND rl.charge_weight::numeric > 0
                ORDER BY rl.roast_date DESC
                LIMIT 5
            ) recent
        ), c.charge_weight, 25) AS effective_charge_weight
    FROM recipe_facility rf
    JOIN calc c ON c.facility_id = rf.facility_id
    LEFT JOIN LATERAL (
        SELECT COALESCE(SUM(rsl.lbs_in_stock), 0) AS in_stock_roasted
        FROM public.roast_stock_log rsl
        WHERE rsl.blend_id = rf.recipe_id AND rsl.facility_id = rf.facility_id
          AND (rsl.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start
    ) stock ON true
    LEFT JOIN LATERAL (
        SELECT SUM(od.roasted_weight) AS total_ordered
        FROM order_details od
        JOIN orders o ON od.order_id = o.order_id
        JOIN products p ON od.product_id = p.product_id
        WHERE p.recipe_id = rf.recipe_id AND o.order_status = 'Open'
          AND o.facility_id = rf.facility_id
    ) ordered ON true
    LEFT JOIN LATERAL (
        SELECT SUM(rl.roasted_weight) AS total_roasted
        FROM public.roast_log rl
        WHERE rl.recipe_id = rf.recipe_id AND rl."charged?" = true
          AND rl.roast_date >= c.roast_week_start AND rl.facility_id = rf.facility_id
    ) roasted ON true
)
SELECT
    (recipe_id || '-' || facility_id)          AS roast_blend_id,
    recipe_id,
    facility_id,
    company_id,
    in_stock_roasted,
    total_ordered,
    total_roasted,
    GREATEST(0, total_ordered - in_stock_roasted - total_roasted) AS roasted_left,
    GREATEST(0, total_ordered - in_stock_roasted - total_roasted)
        / NULLIF(retention_rate, 0)
        / NULLIF(effective_charge_weight, 0)   AS roasts_remaining
FROM per_recipe;
