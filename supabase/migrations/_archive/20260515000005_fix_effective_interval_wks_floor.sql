-- Fix update_customer_metrics_on_order — stop FLOORing avg_interval_wks
--
-- Bug: every customer with a non-integer observed cadence (e.g. 2.7
-- weeks) had their `effective_interval_wks` rounded DOWN, making
-- them appear overdue 2-7 days earlier than they should. Examples
-- from live data:
--   Jacqueline Carey   avg 23.6wk  effective 23wk  (4 days early)
--   Crugen Farm        avg 21.7wk  effective 21wk  (4 days early)
--   Allen Thomashefsky avg 17.6wk  effective 17wk  (4 days early)
--
-- The column is `numeric` — no reason to coerce to integer weeks.
-- Drop FLOOR(); keep the GREATEST(1, ...) floor at one week so a
-- customer with an unusually fast cadence doesn't get flagged
-- overdue daily.
--
-- Also: backfill every existing customer with the corrected value
-- since the trigger only fires on subsequent order INSERT/UPDATEs
-- and we want the fix to take effect immediately for all queues.

CREATE OR REPLACE FUNCTION update_customer_metrics_on_order() RETURNS trigger AS $$
DECLARE
    v_avg_interval NUMERIC;
    v_latest_order_date DATE;
    v_latest_order_id TEXT;
    v_facility_id TEXT;
BEGIN
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    -- Average WEEKS between consecutive non-cancelled orders, last 180 days.
    SELECT ROUND(CAST(AVG(order_date - prev_date) / 7.0 AS numeric), 1)
    INTO v_avg_interval
    FROM (
        SELECT order_date, LAG(order_date) OVER (ORDER BY order_date) AS prev_date
        FROM orders
        WHERE customer_id = NEW.customer_id
          AND order_status != 'Canceled'
          AND order_date > (CURRENT_DATE - INTERVAL '180 days')
          AND facility_id = v_facility_id
    ) sub
    WHERE prev_date IS NOT NULL;

    v_avg_interval := COALESCE(v_avg_interval, 0);

    SELECT order_date, order_id
    INTO v_latest_order_date, v_latest_order_id
    FROM orders
    WHERE customer_id = NEW.customer_id
      AND order_status != 'Canceled'
      AND facility_id = v_facility_id
    ORDER BY order_date DESC
    LIMIT 1;

    UPDATE customers
    SET
        last_order_id = v_latest_order_id,
        last_order_date = v_latest_order_date,
        days_since_last_order = (CURRENT_DATE - v_latest_order_date),
        weeks_since_last_order = CEIL((CURRENT_DATE - v_latest_order_date) / 7.0),
        avg_interval_wks = v_avg_interval,
        -- Was: GREATEST(1, FLOOR(v_avg_interval)) — knocked 2-7 days off
        -- every non-integer cadence. Keep the numeric precision.
        effective_interval_wks = COALESCE(
            acct_management_interval_wks,
            GREATEST(1, v_avg_interval)
        )
    WHERE customer_id = NEW.customer_id
      AND facility_id = v_facility_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Backfill: apply the fix to every existing customer immediately so
-- the suggestion lists + Account Management queues reflect the
-- corrected cadence without waiting for the next order trigger.
UPDATE customers
SET effective_interval_wks = COALESCE(
    acct_management_interval_wks,
    GREATEST(1, avg_interval_wks)
)
WHERE avg_interval_wks IS NOT NULL
  AND (
    -- Only touch rows that would actually change — keeps audit log noise down.
    effective_interval_wks IS DISTINCT FROM COALESCE(
      acct_management_interval_wks,
      GREATEST(1, avg_interval_wks)
    )
  );

-- Verification (run manually post-push):
--   SELECT name_company, avg_interval_wks, effective_interval_wks
--   FROM customers
--   WHERE avg_interval_wks IS NOT NULL
--     AND avg_interval_wks - FLOOR(avg_interval_wks) > 0
--     AND acct_management_interval_wks IS NULL
--   LIMIT 5;
--   -- Expected: avg and effective should now match (instead of effective
--   -- being floored).
