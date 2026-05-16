-- Migration 00173: Fix missing is_active / status filters across views and functions
-- Issues:
--   1. monthly_coffee_usage — missing charged?=true filter
--   2. monthly_coffee_usage_by_origin — missing charged?=true on both UNION branches
--   3. monthly_consumable_stock_by_item — all_purchases CTE missing voided=false filter
--   4. totals — total and recent_avg_week subqueries missing order_status <> 'Canceled'
--   5. weekly_grand_total — total_ordered_roasted/green subqueries missing order_status <> 'Canceled'
--   6. handle_manual_inventory_update — v_purchased_lbs missing voided=false filter

-- ── 1. monthly_coffee_usage ──────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.monthly_coffee_usage AS
SELECT
    (facility_id || '_' || (date_trunc('month', roast_date))::date) AS month_usage_id,
    (date_trunc('month', roast_date))::date AS month_start,
    facility_id,
    company_id,
    round(sum((charge_weight)::numeric), 2) AS green_used_lbs,
    round(sum(roasted_weight), 2) AS lbs_roasted,
    count(*)::integer AS batch_count,
    round((sum(roasted_weight) / NULLIF(sum((charge_weight)::numeric), 0::numeric)) * 100::numeric, 1) AS retention_pct
FROM roast_log rl
WHERE rl."charged?" = true
GROUP BY date_trunc('month', roast_date), facility_id, company_id;

-- ── 2. monthly_coffee_usage_by_origin ───────────────────────────────────────
CREATE OR REPLACE VIEW public.monthly_coffee_usage_by_origin AS
WITH roast_by_origin AS (
    SELECT
        rl.roast_date,
        rl.origin_id,
        (rl.charge_weight)::numeric AS green_used_lbs,
        rl.roasted_weight AS lbs_roasted,
        rl.facility_id,
        rl.company_id
    FROM roast_log rl
    WHERE rl.origin_id IS NOT NULL
      AND rl."charged?" = true
    UNION ALL
    SELECT
        rl.roast_date,
        rc.coffee_item AS origin_id,
        ((rl.charge_weight)::numeric * rc.percentage) AS green_used_lbs,
        (rl.roasted_weight * rc.percentage) AS lbs_roasted,
        rl.facility_id,
        rl.company_id
    FROM roast_log rl
    JOIN recipe_components rc ON rc.recipe_id = rl.recipe_id
    WHERE rl.origin_id IS NULL
      AND rl.recipe_id IS NOT NULL
      AND rl."charged?" = true
)
SELECT
    ((((r.facility_id || '_') || r.origin_id) || '_') || (date_trunc('month', r.roast_date))::date) AS month_origin_id,
    (date_trunc('month', r.roast_date))::date AS month_start,
    r.origin_id,
    ci.origin AS origin_name,
    r.facility_id,
    r.company_id,
    round(sum(r.green_used_lbs), 2) AS green_used_lbs,
    round(sum(r.lbs_roasted), 2) AS lbs_roasted
FROM roast_by_origin r
LEFT JOIN coffee_inventory ci ON ci.origin_id = r.origin_id AND ci.facility_id = r.facility_id
GROUP BY date_trunc('month', r.roast_date), r.origin_id, ci.origin, r.facility_id, r.company_id;

-- ── 3. monthly_consumable_stock_by_item ─────────────────────────────────────
CREATE OR REPLACE VIEW public.monthly_consumable_stock_by_item AS
WITH all_usage AS (
    SELECT
        o.order_date AS usage_date,
        pc.consumable_id,
        od.facility_id,
        sum(od.quantity * pc.quantity) AS units_used
    FROM order_details od
    JOIN orders o ON o.order_id = od.order_id
    JOIN product_consumables pc ON pc.product_id = od.product_id
    WHERE o.order_status <> 'Canceled'
    GROUP BY o.order_date, pc.consumable_id, od.facility_id
), all_purchases AS (
    SELECT
        sr.date_received AS received_date,
        p.consumable_inventory_item AS consumable_id,
        p.facility_id,
        (p.amount)::numeric AS purchased_units
    FROM consumable_inventory_purchased p
    JOIN shipment_received sr ON sr.shipment_id = p.shipment_id
    WHERE sr.date_received IS NOT NULL
      AND COALESCE(sr.voided, false) = false
), consumables AS (
    SELECT DISTINCT
        consumable_inventory_id AS consumable_id,
        facility_id,
        company_id,
        consumable_inventory_item AS item_name
    FROM consumable_inventory
), consumable_first_event AS (
    SELECT events.consumable_id, events.facility_id, min(events.event_date) AS first_event
    FROM (
        SELECT consumable_id, facility_id, inventory_date AS event_date FROM consumable_inventory_history
        UNION ALL
        SELECT consumable_id, facility_id, received_date FROM all_purchases
        UNION ALL
        SELECT consumable_id, facility_id, usage_date FROM all_usage
    ) events
    GROUP BY events.consumable_id, events.facility_id
), date_spine AS (
    SELECT
        c.consumable_id, c.facility_id, c.company_id, c.item_name,
        gs.month_start::date AS month_start
    FROM consumables c
    JOIN consumable_first_event fe ON fe.consumable_id = c.consumable_id AND fe.facility_id = c.facility_id
    JOIN LATERAL generate_series(
        date_trunc('month', fe.first_event::timestamp)::timestamptz,
        date_trunc('month', now()),
        '1 mon'::interval
    ) gs(month_start) ON true
    WHERE fe.first_event < 'infinity'::date
)
SELECT
    (((ds.facility_id || '_') || ds.consumable_id) || '_') || ds.month_start AS month_stock_id,
    ds.month_start,
    ds.consumable_id,
    ds.item_name,
    ds.facility_id,
    ds.company_id,
    GREATEST(0::numeric, round(
        COALESCE(anchor.anchor_count, 0::numeric)
        + COALESCE(purch.purchased_units, 0::numeric)
        - COALESCE(used.units_used, 0::numeric),
        0
    )) AS in_stock
FROM date_spine ds
LEFT JOIN LATERAL (
    SELECT h.inventory_date AS anchor_date, h.inventory_count AS anchor_count
    FROM consumable_inventory_history h
    WHERE h.consumable_id = ds.consumable_id
      AND h.facility_id = ds.facility_id
      AND h.inventory_date < (ds.month_start + '1 mon'::interval)::date
    ORDER BY h.inventory_date DESC
    LIMIT 1
) anchor ON true
LEFT JOIN LATERAL (
    SELECT COALESCE(sum(ap.purchased_units), 0::numeric) AS purchased_units
    FROM all_purchases ap
    WHERE ap.consumable_id = ds.consumable_id
      AND ap.facility_id = ds.facility_id
      AND ap.received_date > COALESCE(anchor.anchor_date, '2000-01-01'::date)
      AND ap.received_date < (ds.month_start + '1 mon'::interval)::date
) purch ON true
LEFT JOIN LATERAL (
    SELECT COALESCE(sum(au.units_used), 0::numeric) AS units_used
    FROM all_usage au
    WHERE au.consumable_id = ds.consumable_id
      AND au.facility_id = ds.facility_id
      AND au.usage_date > COALESCE(anchor.anchor_date, '2000-01-01'::date)
      AND au.usage_date < (ds.month_start + '1 mon'::interval)::date
) used ON true;

-- ── 4. totals — add Canceled filter to total and recent_avg_week ─────────────
CREATE OR REPLACE VIEW public.totals AS
WITH facility_params AS (
    SELECT
        f.facility_id,
        f.company_id,
        COALESCE(NULLIF(f.time_zone, ''), 'Pacific/Honolulu') AS timezone,
        COALESCE(
            (SELECT cp.value_number::integer FROM company_parameters cp
             WHERE cp.parameter_id = 'orders_reset_day' AND cp.facility_id = f.facility_id LIMIT 1),
            (SELECT sp.amount::integer FROM standard_parameters sp
             WHERE sp.parameters_id = 'orders_reset_day' LIMIT 1),
            6
        ) AS orders_reset_day
    FROM facilities f
), calc AS (
    SELECT
        fp.facility_id, fp.company_id, fp.timezone,
        (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date
            - (((EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date)::integer
                - fp.orders_reset_day) + 7) % 7) AS orders_week_start
    FROM facility_params fp
), product_facility AS (
    SELECT p.product_id, f.facility_id, f.company_id
    FROM products p
    JOIN facilities f ON p.company_id = f.company_id
        AND (p.facility_id IS NULL OR p.facility_id = f.facility_id)
)
SELECT
    (pf.product_id || '-' || pf.facility_id) AS totals_id,
    pf.product_id,
    pf.facility_id,
    pf.company_id,
    COALESCE((
        SELECT sum(od.quantity)
        FROM order_details od
        JOIN orders o ON od.order_id = o.order_id
        WHERE od.product_id = pf.product_id
          AND o.order_date >= c.orders_week_start
          AND o.facility_id = pf.facility_id
          AND o.order_status <> 'Canceled'
    ), 0::numeric) AS total,
    COALESCE((
        SELECT sum(od.quantity)
        FROM order_details od
        JOIN orders o ON od.order_id = o.order_id
        WHERE od.product_id = pf.product_id
          AND o.order_status = 'Open'
          AND o.facility_id = pf.facility_id
    ), 0::numeric) AS left_to_pack,
    COALESCE((
        SELECT sum(od.quantity)
        FROM order_details od
        JOIN orders o ON od.order_id = o.order_id
        WHERE od.product_id = pf.product_id
          AND o.order_date < c.orders_week_start
          AND o.order_status = 'Open'
          AND o.facility_id = pf.facility_id
    ), 0::numeric) AS open_backlog,
    COALESCE((
        SELECT sum(od.quantity)
        FROM order_details od
        JOIN orders o ON od.order_id = o.order_id
        WHERE od.product_id = pf.product_id
          AND o.order_status = 'Packed'
          AND (o.status_changed_at AT TIME ZONE c.timezone)::date >= c.orders_week_start
          AND o.facility_id = pf.facility_id
    ), 0::numeric) AS packed_qty,
    COALESCE((
        SELECT sum(od.quantity)
        FROM order_details od
        JOIN orders o ON od.order_id = o.order_id
        WHERE od.product_id = pf.product_id
          AND o.order_status = 'Delivered'
          AND (o.status_changed_at AT TIME ZONE c.timezone)::date >= c.orders_week_start
          AND o.facility_id = pf.facility_id
    ), 0::numeric) AS delivered_qty,
    COALESCE((
        SELECT avg(sub.weekly_sum)
        FROM (
            SELECT sum(od2.quantity) AS weekly_sum
            FROM order_details od2
            JOIN orders o2 ON od2.order_id = o2.order_id
            WHERE od2.product_id = pf.product_id
              AND o2.order_date >= (c.orders_week_start - '42 days'::interval)
              AND o2.order_date < c.orders_week_start
              AND o2.facility_id = pf.facility_id
              AND o2.order_status <> 'Canceled'
            GROUP BY date_trunc('week', o2.order_date::timestamptz)
        ) sub
    ), 0::numeric) AS recent_avg_week
FROM product_facility pf
JOIN calc c ON c.facility_id = pf.facility_id;

-- ── 5. weekly_grand_total — add Canceled filter to order subqueries ──────────
CREATE OR REPLACE VIEW public.weekly_grand_total AS
WITH facility_config AS (
    SELECT
        f.facility_id,
        f.company_id,
        COALESCE(NULLIF(f.time_zone, ''), 'UTC') AS timezone,
        COALESCE(
            (SELECT cp.value_number::integer FROM company_parameters cp
             WHERE cp.parameter_id = 'RF1iFWjOh7' AND cp.facility_id = f.facility_id LIMIT 1),
            1
        ) AS roast_target_day,
        COALESCE(
            (SELECT cp.value_number FROM company_parameters cp
             WHERE cp.parameter_id = '1de271df' AND cp.facility_id = f.facility_id LIMIT 1),
            0.82
        ) AS retention_rate,
        COALESCE(
            (SELECT cp.value_number::integer FROM company_parameters cp
             WHERE cp.parameter_id = 'orders_reset_day' AND cp.facility_id = f.facility_id LIMIT 1),
            (SELECT sp.amount::integer FROM standard_parameters sp
             WHERE sp.parameters_id = 'orders_reset_day' LIMIT 1),
            6
        ) AS orders_reset_day
    FROM facilities f
), calc AS (
    SELECT
        fc.facility_id, fc.company_id, fc.retention_rate,
        (CURRENT_TIMESTAMP AT TIME ZONE fc.timezone)::date
            - (((EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fc.timezone)::date)::integer
                - fc.orders_reset_day) + 7) % 7) AS order_week_start,
        (CURRENT_TIMESTAMP AT TIME ZONE fc.timezone)::date
            - (((EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fc.timezone)::date)::integer
                - fc.roast_target_day) + 7) % 7) AS roast_week_start
    FROM facility_config fc
)
SELECT
    facility_id AS open_order_total_id,
    facility_id,
    company_id,
    COALESCE((
        SELECT sum(od.roasted_weight)
        FROM order_details od
        JOIN orders o ON od.order_id = o.order_id
        WHERE o.order_date >= c.order_week_start
          AND o.facility_id = c.facility_id
          AND o.order_status <> 'Canceled'
    ), 0::double precision) AS total_ordered_roasted,
    COALESCE((
        SELECT sum(od.roasted_weight)
        FROM order_details od
        JOIN orders o ON od.order_id = o.order_id
        WHERE o.order_date >= c.order_week_start
          AND o.facility_id = c.facility_id
          AND o.order_status <> 'Canceled'
    ), 0::double precision) / NULLIF(retention_rate::double precision, 0) AS total_ordered_green,
    COALESCE((
        SELECT sum(rl.roasted_weight)
        FROM roast_log rl
        WHERE rl."charged?" = true
          AND rl.roast_date >= c.roast_week_start
          AND rl.facility_id = c.facility_id
    ), 0::numeric) AS total_roasted,
    COALESCE((
        SELECT sum(rl.charge_weight::numeric)
        FROM roast_log rl
        WHERE rl."charged?" = true
          AND rl.roast_date >= c.roast_week_start
          AND rl.facility_id = c.facility_id
    ), 0::numeric) AS total_roasted_green
FROM calc c;

-- ── 6. handle_manual_inventory_update — add voided filter ───────────────────
CREATE OR REPLACE FUNCTION public.handle_manual_inventory_update()
RETURNS trigger LANGUAGE plpgsql AS $function$
DECLARE
    v_bag_size            NUMERIC;
    v_purchased_lbs       NUMERIC;
    v_roasted_direct_lbs  NUMERIC;
    v_roasted_blend_lbs   NUMERIC;
    v_last_inventory_date DATE;
BEGIN
    -- 1. Bag size (text → numeric)
    v_bag_size := COALESCE(NEW.bag_size::numeric, 154);

    -- 2. Rolling metrics
    NEW.par           := public.calculate_par(NEW.origin_id);
    NEW.restock_level := public.calculate_restock_level(NEW.origin_id);

    -- 3. Baseline
    v_last_inventory_date := COALESCE(NEW.last_inventory::DATE, '2000-01-01');
    NEW.inventory_lbs     := COALESCE(NEW.inventory_count_bags, 0) * v_bag_size;

    -- 4. Inflows (exclude voided shipments)
    SELECT COALESCE(SUM(p.amount), 0) INTO v_purchased_lbs
    FROM coffee_inventory_purchased p
    JOIN shipment_received s ON p.shipment_id = s.shipment_id
    WHERE p.origin = NEW.origin_id
      AND s.date_received IS NOT NULL
      AND s.date_received::DATE > v_last_inventory_date
      AND COALESCE(s.voided, false) = false
      AND p.facility_id = NEW.facility_id;

    -- 5a. Direct roasts
    SELECT COALESCE(SUM(rl.charge_weight::numeric), 0) INTO v_roasted_direct_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    WHERE rl.origin_id = NEW.origin_id
      AND rl.roast_date::DATE > v_last_inventory_date
      AND rl."charged?" = TRUE
      AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend')
      AND rl.facility_id = NEW.facility_id;

    -- 5b. Blend roasts
    SELECT COALESCE(SUM(rl.charge_weight::numeric * rc.percentage), 0) INTO v_roasted_blend_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
    WHERE rc.coffee_item = NEW.origin_id
      AND rr.roast_type = 'Pre-Blend'
      AND rl.roast_date::DATE > v_last_inventory_date
      AND rl."charged?" = TRUE
      AND rl.facility_id = NEW.facility_id;

    -- 6. In stock
    NEW.in_stock_lbs := GREATEST(0, (NEW.inventory_lbs + v_purchased_lbs - v_roasted_direct_lbs - v_roasted_blend_lbs));
    NEW.in_stock     := NEW.in_stock_lbs / NULLIF(v_bag_size, 0);

    -- 7. To order
    NEW.to_order_bags := GREATEST(0, COALESCE(NEW.par, 0) - NEW.in_stock);

    RETURN NEW;
END;
$function$;
