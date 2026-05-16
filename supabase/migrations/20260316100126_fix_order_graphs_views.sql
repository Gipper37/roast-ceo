-- Migration 00126: Rebuild order_graphs_week, order_graphs_weekly_avg_by_month,
-- and order_graphs_weekly_avg_by_year.
--
-- These views were reduced to bare date scaffolding (no data columns), causing
-- AppSheet to show only the week_start/month_start/year_start column with no data.
-- Rebuilt to mirror the summarized_weight_weekly pattern: dynamic date spine
-- LEFT JOINed to real order data, so every week/month/year shows metrics even
-- if there were no orders (zeros instead of gaps).

-- Drop dependent views first (order matters — avg views depend on order_graphs_week)
DROP VIEW IF EXISTS public.order_graphs_year CASCADE;
DROP VIEW IF EXISTS public.order_graphs_weekly_avg_by_year CASCADE;
DROP VIEW IF EXISTS public.order_graphs_weekly_avg_by_month CASCADE;
DROP VIEW IF EXISTS public.order_graphs_week CASCADE;

-- ── 1. order_graphs_week ─────────────────────────────────────────────────────────────
-- One row per week (Mon-based) from earliest order to 52 weeks ahead of today.
-- Mirrors monthly_financials but at weekly granularity.
CREATE VIEW public.order_graphs_week AS
WITH weeks AS (
    SELECT generate_series(
        date_trunc('week', (SELECT MIN(order_date) FROM public.orders WHERE order_status != 'Canceled')::timestamp),
        date_trunc('week', (CURRENT_DATE + interval '52 weeks')::timestamp),
        '7 days'::interval
    )::date AS week_start
)
SELECT
    w.week_start,
    COALESCE(SUM(od.total_price),        0) AS revenue,
    COALESCE(SUM(od.unit_cost_at_sale),  0) AS cogs,
    COALESCE(SUM(od.total_price) - SUM(od.unit_cost_at_sale), 0) AS gross_profit,
    ROUND(
        COALESCE(SUM(od.unit_cost_at_sale), 0)
        / NULLIF(SUM(od.total_price), 0) * 100, 1
    ) AS cogs_pct,
    ROUND(
        (COALESCE(SUM(od.total_price), 0) - COALESCE(SUM(od.unit_cost_at_sale), 0))
        / NULLIF(SUM(od.total_price), 0) * 100, 1
    ) AS margin_pct,
    COUNT(DISTINCT o.order_id)           AS order_count,
    COALESCE(SUM(od.roasted_weight),     0) AS total_roasted_weight
FROM weeks w
LEFT JOIN public.orders o
       ON date_trunc('week', o.order_date::timestamp)::date = w.week_start
      AND o.order_status != 'Canceled'
LEFT JOIN public.order_details od ON od.order_id = o.order_id
GROUP BY w.week_start
ORDER BY w.week_start DESC;


-- ── 2. order_graphs_weekly_avg_by_month ──────────────────────────────────────────────
-- For each calendar month, the average weekly values across all weeks in that month.
-- Useful for comparing "how does January typically perform vs July" etc.
CREATE VIEW public.order_graphs_weekly_avg_by_month AS
WITH weekly AS (
    SELECT
        date_trunc('month', week_start)::date AS month_start,
        revenue,
        cogs,
        gross_profit,
        cogs_pct,
        margin_pct,
        order_count,
        total_roasted_weight
    FROM public.order_graphs_week
    WHERE week_start <= CURRENT_DATE
)
SELECT
    month_start,
    ROUND(AVG(revenue),              2) AS avg_weekly_revenue,
    ROUND(AVG(cogs),                 2) AS avg_weekly_cogs,
    ROUND(AVG(gross_profit),         2) AS avg_weekly_gross_profit,
    ROUND(AVG(cogs_pct),             1) AS avg_cogs_pct,
    ROUND(AVG(margin_pct),           1) AS avg_margin_pct,
    ROUND(AVG(order_count),          1) AS avg_weekly_order_count,
    ROUND(AVG(total_roasted_weight)::numeric, 2) AS avg_weekly_roasted_weight,
    COUNT(*)                            AS weeks_in_month
FROM weekly
GROUP BY month_start
ORDER BY month_start DESC;


-- ── 3. order_graphs_weekly_avg_by_year ───────────────────────────────────────────────
-- For each calendar year, the average weekly values across all weeks in that year.
-- Useful for year-over-year trending on a weekly basis.
CREATE VIEW public.order_graphs_weekly_avg_by_year AS
WITH weekly AS (
    SELECT
        EXTRACT(year FROM week_start)::integer AS year_start,
        revenue,
        cogs,
        gross_profit,
        cogs_pct,
        margin_pct,
        order_count,
        total_roasted_weight
    FROM public.order_graphs_week
    WHERE week_start <= CURRENT_DATE
)
SELECT
    year_start,
    ROUND(AVG(revenue),              2) AS avg_weekly_revenue,
    ROUND(AVG(cogs),                 2) AS avg_weekly_cogs,
    ROUND(AVG(gross_profit),         2) AS avg_weekly_gross_profit,
    ROUND(AVG(cogs_pct),             1) AS avg_cogs_pct,
    ROUND(AVG(margin_pct),           1) AS avg_margin_pct,
    ROUND(AVG(order_count),          1) AS avg_weekly_order_count,
    ROUND(AVG(total_roasted_weight)::numeric, 2) AS avg_weekly_roasted_weight,
    COUNT(*)                            AS weeks_in_year
FROM weekly
GROUP BY year_start
ORDER BY year_start DESC;
