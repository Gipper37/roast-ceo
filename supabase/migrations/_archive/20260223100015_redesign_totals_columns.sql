-- Redesign totals table — status pipeline + configurable orders week
--
-- Problems fixed:
--   1. left_to_pack was all-time open orders; total was this calendar week (Monday).
--      Different denominators made columns inconsistent and confusing.
--   2. left_to_bag was never calculated in SQL (always 0). Its AppSheet formula
--      total − amount_packed depended on amount_packed, a manual-entry relic.
--   3. amount_packed is redundant now that order_status = 'Packed' exists.
--   4. Week reset was hardcoded to Monday (date_trunc). Now configurable via
--      company_parameters 'orders_reset_day' (default Saturday = 6).
--
-- New totals columns: total, left_to_pack, packed_qty, delivered_qty, recent_avg_week
-- All columns use the same v_orders_week_start boundary.
-- Trigger chain unchanged: status change → nudge → calculate_totals_columns().

-- ─── 1. order_statuses reference table ────────────────────────────────────────

CREATE TABLE public.order_statuses (
    status_id    text        NOT NULL,
    display_name text        NOT NULL,
    sort_order   integer     DEFAULT 0,
    company_id   text,               -- NULL = global; nullable for future per-company statuses
    created_at   timestamptz DEFAULT now(),
    CONSTRAINT order_statuses_pkey PRIMARY KEY (status_id)
);

INSERT INTO public.order_statuses (status_id, display_name, sort_order) VALUES
    ('Open',      'Open',      1),
    ('Packed',    'Packed',    2),
    ('Delivered', 'Delivered', 3),
    ('Canceled',  'Canceled',  4);

-- ─── 2. Alter totals table ─────────────────────────────────────────────────────

ALTER TABLE public.totals DROP COLUMN IF EXISTS amount_packed;
ALTER TABLE public.totals DROP COLUMN IF EXISTS left_to_bag;
ALTER TABLE public.totals ADD COLUMN IF NOT EXISTS packed_qty    numeric DEFAULT 0;
ALTER TABLE public.totals ADD COLUMN IF NOT EXISTS delivered_qty numeric DEFAULT 0;

-- ─── 3. Seed global default for orders_reset_day in standard_parameters ───────
-- 6 = Saturday (DOW: 0=Sunday … 6=Saturday)
-- Per-facility overrides go in company_parameters with parameter_id = 'orders_reset_day'

INSERT INTO public.standard_parameters (parameters_id, parameter, amount, data_type)
VALUES ('orders_reset_day', 'Orders Week Reset Day', 6, 'number')
ON CONFLICT DO NOTHING;

-- ─── 4. Rewrite calculate_totals_columns() ────────────────────────────────────

CREATE OR REPLACE FUNCTION public.calculate_totals_columns()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_timezone          TEXT;
    v_orders_reset_day  INTEGER;
    v_orders_week_start DATE;
BEGIN
    -- 1. Timezone from facilities (empty-string guard matches nudge_all_inventory pattern)
    SELECT time_zone INTO v_timezone
    FROM public.facilities
    WHERE facility_id = NEW.facility_id;
    IF v_timezone IS NULL OR v_timezone = '' THEN v_timezone := 'Pacific/Honolulu'; END IF;

    -- 2. Orders week reset day: facility-specific → global default → hardcoded
    SELECT value_number::integer INTO v_orders_reset_day
    FROM public.company_parameters
    WHERE parameter_id = 'orders_reset_day'
      AND facility_id  = NEW.facility_id
    LIMIT 1;
    IF v_orders_reset_day IS NULL THEN
        SELECT amount::integer INTO v_orders_reset_day
        FROM public.standard_parameters
        WHERE parameters_id = 'orders_reset_day'
        LIMIT 1;
    END IF;
    IF v_orders_reset_day IS NULL THEN v_orders_reset_day := 6; END IF;

    -- 3. Orders week start (same DOW formula as roast_week_start)
    v_orders_week_start := (CURRENT_TIMESTAMP AT TIME ZONE v_timezone)::date
        - ((EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE v_timezone)::date)::integer
            - v_orders_reset_day + 7) % 7);

    -- 4. Total — all orders this orders-week (any status)
    NEW.total := COALESCE((
        SELECT SUM(od.quantity)
        FROM public.order_details od
        JOIN public.orders o ON od.order_id = o.order_id
        WHERE od.product_id  = NEW.product_id
          AND o.order_date  >= v_orders_week_start
          AND o.facility_id  = NEW.facility_id
    ), 0);

    -- 5. Left To Pack — Open orders this orders-week
    NEW.left_to_pack := COALESCE((
        SELECT SUM(od.quantity)
        FROM public.order_details od
        JOIN public.orders o ON od.order_id = o.order_id
        WHERE od.product_id  = NEW.product_id
          AND o.order_date  >= v_orders_week_start
          AND o.order_status = 'Open'
          AND o.facility_id  = NEW.facility_id
    ), 0);

    -- 6. Packed Qty — Packed orders this orders-week
    NEW.packed_qty := COALESCE((
        SELECT SUM(od.quantity)
        FROM public.order_details od
        JOIN public.orders o ON od.order_id = o.order_id
        WHERE od.product_id  = NEW.product_id
          AND o.order_date  >= v_orders_week_start
          AND o.order_status = 'Packed'
          AND o.facility_id  = NEW.facility_id
    ), 0);

    -- 7. Delivered Qty — Delivered orders this orders-week
    NEW.delivered_qty := COALESCE((
        SELECT SUM(od.quantity)
        FROM public.order_details od
        JOIN public.orders o ON od.order_id = o.order_id
        WHERE od.product_id  = NEW.product_id
          AND o.order_date  >= v_orders_week_start
          AND o.order_status = 'Delivered'
          AND o.facility_id  = NEW.facility_id
    ), 0);

    -- 8. Recent Avg Week — 6-week rolling average of weeks before this orders-week
    NEW.recent_avg_week := COALESCE((
        SELECT AVG(weekly_sum) FROM (
            SELECT SUM(od2.quantity) AS weekly_sum
            FROM public.order_details od2
            JOIN public.orders o2 ON od2.order_id = o2.order_id
            WHERE od2.product_id  = NEW.product_id
              AND o2.order_date  >= (v_orders_week_start - INTERVAL '42 days')
              AND o2.order_date   < v_orders_week_start
              AND o2.facility_id  = NEW.facility_id
            GROUP BY date_trunc('week', o2.order_date)
        ) sub
    ), 0);

    RETURN NEW;
END;
$$;

-- ─── 5. Update weekly_grand_total — configurable order_week_start ──────────────
-- Replaces hardcoded date_trunc('week') with the same DOW formula,
-- reading orders_reset_day from company_parameters (fallback standard_parameters → 6).

CREATE OR REPLACE VIEW public.weekly_grand_total
WITH (security_invoker='true') AS
WITH facility_config AS (
    SELECT
        f.facility_id,
        f.company_id,
        COALESCE(NULLIF(f.time_zone, ''), 'UTC') AS timezone,
        COALESCE(
            (SELECT cp.value_number::integer
             FROM public.company_parameters cp
             WHERE cp.parameter_id = 'RF1iFWjOh7'
               AND cp.facility_id  = f.facility_id
             LIMIT 1),
            1
        ) AS roast_target_day,
        COALESCE(
            (SELECT cp.value_number
             FROM public.company_parameters cp
             WHERE cp.parameter_id = '1de271df'
               AND cp.facility_id  = f.facility_id
             LIMIT 1),
            0.82
        ) AS retention_rate,
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
        fc.facility_id,
        fc.company_id,
        fc.retention_rate,
        -- Orders week start: configurable reset day (same DOW formula as roast_week_start)
        ((CURRENT_TIMESTAMP AT TIME ZONE fc.timezone)::date - (
            EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fc.timezone)::date)::integer
            - fc.orders_reset_day + 7
        ) % 7)                                                          AS order_week_start,
        -- Roast week start: unchanged
        ((CURRENT_TIMESTAMP AT TIME ZONE fc.timezone)::date - (
            EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fc.timezone)::date)::integer
            - fc.roast_target_day + 7
        ) % 7)                                                          AS roast_week_start
    FROM facility_config fc
)
SELECT
    c.facility_id                         AS open_order_total_id,
    c.facility_id,
    c.company_id,
    COALESCE(
        (SELECT SUM(od.roasted_weight)
         FROM public.order_details od
         JOIN public.orders o ON od.order_id = o.order_id
         WHERE o.order_date  >= c.order_week_start
           AND o.facility_id  = c.facility_id),
        0::double precision
    )                                     AS total_ordered_roasted,
    COALESCE(
        (SELECT SUM(od.roasted_weight)
         FROM public.order_details od
         JOIN public.orders o ON od.order_id = o.order_id
         WHERE o.order_date  >= c.order_week_start
           AND o.facility_id  = c.facility_id),
        0::double precision
    ) / NULLIF(c.retention_rate::double precision, 0::double precision)
                                          AS total_ordered_green,
    COALESCE(
        (SELECT SUM(rl.roasted_weight)
         FROM public.roast_log rl
         WHERE rl."charged?"   = true
           AND rl.roast_date   >= c.roast_week_start
           AND rl.facility_id   = c.facility_id),
        0::numeric
    )                                     AS total_roasted,
    COALESCE(
        (SELECT SUM(rl.charge_weight)
         FROM public.roast_log rl
         WHERE rl."charged?"   = true
           AND rl.roast_date   >= c.roast_week_start
           AND rl.facility_id   = c.facility_id),
        0::numeric
    )                                     AS total_roasted_green
FROM calc c;

-- ─── 6. Force recalculation of all totals rows ────────────────────────────────
-- Triggers trg_calculate_totals (BEFORE UPDATE) → calculate_totals_columns()
-- on every row, populating packed_qty and delivered_qty for the first time
-- and applying the new orders-week boundary to total, left_to_pack, recent_avg_week.

UPDATE public.totals SET updated_at = NOW();
