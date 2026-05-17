-- Recreate order_graphs_year with actual yearly totals (not averages)

DROP VIEW IF EXISTS order_graphs_year CASCADE;

CREATE VIEW order_graphs_year AS
WITH yearly AS (
  SELECT
    facility_id,
    company_id,
    (EXTRACT(year FROM week_start))::integer AS year_start,
    round(sum(revenue), 2) AS total_revenue,
    round(sum(cogs), 2) AS total_cogs,
    round(sum(gross_profit), 2) AS total_gross_profit,
    round((sum(cogs) / NULLIF(sum(revenue), 0)) * 100, 1) AS cogs_pct,
    round((sum(gross_profit) / NULLIF(sum(revenue), 0)) * 100, 1) AS margin_pct,
    sum(order_count) AS total_orders,
    round(sum(total_roasted_weight), 2) AS total_roasted_weight
  FROM order_graphs_week
  WHERE week_start <= CURRENT_DATE
  GROUP BY facility_id, company_id, EXTRACT(year FROM week_start)
)
SELECT
  (facility_id || '_' || year_start) AS year_report_id,
  year_start, facility_id, company_id,
  total_revenue, total_cogs, total_gross_profit,
  cogs_pct, margin_pct,
  total_orders, total_roasted_weight,
  round(avg(total_revenue) OVER w3, 2) AS revenue_3yr_avg,
  round(avg(margin_pct) OVER w3, 1) AS margin_pct_3yr_avg
FROM yearly
WINDOW w3 AS (PARTITION BY facility_id ORDER BY year_start ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)
ORDER BY year_start DESC, facility_id;
