-- Migration 00127: Consolidate volume report views
--
-- summarized_weight_weekly, summarized_weight_monthly, and summarized_weight_yearly
-- were duplicates of data already in the order_graphs_* family. Dropping all three
-- and keeping the order_graphs versions as the single source of truth for volume reports.
--
-- Also adds order_graphs_year (yearly TOTALS) which was missing — the order_graphs family
-- had weekly totals, weekly-avg-by-month, and weekly-avg-by-year but no yearly total view.
--
-- Volume report family after this migration:
--   order_graphs_week              → weekly totals
--   order_graphs_weekly_avg_by_month → average week per calendar month
--   order_graphs_weekly_avg_by_year  → average week per year
--   order_graphs_year              → yearly totals (NEW)

-- ── 1. Drop duplicates ───────────────────────────────────────────────────────────────
DROP VIEW IF EXISTS public.summarized_weight_monthly;
DROP VIEW IF EXISTS public.summarized_weight_yearly;
DROP VIEW IF EXISTS public.summarized_weight_weekly;

-- ── 2. Yearly totals view (missing from order_graphs family) ─────────────────────────
CREATE OR REPLACE VIEW public.order_graphs_year AS
SELECT
    EXTRACT(year FROM week_start)::integer       AS year_start,
    ROUND(SUM(revenue),                      2)  AS total_revenue,
    ROUND(SUM(cogs),                         2)  AS total_cogs,
    ROUND(SUM(gross_profit),                 2)  AS total_gross_profit,
    ROUND(SUM(cogs)         / NULLIF(SUM(revenue), 0) * 100, 1) AS cogs_pct,
    ROUND(SUM(gross_profit) / NULLIF(SUM(revenue), 0) * 100, 1) AS margin_pct,
    SUM(order_count)                             AS total_orders,
    ROUND(SUM(total_roasted_weight)::numeric, 2) AS total_roasted_weight,
    COUNT(*)                                     AS weeks_in_year
FROM public.order_graphs_week
WHERE week_start <= CURRENT_DATE
GROUP BY EXTRACT(year FROM week_start)
ORDER BY year_start DESC;
