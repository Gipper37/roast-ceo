-- Migration 00129: Drop monthly_financials view
--
-- Redundant: order_graphs_weekly_avg_by_month covers the same grain (monthly)
-- with the same columns (revenue, cogs, gross_profit, cogs_pct, margin_pct)
-- plus a 12-month rolling average (vs. the old 6-month) and a full date spine
-- that shows empty months. Nothing else depends on this view.

DROP VIEW IF EXISTS public.monthly_financials;
