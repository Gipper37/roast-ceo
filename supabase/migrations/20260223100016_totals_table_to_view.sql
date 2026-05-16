-- Convert totals from table to view + add open_backlog column
--
-- Why now: amount_packed (the only user-input column) was dropped in 00015.
-- All remaining columns are pure calculations, so a view is strictly better:
--   • No stale data — delivered orders can't linger in left_to_pack
--   • No trigger chain to maintain
--   • AppSheet always reads live values
--
-- What changes for AppSheet:
--   1. Sync schema on totals (metadata columns gone; totals_id is now text)
--   2. Update key column to totals_id
--   3. Remove any formulas referencing created_at / updated_at / amount_packed / left_to_bag

-- ─── 1. Drop trigger chain (triggers on other tables; CASCADE handles totals trigger) ───

DROP TRIGGER IF EXISTS trg_sync_totals_from_order ON public.order_details;
DROP TRIGGER IF EXISTS trg_sync_totals_status      ON public.orders;

-- ─── 2. Drop the table (CASCADE drops trg_calculate_totals which lived ON totals) ──────

DROP TABLE IF EXISTS public.totals CASCADE;

-- ─── 3. Drop orphaned functions ───────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.calculate_totals_columns();
DROP FUNCTION IF EXISTS public.update_totals_from_order();
DROP FUNCTION IF EXISTS public.update_totals_from_order_status();

-- ─── 4. Create totals VIEW ────────────────────────────────────────────────────────────
-- Same name → AppSheet data-source config unchanged.
-- Key: product_id || '-' || facility_id (stable text, replaces old random UUID totals_id).
-- Base: hybrid product catalog (company-wide facility_id IS NULL + facility-specific).

CREATE VIEW public.totals
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
        -- Orders week start: same DOW formula used in calculate_totals_columns()
        ((CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date
            - ((EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date)::integer
                - fp.orders_reset_day + 7) % 7))  AS orders_week_start
    FROM facility_params fp
),
product_facility AS (
    -- Hybrid catalog: company-wide products (facility_id IS NULL) + facility-specific
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

    -- Total: all orders this orders-week (any status)
    COALESCE((
        SELECT SUM(od.quantity)
        FROM public.order_details od
        JOIN public.orders o ON od.order_id = o.order_id
        WHERE od.product_id  = pf.product_id
          AND o.order_date  >= c.orders_week_start
          AND o.facility_id  = pf.facility_id
    ), 0)                                      AS total,

    -- Left To Pack: Open orders this orders-week
    COALESCE((
        SELECT SUM(od.quantity)
        FROM public.order_details od
        JOIN public.orders o ON od.order_id = o.order_id
        WHERE od.product_id  = pf.product_id
          AND o.order_date  >= c.orders_week_start
          AND o.order_status = 'Open'
          AND o.facility_id  = pf.facility_id
    ), 0)                                      AS left_to_pack,

    -- Open Backlog: Open orders from BEFORE this orders-week (carryover)
    COALESCE((
        SELECT SUM(od.quantity)
        FROM public.order_details od
        JOIN public.orders o ON od.order_id = o.order_id
        WHERE od.product_id  = pf.product_id
          AND o.order_date   < c.orders_week_start
          AND o.order_status = 'Open'
          AND o.facility_id  = pf.facility_id
    ), 0)                                      AS open_backlog,

    -- Packed Qty: Packed orders this orders-week
    COALESCE((
        SELECT SUM(od.quantity)
        FROM public.order_details od
        JOIN public.orders o ON od.order_id = o.order_id
        WHERE od.product_id  = pf.product_id
          AND o.order_date  >= c.orders_week_start
          AND o.order_status = 'Packed'
          AND o.facility_id  = pf.facility_id
    ), 0)                                      AS packed_qty,

    -- Delivered Qty: Delivered orders this orders-week
    COALESCE((
        SELECT SUM(od.quantity)
        FROM public.order_details od
        JOIN public.orders o ON od.order_id = o.order_id
        WHERE od.product_id  = pf.product_id
          AND o.order_date  >= c.orders_week_start
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
