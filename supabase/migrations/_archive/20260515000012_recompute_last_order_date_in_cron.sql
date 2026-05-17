-- Bug: customers.last_order_date can go stale.
--
-- The update_customer_metrics_on_order trigger only fires on
-- orders INSERT/UPDATE. If an order is DELETED (or its earlier
-- INSERT predates the trigger), customers.last_order_date keeps
-- the old value forever. Symptom: Ryan Hagler shows last_order_date
-- = 2026-04-23 but the actual latest non-Canceled order is
-- 2025-12-11.
--
-- Fix: extend the daily recompute job to refresh last_order_date,
-- last_order_id, days_since_last_order, and weeks_since_last_order
-- alongside the cadence values. Adds one pass over orders per
-- customer per day — still bounded + idempotent.

CREATE OR REPLACE FUNCTION public.recompute_all_customer_cadence()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  WITH per_customer AS (
    SELECT
      c.customer_id,
      c.facility_id,
      -- avg gap in weeks across 180d window, NULL when <2 orders.
      COALESCE(
        (
          SELECT ROUND(CAST(AVG(order_date - prev_date) / 7.0 AS numeric), 1)
          FROM (
            SELECT order_date,
                   LAG(order_date) OVER (ORDER BY order_date) AS prev_date
            FROM public.orders
            WHERE orders.customer_id = c.customer_id
              AND orders.facility_id = c.facility_id
              AND orders.order_status != 'Canceled'
              AND orders.order_date > (CURRENT_DATE - INTERVAL '180 days')
          ) sub
          WHERE prev_date IS NOT NULL
        ),
        0
      ) AS avg_int,
      -- latest non-Canceled order at this facility, all-time
      (
        SELECT order_date
        FROM public.orders
        WHERE orders.customer_id = c.customer_id
          AND orders.facility_id = c.facility_id
          AND orders.order_status != 'Canceled'
        ORDER BY order_date DESC
        LIMIT 1
      ) AS latest_order_date,
      (
        SELECT order_id
        FROM public.orders
        WHERE orders.customer_id = c.customer_id
          AND orders.facility_id = c.facility_id
          AND orders.order_status != 'Canceled'
        ORDER BY order_date DESC
        LIMIT 1
      ) AS latest_order_id
    FROM public.customers c
    WHERE c.is_active = true
  )
  UPDATE public.customers c
  SET
    avg_interval_wks = pc.avg_int,
    effective_interval_wks = COALESCE(
      c.acct_management_interval_wks,
      CASE WHEN pc.avg_int > 0 THEN GREATEST(1, pc.avg_int) ELSE NULL END
    ),
    last_order_date = pc.latest_order_date,
    last_order_id = pc.latest_order_id,
    days_since_last_order = CASE WHEN pc.latest_order_date IS NULL THEN NULL
                                 ELSE (CURRENT_DATE - pc.latest_order_date)::numeric END,
    weeks_since_last_order = CASE WHEN pc.latest_order_date IS NULL THEN NULL
                                  ELSE CEIL((CURRENT_DATE - pc.latest_order_date) / 7.0) END
  FROM per_customer pc
  WHERE c.customer_id = pc.customer_id
    AND c.facility_id = pc.facility_id;
END;
$$;

-- Run once to fix the existing stale rows (Ryan Hagler et al).
SELECT public.recompute_all_customer_cadence();
