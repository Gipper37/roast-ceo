-- Monthly "avg weekly lbs ordered" counted the CURRENT, unfinished week as a
-- complete week of zero.
--
-- order_graphs_weekly_avg_by_month already excludes future weeks
-- (WHERE week_start <= CURRENT_DATE), but the week we are standing in passes that
-- test: on 2026-07-28 the week beginning 07-25 is three days old and mostly unlived.
-- It landed in the average as a full week worth 0, so MCR's July read
--     (2512 + 796 + 0 + 0) / 4 = 827
-- when the completed weeks average 1,103. The newest point on the chart — the one
-- an operator looks at first — is understated every single week, worst on a Monday
-- and recovering by Sunday, which reads as "the business is falling off a cliff".
--
-- 🔴 NOT fixed by moving the WHERE clause. total_revenue, total_cogs,
-- total_gross_profit and total_orders in this same view are SUMS over those weeks.
-- Excluding the in-progress week from the WHERE would erase THIS WEEK'S SALES from
-- the current month's revenue — trading a cosmetic understatement for a financial
-- one. Only the average is wrong, so only the average is filtered.
--
-- Note this does NOT explain the rest of MCR's July drop: their QuickBooks export
-- ends 2026-07-14 and no orders have been entered in STRATA since, so most of that
-- cliff is real and must stay visible.

begin;

create or replace view public.order_graphs_weekly_avg_by_month as
 WITH monthly AS (
         SELECT order_graphs_week.facility_id,
            order_graphs_week.company_id,
            date_trunc('month'::text, order_graphs_week.week_start::timestamp with time zone)::date AS month_start,
            -- SUMS: every week up to today, including the in-progress one. Money
            -- taken this week belongs in this month's revenue.
            round(sum(order_graphs_week.revenue), 2) AS total_revenue,
            round(sum(order_graphs_week.cogs), 2) AS total_cogs,
            round(sum(order_graphs_week.gross_profit), 2) AS total_gross_profit,
            round(sum(order_graphs_week.cogs) / NULLIF(sum(order_graphs_week.revenue), 0::numeric) * 100::numeric, 1) AS cogs_pct,
            round(sum(order_graphs_week.gross_profit) / NULLIF(sum(order_graphs_week.revenue), 0::numeric) * 100::numeric, 1) AS margin_pct,
            sum(order_graphs_week.order_count) AS total_orders,
            -- AVERAGE: completed weeks only. A week is complete once seven days have
            -- elapsed from its start; until then it is a partial observation and
            -- averaging it in dilutes the result by however much of it is unlived.
            round(avg(order_graphs_week.total_roasted_weight)
                  FILTER (WHERE order_graphs_week.week_start + 7 <= CURRENT_DATE), 2) AS avg_weekly_roasted_weight,
            -- Kept consistent with the average above: it reports how many weeks the
            -- average is over, so counting a week the average excluded would make it
            -- a different number than it claims to be.
            count(*) FILTER (WHERE order_graphs_week.week_start + 7 <= CURRENT_DATE) AS weeks_in_month
           FROM order_graphs_week
          WHERE order_graphs_week.week_start <= CURRENT_DATE
          GROUP BY order_graphs_week.facility_id, order_graphs_week.company_id, (date_trunc('month'::text, order_graphs_week.week_start::timestamp with time zone))
        )
 SELECT (facility_id || '_'::text) || month_start AS month_report_id,
    month_start,
    facility_id,
    company_id,
    total_revenue,
    total_cogs,
    total_gross_profit,
    cogs_pct,
    margin_pct,
    total_orders,
    avg_weekly_roasted_weight,
    weeks_in_month,
    round(avg(total_revenue) OVER w12, 2) AS revenue_12mo_avg,
    round(avg(total_cogs) OVER w12, 2) AS cogs_12mo_avg,
    round(avg(total_gross_profit) OVER w12, 2) AS gross_profit_12mo_avg,
    round(avg(cogs_pct) OVER w12, 1) AS cogs_pct_12mo_avg,
    round(avg(margin_pct) OVER w12, 1) AS margin_pct_12mo_avg,
    round(avg(avg_weekly_roasted_weight) OVER w12, 2) AS roasted_weight_12mo_avg
   FROM monthly
  WINDOW w12 AS (PARTITION BY facility_id ORDER BY month_start ROWS BETWEEN 11 PRECEDING AND CURRENT ROW)
  ORDER BY month_start DESC, facility_id;

comment on view public.order_graphs_weekly_avg_by_month is
  'Monthly order rollup. SUMS include the in-progress week (this week''s money is this month''s money); the weekly AVERAGE excludes it, because a partial week is not a week.';

commit;

notify pgrst, 'reload schema';
