-- Fix: effective_interval_wks shouldn't floor to 1 when there's no
-- computable cadence (avg_interval_wks = 0).
--
-- Bug: GREATEST(1, 0) = 1 turned "we have no real average yet"
-- (customer has 0–1 orders in the last 180d) into "1-week cadence".
-- That made customers appear with bogus cadence + appear in the
-- "overdue" set against a fake 1-week interval. Examples from live
-- data: Red Fish, Happy Fish, Foodland Kapolei — all show
-- avg_interval_wks=0 (no orders in 180d) but effective=1.
--
-- Fix: NULL effective when avg is 0. Operator override (acct_management_
-- interval_wks) still wins. Cadence-aware UI/RPC paths must
-- already cope with NULL effective (cron's reminder_candidates
-- already filters `effective_interval_wks IS NOT NULL`).
--
-- Backfill applies the corrected value to every existing row so
-- the UI stops showing fake "1wk" cadences immediately.

CREATE OR REPLACE FUNCTION update_customer_metrics_on_order() RETURNS trigger AS $$
DECLARE
    v_avg_interval NUMERIC;
    v_latest_order_date DATE;
    v_latest_order_id TEXT;
    v_facility_id TEXT;
BEGIN
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

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
        -- v_avg_interval = 0 means "no computable cadence" (0 or 1
        -- orders in 180d). Don't fake a 1-week floor — leave NULL
        -- so cadence-aware paths skip the customer.
        effective_interval_wks = COALESCE(
            acct_management_interval_wks,
            CASE WHEN v_avg_interval > 0 THEN GREATEST(1, v_avg_interval) ELSE NULL END
        )
    WHERE customer_id = NEW.customer_id
      AND facility_id = v_facility_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Backfill: clear effective for rows where the floor was faking a
-- cadence. Don't touch rows with a manual override.
UPDATE customers
SET effective_interval_wks = NULL
WHERE acct_management_interval_wks IS NULL
  AND (avg_interval_wks IS NULL OR avg_interval_wks = 0)
  AND effective_interval_wks IS NOT NULL;
