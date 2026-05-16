-- Materialize order_graphs_week for performance
-- The dynamic view with per-facility orders_reset_day is slow (4+ seconds)
-- Materialized version refreshes hourly via pg_cron

-- First drop the dependent views (they reference order_graphs_week)
DROP VIEW IF EXISTS order_graphs_weekly_avg_by_year CASCADE;
DROP VIEW IF EXISTS order_graphs_weekly_avg_by_month CASCADE;
DROP VIEW IF EXISTS order_graphs_year CASCADE;

-- Drop the regular view
DROP VIEW IF EXISTS order_graphs_week;

-- Recreate as materialized view
CREATE MATERIALIZED VIEW order_graphs_week AS
WITH facility_params AS (
    SELECT f.facility_id,
           f.company_id,
           COALESCE(
             (SELECT cp.value_number::integer FROM company_parameters cp
              WHERE cp.parameter_id = 'orders_reset_day' AND cp.facility_id = f.facility_id LIMIT 1),
             (SELECT sp.amount::integer FROM standard_parameters sp
              WHERE sp.parameters_id = 'orders_reset_day' LIMIT 1),
             6
           ) AS orders_reset_day,
           (SELECT min(o.order_date) FROM orders o
            WHERE o.facility_id = f.facility_id AND o.order_status <> 'Canceled') AS first_order_date
    FROM facilities f
),
spine AS (
    SELECT fp.facility_id,
           fp.company_id,
           fp.orders_reset_day,
           gs::date AS week_start
    FROM facility_params fp,
    LATERAL generate_series(
        fp.first_order_date::date
            - ((EXTRACT(dow FROM fp.first_order_date)::integer - fp.orders_reset_day + 7) % 7),
        CURRENT_DATE + interval '364 days',
        interval '7 days'
    ) AS gs
    WHERE fp.first_order_date IS NOT NULL
),
agg AS (
    SELECT s.facility_id,
           s.company_id,
           s.week_start,
           COALESCE(sum(od.total_price), 0) AS revenue,
           COALESCE(sum(od.unit_cost_at_sale), 0) AS cogs,
           COALESCE(sum(od.total_price) - sum(od.unit_cost_at_sale), 0) AS gross_profit,
           round((COALESCE(sum(od.unit_cost_at_sale), 0) / NULLIF(sum(od.total_price), 0)) * 100, 1) AS cogs_pct,
           round(((COALESCE(sum(od.total_price), 0) - COALESCE(sum(od.unit_cost_at_sale), 0)) / NULLIF(sum(od.total_price), 0)) * 100, 1) AS margin_pct,
           count(DISTINCT o.order_id) AS order_count,
           round(COALESCE(sum(od.roasted_weight), 0)::numeric, 2) AS total_roasted_weight
    FROM spine s
    LEFT JOIN orders o ON o.facility_id = s.facility_id
        AND (o.order_date::date - ((EXTRACT(dow FROM o.order_date)::integer - s.orders_reset_day + 7) % 7)) = s.week_start
        AND o.order_status <> 'Canceled'
    LEFT JOIN order_details od ON od.order_id = o.order_id
    GROUP BY s.facility_id, s.company_id, s.week_start
)
SELECT (facility_id || '_' || week_start) AS week_report_id,
       week_start, facility_id, company_id,
       revenue, cogs, gross_profit, cogs_pct, margin_pct,
       order_count, total_roasted_weight,
       round(avg(revenue)                OVER w26, 2) AS revenue_6mo_avg,
       round(avg(cogs)                   OVER w26, 2) AS cogs_6mo_avg,
       round(avg(gross_profit)           OVER w26, 2) AS gross_profit_6mo_avg,
       round(avg(cogs_pct)               OVER w26, 1) AS cogs_pct_6mo_avg,
       round(avg(margin_pct)             OVER w26, 1) AS margin_pct_6mo_avg,
       round(avg(total_roasted_weight)   OVER w26, 2) AS roasted_weight_6mo_avg
FROM agg
WINDOW w26 AS (PARTITION BY facility_id ORDER BY week_start ROWS BETWEEN 25 PRECEDING AND CURRENT ROW)
ORDER BY week_start DESC, facility_id;

-- Add index for fast lookups
CREATE UNIQUE INDEX idx_ogw_pk ON order_graphs_week(week_report_id);
CREATE INDEX idx_ogw_facility ON order_graphs_week(facility_id);

-- Recreate the dependent views (they were regular views reading from order_graphs_week)
CREATE VIEW order_graphs_weekly_avg_by_month AS
 WITH monthly AS (
         SELECT order_graphs_week.facility_id,
            order_graphs_week.company_id,
            (date_trunc('month', order_graphs_week.week_start::timestamp with time zone))::date AS month_start,
            round(sum(order_graphs_week.revenue), 2) AS total_revenue,
            round(sum(order_graphs_week.cogs), 2) AS total_cogs,
            round(sum(order_graphs_week.gross_profit), 2) AS total_gross_profit,
            round((sum(order_graphs_week.cogs) / NULLIF(sum(order_graphs_week.revenue), 0)) * 100, 1) AS cogs_pct,
            round((sum(order_graphs_week.gross_profit) / NULLIF(sum(order_graphs_week.revenue), 0)) * 100, 1) AS margin_pct,
            sum(order_graphs_week.order_count) AS total_orders,
            round(avg(order_graphs_week.total_roasted_weight), 2) AS avg_weekly_roasted_weight,
            count(*) AS weeks_in_month
           FROM order_graphs_week
          WHERE order_graphs_week.week_start <= CURRENT_DATE
          GROUP BY order_graphs_week.facility_id, order_graphs_week.company_id, (date_trunc('month', order_graphs_week.week_start::timestamp with time zone))
        )
 SELECT (facility_id || '_' || month_start) AS month_report_id,
    month_start, facility_id, company_id,
    total_revenue, total_cogs, total_gross_profit, cogs_pct, margin_pct,
    total_orders, avg_weekly_roasted_weight, weeks_in_month,
    round(avg(total_revenue) OVER w12, 2) AS revenue_12mo_avg,
    round(avg(total_cogs) OVER w12, 2) AS cogs_12mo_avg,
    round(avg(total_gross_profit) OVER w12, 2) AS gross_profit_12mo_avg,
    round(avg(cogs_pct) OVER w12, 1) AS cogs_pct_12mo_avg,
    round(avg(margin_pct) OVER w12, 1) AS margin_pct_12mo_avg,
    round(avg(avg_weekly_roasted_weight) OVER w12, 2) AS roasted_weight_12mo_avg
   FROM monthly
  WINDOW w12 AS (PARTITION BY facility_id ORDER BY month_start ROWS BETWEEN 11 PRECEDING AND CURRENT ROW)
  ORDER BY month_start DESC, facility_id;

CREATE VIEW order_graphs_weekly_avg_by_year AS
 WITH monthly AS (
         SELECT order_graphs_week.facility_id,
            order_graphs_week.company_id,
            (EXTRACT(year FROM order_graphs_week.week_start))::integer AS year_start,
            date_trunc('month', order_graphs_week.week_start::timestamp with time zone) AS month_start,
            sum(order_graphs_week.revenue) AS monthly_revenue,
            sum(order_graphs_week.gross_profit) AS monthly_gross_profit
           FROM order_graphs_week
          WHERE order_graphs_week.week_start <= CURRENT_DATE
          GROUP BY order_graphs_week.facility_id, order_graphs_week.company_id, (EXTRACT(year FROM order_graphs_week.week_start)), (date_trunc('month', order_graphs_week.week_start::timestamp with time zone))
        ), weekly AS (
         SELECT order_graphs_week.facility_id,
            order_graphs_week.company_id,
            (EXTRACT(year FROM order_graphs_week.week_start))::integer AS year_start,
            round(avg(order_graphs_week.total_roasted_weight), 2) AS avg_weekly_roasted_weight
           FROM order_graphs_week
          WHERE order_graphs_week.week_start <= CURRENT_DATE
          GROUP BY order_graphs_week.facility_id, order_graphs_week.company_id, (EXTRACT(year FROM order_graphs_week.week_start))
        ), yearly AS (
         SELECT m.facility_id, m.company_id, m.year_start,
            round(avg(m.monthly_revenue), 2) AS avg_monthly_revenue,
            round(avg(m.monthly_gross_profit), 2) AS avg_monthly_gross_profit
           FROM monthly m
          GROUP BY m.facility_id, m.company_id, m.year_start
        )
 SELECT (y.facility_id || '_' || y.year_start) AS year_report_id,
    y.year_start, y.facility_id, y.company_id,
    y.avg_monthly_revenue, y.avg_monthly_gross_profit,
    w.avg_weekly_roasted_weight
   FROM yearly y
     JOIN weekly w ON w.facility_id = y.facility_id AND w.year_start = y.year_start
  ORDER BY y.year_start DESC, y.facility_id;

-- Also recreate order_graphs_year if it existed
CREATE OR REPLACE VIEW order_graphs_year AS
SELECT * FROM order_graphs_weekly_avg_by_year;

-- Refresh the materialized view now
REFRESH MATERIALIZED VIEW order_graphs_week;

-- Add to hourly cron refresh (the nudge_all_inventory job can refresh this too)
-- Or create a separate scheduled function
CREATE OR REPLACE FUNCTION refresh_order_graphs() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY order_graphs_week;
END;
$$;

-- Schedule hourly refresh via pg_cron
SELECT cron.schedule('refresh-order-graphs', '5 * * * *', 'SELECT refresh_order_graphs()');
