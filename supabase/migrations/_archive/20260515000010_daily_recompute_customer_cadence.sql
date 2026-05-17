-- Daily cron: recompute avg_interval_wks + effective_interval_wks
-- for every active customer.
--
-- Why: the existing update_customer_metrics_on_order trigger only
-- fires on order INSERT/UPDATE. Dormant customers never get their
-- avg refreshed — the value persists from whenever they last
-- ordered, even as the 180-day rolling window slides past those
-- orders. Result: a customer who hasn't ordered in 25 weeks still
-- shows "4.5wk avg" because that was their pattern back when they
-- did order.
--
-- This adds a single function that recomputes EVERY customer's
-- cadence using the current 180-day window, and a pg_cron job that
-- runs it once per day at 3am UTC.

CREATE OR REPLACE FUNCTION public.recompute_all_customer_cadence()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  WITH avg_calc AS (
    SELECT
      o.customer_id,
      o.facility_id,
      ROUND(CAST(AVG(o.order_date - o.prev_date) / 7.0 AS numeric), 1) AS avg_int
    FROM (
      SELECT
        order_date,
        customer_id,
        facility_id,
        LAG(order_date) OVER (PARTITION BY customer_id, facility_id ORDER BY order_date) AS prev_date
      FROM public.orders
      WHERE order_status != 'Canceled'
        AND order_date > (CURRENT_DATE - INTERVAL '180 days')
    ) o
    WHERE o.prev_date IS NOT NULL
    GROUP BY o.customer_id, o.facility_id
  )
  UPDATE public.customers c
  SET
    avg_interval_wks = COALESCE(a.avg_int, 0),
    -- Same logic as the per-order trigger: NULL effective when avg
    -- is 0 (no computable cadence). Manual override still wins.
    effective_interval_wks = COALESCE(
      c.acct_management_interval_wks,
      CASE WHEN COALESCE(a.avg_int, 0) > 0 THEN GREATEST(1, a.avg_int) ELSE NULL END
    )
  FROM avg_calc a
  WHERE c.customer_id = a.customer_id
    AND c.facility_id = a.facility_id
    AND c.is_active = true;

  -- Customers with NO non-cancelled orders in the last 180 days
  -- need their avg reset to 0 too — the JOIN above only hits rows
  -- WITH orders. Handle the rest with a sweep.
  UPDATE public.customers c
  SET
    avg_interval_wks = 0,
    effective_interval_wks = c.acct_management_interval_wks  -- NULL when no override
  WHERE c.is_active = true
    AND (c.avg_interval_wks IS NULL OR c.avg_interval_wks > 0)
    AND NOT EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.customer_id = c.customer_id
        AND o.facility_id = c.facility_id
        AND o.order_status != 'Canceled'
        AND o.order_date > (CURRENT_DATE - INTERVAL '180 days')
    );
END;
$$;

-- Schedule: 03:00 UTC daily. pg_cron is already enabled per
-- nudge_all_inventory(). Picked 3am UTC because order activity is
-- effectively zero across all timezones we serve at that hour.
SELECT cron.schedule(
  'recompute_customer_cadence_daily',
  '0 3 * * *',
  $$SELECT public.recompute_all_customer_cadence();$$
);

-- Run once now to fix the existing stale values (Wailuku Inn et al).
SELECT public.recompute_all_customer_cadence();
