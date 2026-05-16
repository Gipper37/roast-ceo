-- Fix packed_qty / delivered_qty: use updated_at instead of order_date
--
-- Problem: order_date is when the order was placed. Backlog orders placed before
-- this orders-week would never appear in packed_qty/delivered_qty even after
-- being marked Packed or Delivered this week.
--
-- Solution: filter by (o.updated_at AT TIME ZONE timezone)::date >= orders_week_start
-- updated_at is stamped whenever order_status changes, so this correctly captures
-- "marked Packed/Delivered during this orders-week" regardless of order_date.
--
-- timezone is added to the calc CTE so the updated_at comparison uses the
-- facility's local date boundary (not UTC midnight).
--
-- Pipeline:
--   total         = ordered THIS week (any status, by order_date)
--   left_to_pack  = ALL Open orders (any date)
--   open_backlog  = Open orders placed before this week
--   packed_qty    = orders marked Packed during THIS week (by updated_at)
--   delivered_qty = orders marked Delivered during THIS week (by updated_at)
--   recent_avg_week = 6-week rolling average (by order_date)

CREATE OR REPLACE VIEW public.totals
WITH (security_invoker='true') AS
WITH facility_params AS (
    SELECT
        f.facility_id,
        f.company_id,
        COALESCE(NULLIF(f.time_zone, ''), 'Pacific/Honolulu') AS timezone,
        COALESCE(
            (SELECT cp.value_number::integer
             FROM public.company_parameters cp
             WHERE cp.parameter_id = 'orders_reset_day'
               AND cp.facility_id  = f.facility_id
             LIMIT 1),
            (SELECT sp.amount::integer
             FROM public.standard_parameters sp
             WHERE sp.parameters_id = 'orders_reset_day'
             LIMIT 1),
            6
        ) AS orders_reset_day
    FROM public.facilities f
),
calc AS (
    SELECT
        fp.facility_id,
        fp.company_id,
        fp.timezone,
        ((CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date
            - ((EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date)::integer
                - fp.orders_reset_day + 7) % 7))  AS orders_week_start
    FROM facility_params fp
),
product_facility AS (
    SELECT
        p.product_id,
        f.facility_id,
        f.company_id
    FROM public.products p
    JOIN public.facilities f
      ON p.company_id = f.company_id
     AND (p.facility_id IS NULL OR p.facility_id = f.facility_id)
)
SELECT
    pf.product_id || '-' || pf.facility_id    AS totals_id,
    pf.product_id,
    pf.facility_id,
    pf.company_id,

    -- Total: orders placed THIS orders-week (any status, by order_date)
    COALESCE((
        SELECT SUM(od.quantity)
        FROM public.order_details od
        JOIN public.orders o ON od.order_id = o.order_id
        WHERE od.product_id  = pf.product_id
          AND o.order_date  >= c.orders_week_start
          AND o.facility_id  = pf.facility_id
    ), 0)                                      AS total,

    -- Left To Pack: ALL Open orders (this week + carryover backlog)
    COALESCE((
        SELECT SUM(od.quantity)
        FROM public.order_details od
        JOIN public.orders o ON od.order_id = o.order_id
        WHERE od.product_id  = pf.product_id
          AND o.order_status = 'Open'
          AND o.facility_id  = pf.facility_id
    ), 0)                                      AS left_to_pack,

    -- Open Backlog: Open orders placed BEFORE this orders-week (subset of left_to_pack)
    COALESCE((
        SELECT SUM(od.quantity)
        FROM public.order_details od
        JOIN public.orders o ON od.order_id = o.order_id
        WHERE od.product_id  = pf.product_id
          AND o.order_date   < c.orders_week_start
          AND o.order_status = 'Open'
          AND o.facility_id  = pf.facility_id
    ), 0)                                      AS open_backlog,

    -- Packed Qty: orders marked Packed during THIS orders-week (by updated_at)
    COALESCE((
        SELECT SUM(od.quantity)
        FROM public.order_details od
        JOIN public.orders o ON od.order_id = o.order_id
        WHERE od.product_id  = pf.product_id
          AND o.order_status = 'Packed'
          AND (o.updated_at AT TIME ZONE c.timezone)::date >= c.orders_week_start
          AND o.facility_id  = pf.facility_id
    ), 0)                                      AS packed_qty,

    -- Delivered Qty: orders marked Delivered during THIS orders-week (by updated_at)
    COALESCE((
        SELECT SUM(od.quantity)
        FROM public.order_details od
        JOIN public.orders o ON od.order_id = o.order_id
        WHERE od.product_id  = pf.product_id
          AND o.order_status = 'Delivered'
          AND (o.updated_at AT TIME ZONE c.timezone)::date >= c.orders_week_start
          AND o.facility_id  = pf.facility_id
    ), 0)                                      AS delivered_qty,

    -- Recent Avg Week: 6-week rolling average (weeks before this orders-week, by order_date)
    COALESCE((
        SELECT AVG(weekly_sum) FROM (
            SELECT SUM(od2.quantity) AS weekly_sum
            FROM public.order_details od2
            JOIN public.orders o2 ON od2.order_id = o2.order_id
            WHERE od2.product_id  = pf.product_id
              AND o2.order_date  >= (c.orders_week_start - INTERVAL '42 days')
              AND o2.order_date   < c.orders_week_start
              AND o2.facility_id  = pf.facility_id
            GROUP BY date_trunc('week', o2.order_date)
        ) sub
    ), 0)                                      AS recent_avg_week

FROM product_facility pf
JOIN calc c ON c.facility_id = pf.facility_id;
