-- Fix packed_qty and delivered_qty: remove order_date filter
--
-- Root cause: filter was o.order_date >= orders_week_start, so backlog orders
-- placed before this orders-week never appeared in packed_qty / delivered_qty
-- even after being marked Packed or Delivered this week.
--
-- We don't store when an order's status changed — only when it was placed.
-- Removing the date filter is consistent with left_to_pack (all Open orders,
-- regardless of order_date). The full pipeline now reads:
--   total        = ordered THIS week (any status)   — planning/roasting target
--   left_to_pack = ALL Open orders                  — operational queue
--   open_backlog = Open orders from before this week (subset of left_to_pack)
--   packed_qty   = ALL Packed orders                — progress indicator
--   delivered_qty= ALL Delivered orders             — completion indicator

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

    -- Total: orders placed THIS orders-week (any status) — planning/roasting target
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

    -- Open Backlog: Open orders from BEFORE this orders-week (subset of left_to_pack)
    COALESCE((
        SELECT SUM(od.quantity)
        FROM public.order_details od
        JOIN public.orders o ON od.order_id = o.order_id
        WHERE od.product_id  = pf.product_id
          AND o.order_date   < c.orders_week_start
          AND o.order_status = 'Open'
          AND o.facility_id  = pf.facility_id
    ), 0)                                      AS open_backlog,

    -- Packed Qty: ALL Packed orders (no date filter — backlog orders count when packed)
    COALESCE((
        SELECT SUM(od.quantity)
        FROM public.order_details od
        JOIN public.orders o ON od.order_id = o.order_id
        WHERE od.product_id  = pf.product_id
          AND o.order_status = 'Packed'
          AND o.facility_id  = pf.facility_id
    ), 0)                                      AS packed_qty,

    -- Delivered Qty: ALL Delivered orders (no date filter — backlog orders count when delivered)
    COALESCE((
        SELECT SUM(od.quantity)
        FROM public.order_details od
        JOIN public.orders o ON od.order_id = o.order_id
        WHERE od.product_id  = pf.product_id
          AND o.order_status = 'Delivered'
          AND o.facility_id  = pf.facility_id
    ), 0)                                      AS delivered_qty,

    -- Recent Avg Week: 6-week rolling average (weeks before this orders-week)
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
