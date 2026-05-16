-- Migration 00128: Add facility scoping and moving averages to all order_graphs views
--
-- All four views now scoped by (facility_id, week/month/year).
-- Primary key columns added to each view for AppSheet.
--
-- Moving average windows:
--   order_graphs_week              → 26-week  (≈ 6 calendar months)
--   order_graphs_weekly_avg_by_month → 12-month (matches legacy AppSheet VC formula)
--   order_graphs_year              → 3-year

DROP VIEW IF EXISTS public.order_graphs_weekly_avg_by_month;
DROP VIEW IF EXISTS public.order_graphs_weekly_avg_by_year;
DROP VIEW IF EXISTS public.order_graphs_year;
DROP VIEW IF EXISTS public.order_graphs_week;

-- ── 1. order_graphs_week ─────────────────────────────────────────────────────────────
CREATE VIEW public.order_graphs_week AS
WITH weeks AS (
    SELECT generate_series(
        date_trunc('week', (SELECT MIN(order_date) FROM public.orders WHERE order_status != 'Canceled')::timestamp),
        date_trunc('week', (CURRENT_DATE + interval '52 weeks')::timestamp),
        '7 days'::interval
    )::date AS week_start
),
spine AS (
    SELECT f.facility_id, f.company_id, w.week_start
    FROM weeks w
    CROSS JOIN public.facilities f
),
agg AS (
    SELECT
        s.facility_id,
        s.company_id,
        s.week_start,
        COALESCE(SUM(od.total_price),       0) AS revenue,
        COALESCE(SUM(od.unit_cost_at_sale), 0) AS cogs,
        COALESCE(SUM(od.total_price) - SUM(od.unit_cost_at_sale), 0) AS gross_profit,
        ROUND(COALESCE(SUM(od.unit_cost_at_sale), 0)
            / NULLIF(SUM(od.total_price), 0) * 100, 1)                AS cogs_pct,
        ROUND((COALESCE(SUM(od.total_price), 0) - COALESCE(SUM(od.unit_cost_at_sale), 0))
            / NULLIF(SUM(od.total_price), 0) * 100, 1)                AS margin_pct,
        COUNT(DISTINCT o.order_id)                                     AS order_count,
        ROUND(COALESCE(SUM(od.roasted_weight), 0)::numeric, 2)         AS total_roasted_weight
    FROM spine s
    LEFT JOIN public.orders o
           ON o.facility_id = s.facility_id
          AND date_trunc('week', o.order_date::timestamp)::date = s.week_start
          AND o.order_status != 'Canceled'
    LEFT JOIN public.order_details od ON od.order_id = o.order_id
    GROUP BY s.facility_id, s.company_id, s.week_start
)
SELECT
    facility_id || '_' || week_start            AS week_report_id,
    week_start,
    facility_id,
    company_id,
    revenue,
    cogs,
    gross_profit,
    cogs_pct,
    margin_pct,
    order_count,
    total_roasted_weight,
    -- 26-week (≈ 6-month) moving averages
    ROUND(AVG(revenue)              OVER w26, 2) AS revenue_6mo_avg,
    ROUND(AVG(cogs)                 OVER w26, 2) AS cogs_6mo_avg,
    ROUND(AVG(gross_profit)         OVER w26, 2) AS gross_profit_6mo_avg,
    ROUND(AVG(cogs_pct)             OVER w26, 1) AS cogs_pct_6mo_avg,
    ROUND(AVG(margin_pct)           OVER w26, 1) AS margin_pct_6mo_avg,
    ROUND(AVG(total_roasted_weight) OVER w26, 2) AS roasted_weight_6mo_avg
FROM agg
WINDOW w26 AS (
    PARTITION BY facility_id
    ORDER BY week_start
    ROWS BETWEEN 25 PRECEDING AND CURRENT ROW
)
ORDER BY week_start DESC, facility_id;


-- ── 2. order_graphs_weekly_avg_by_month ──────────────────────────────────────────────
CREATE VIEW public.order_graphs_weekly_avg_by_month AS
WITH monthly AS (
    SELECT
        facility_id,
        company_id,
        date_trunc('month', week_start)::date AS month_start,
        ROUND(AVG(revenue),             2) AS avg_weekly_revenue,
        ROUND(AVG(cogs),                2) AS avg_weekly_cogs,
        ROUND(AVG(gross_profit),        2) AS avg_weekly_gross_profit,
        ROUND(AVG(cogs_pct),            1) AS avg_cogs_pct,
        ROUND(AVG(margin_pct),          1) AS avg_margin_pct,
        ROUND(AVG(order_count),         1) AS avg_weekly_order_count,
        ROUND(AVG(total_roasted_weight)::numeric, 2) AS avg_weekly_roasted_weight,
        COUNT(*)                           AS weeks_in_month
    FROM public.order_graphs_week
    WHERE week_start <= CURRENT_DATE
    GROUP BY facility_id, company_id, date_trunc('month', week_start)
)
SELECT
    facility_id || '_' || month_start       AS month_report_id,
    month_start,
    facility_id,
    company_id,
    avg_weekly_revenue,
    avg_weekly_cogs,
    avg_weekly_gross_profit,
    avg_cogs_pct,
    avg_margin_pct,
    avg_weekly_order_count,
    avg_weekly_roasted_weight,
    weeks_in_month,
    -- 12-month rolling averages (matches legacy AppSheet VC formula)
    ROUND(AVG(avg_weekly_revenue)         OVER w12, 2) AS revenue_12mo_avg,
    ROUND(AVG(avg_weekly_cogs)            OVER w12, 2) AS cogs_12mo_avg,
    ROUND(AVG(avg_cogs_pct)              OVER w12, 1) AS cogs_pct_12mo_avg,
    ROUND(AVG(avg_margin_pct)            OVER w12, 1) AS margin_pct_12mo_avg,
    ROUND(AVG(avg_weekly_roasted_weight) OVER w12, 2) AS roasted_weight_12mo_avg
FROM monthly
WINDOW w12 AS (
    PARTITION BY facility_id
    ORDER BY month_start
    ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
)
ORDER BY month_start DESC, facility_id;


-- ── 3. order_graphs_weekly_avg_by_year ───────────────────────────────────────────────
CREATE VIEW public.order_graphs_weekly_avg_by_year AS
WITH yearly AS (
    SELECT
        facility_id,
        company_id,
        EXTRACT(year FROM week_start)::integer AS year_start,
        ROUND(AVG(revenue),             2) AS avg_weekly_revenue,
        ROUND(AVG(cogs),                2) AS avg_weekly_cogs,
        ROUND(AVG(gross_profit),        2) AS avg_weekly_gross_profit,
        ROUND(AVG(cogs_pct),            1) AS avg_cogs_pct,
        ROUND(AVG(margin_pct),          1) AS avg_margin_pct,
        ROUND(AVG(order_count),         1) AS avg_weekly_order_count,
        ROUND(AVG(total_roasted_weight)::numeric, 2) AS avg_weekly_roasted_weight,
        COUNT(*)                           AS weeks_in_year
    FROM public.order_graphs_week
    WHERE week_start <= CURRENT_DATE
    GROUP BY facility_id, company_id, EXTRACT(year FROM week_start)
)
SELECT
    facility_id || '_' || year_start        AS year_report_id,
    year_start,
    facility_id,
    company_id,
    avg_weekly_revenue,
    avg_weekly_cogs,
    avg_weekly_gross_profit,
    avg_cogs_pct,
    avg_margin_pct,
    avg_weekly_order_count,
    avg_weekly_roasted_weight,
    weeks_in_year,
    -- 3-year moving averages (matches legacy AppSheet VC formula)
    ROUND(AVG(avg_weekly_revenue)         OVER w3, 2) AS revenue_3yr_avg,
    ROUND(AVG(avg_weekly_cogs)            OVER w3, 2) AS cogs_3yr_avg,
    ROUND(AVG(avg_cogs_pct)              OVER w3, 1) AS cogs_pct_3yr_avg,
    ROUND(AVG(avg_margin_pct)            OVER w3, 1) AS margin_pct_3yr_avg,
    ROUND(AVG(avg_weekly_roasted_weight) OVER w3, 2) AS roasted_weight_3yr_avg
FROM yearly
WINDOW w3 AS (
    PARTITION BY facility_id
    ORDER BY year_start
    ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
)
ORDER BY year_start DESC, facility_id;


-- ── 4. order_graphs_year ─────────────────────────────────────────────────────────────
CREATE VIEW public.order_graphs_year AS
WITH yearly AS (
    SELECT
        facility_id,
        company_id,
        EXTRACT(year FROM week_start)::integer AS year_start,
        ROUND(SUM(revenue),             2) AS total_revenue,
        ROUND(SUM(cogs),                2) AS total_cogs,
        ROUND(SUM(gross_profit),        2) AS total_gross_profit,
        ROUND(SUM(cogs)         / NULLIF(SUM(revenue), 0) * 100, 1) AS cogs_pct,
        ROUND(SUM(gross_profit) / NULLIF(SUM(revenue), 0) * 100, 1) AS margin_pct,
        SUM(order_count)                   AS total_orders,
        ROUND(SUM(total_roasted_weight)::numeric, 2) AS total_roasted_weight,
        COUNT(*)                           AS weeks_in_year
    FROM public.order_graphs_week
    WHERE week_start <= CURRENT_DATE
    GROUP BY facility_id, company_id, EXTRACT(year FROM week_start)
)
SELECT
    facility_id || '_' || year_start        AS year_report_id,
    year_start,
    facility_id,
    company_id,
    total_revenue,
    total_cogs,
    total_gross_profit,
    cogs_pct,
    margin_pct,
    total_orders,
    total_roasted_weight,
    weeks_in_year,
    -- 3-year moving averages
    ROUND(AVG(total_revenue)         OVER w3, 2) AS revenue_3yr_avg,
    ROUND(AVG(total_cogs)            OVER w3, 2) AS cogs_3yr_avg,
    ROUND(AVG(cogs_pct)             OVER w3, 1) AS cogs_pct_3yr_avg,
    ROUND(AVG(margin_pct)           OVER w3, 1) AS margin_pct_3yr_avg,
    ROUND(AVG(total_roasted_weight) OVER w3, 2) AS roasted_weight_3yr_avg
FROM yearly
WINDOW w3 AS (
    PARTITION BY facility_id
    ORDER BY year_start
    ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
)
ORDER BY year_start DESC, facility_id;
