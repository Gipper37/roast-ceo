-- Fix: recompute_all_customer_cadence skipped customers with
-- exactly ONE non-canceled order in the 180d window. The LAG-based
-- CTE only emitted rows for orders with a prev_date; the sweep
-- only handled customers with ZERO orders. Customers with one
-- order fell into neither bucket and kept their stale avg.
--
-- Rewrite to a single UPDATE driven by a per-customer subquery so
-- every active customer gets touched once. Still fast — bounded by
-- customer count, not order count, and runs once per day.

CREATE OR REPLACE FUNCTION public.recompute_all_customer_cadence()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  WITH per_customer AS (
    SELECT
      c.customer_id,
      c.facility_id,
      -- Returns the avg gap in WEEKS over the 180d window when ≥2
      -- orders exist; null otherwise. Wrapped in COALESCE → 0.
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
      ) AS avg_int
    FROM public.customers c
    WHERE c.is_active = true
  )
  UPDATE public.customers c
  SET
    avg_interval_wks = pc.avg_int,
    effective_interval_wks = COALESCE(
      c.acct_management_interval_wks,
      CASE WHEN pc.avg_int > 0 THEN GREATEST(1, pc.avg_int) ELSE NULL END
    )
  FROM per_customer pc
  WHERE c.customer_id = pc.customer_id
    AND c.facility_id = pc.facility_id;
END;
$$;

-- Run once now to clean up the still-stale rows from the broken
-- previous version.
SELECT public.recompute_all_customer_cadence();
