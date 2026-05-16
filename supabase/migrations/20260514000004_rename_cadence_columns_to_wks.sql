-- =============================================================================
-- Rename cadence columns so the unit is in the name
-- =============================================================================
-- Audit during the reminder-engine planning surfaced that:
--
--   `avg_interval_last_180_days` — value is in WEEKS, not days. The
--      column name is misleading: a customer ordering weekly stores
--      ~1.0 in this column (one WEEK per order, computed at line
--      `AVG(order_date - prev_date) / 7.0` in the
--      update_customer_metrics_on_order trigger).
--
--   `effective_interval` — also in WEEKS. The COALESCE source columns
--      (`acct_management_interval_wks` and `avg_interval_last_180_days`)
--      are both weeks, the frontend renders it as `${value} wks`,
--      and the operator-input field is named `_wks`. Only this
--      output column lacks the unit in the name.
--
-- This migration renames both to make the unit explicit. No data
-- conversion needed — values are already in the correct unit.
--
-- Trigger functions (`update_customer_metrics_on_order` +
-- `update_effective_interval_on_manual_change`) are rewritten in
-- place to reference the new column names. Same logic, same output;
-- only the column references change.
-- =============================================================================

-- 1) Rename the columns.
ALTER TABLE public.customers
  RENAME COLUMN avg_interval_last_180_days TO avg_interval_wks;

ALTER TABLE public.customers
  RENAME COLUMN effective_interval TO effective_interval_wks;

-- 2) Add column comments documenting the unit in the schema itself.
COMMENT ON COLUMN public.customers.avg_interval_wks IS
  'Observed average order cadence in WEEKS, computed from the last 180 days of non-cancelled orders. Auto-updated by trigger update_customer_metrics_on_order on every order insert/update.';
COMMENT ON COLUMN public.customers.effective_interval_wks IS
  'Resolved cadence the app uses (weeks). Operator override (acct_management_interval_wks) wins; falls back to GREATEST(1, FLOOR(avg_interval_wks)) when no override.';
COMMENT ON COLUMN public.customers.acct_management_interval_wks IS
  'Operator override for cadence (weeks). When set, takes precedence over the observed avg_interval_wks. Surface in the UI alongside the observed value so operators can see when an override has drifted from reality.';

-- 3) Rebuild the two trigger functions to reference the new names.
CREATE OR REPLACE FUNCTION public.update_effective_interval_on_manual_change()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    -- Recompute when EITHER the operator override or the observed
    -- average changes. Output unit is weeks (both inputs are weeks).
    IF (OLD.acct_management_interval_wks IS DISTINCT FROM NEW.acct_management_interval_wks)
       OR (OLD.avg_interval_wks IS DISTINCT FROM NEW.avg_interval_wks) THEN

        NEW.effective_interval_wks := COALESCE(
            NEW.acct_management_interval_wks,
            GREATEST(1, FLOOR(COALESCE(NEW.avg_interval_wks, 0)))
        );

    END IF;

    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_customer_metrics_on_order()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
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
        -- Manual override -> else floor of observed avg, min 1.
        effective_interval_wks = COALESCE(
            acct_management_interval_wks,
            GREATEST(1, FLOOR(v_avg_interval))
        )
    WHERE customer_id = NEW.customer_id
      AND facility_id = v_facility_id;

    RETURN NEW;
END;
$function$;

-- =============================================================================
-- Verification (run manually post-push):
--   \d customers   -- should show avg_interval_wks + effective_interval_wks
--   SELECT name_company, acct_management_interval_wks,
--          avg_interval_wks, effective_interval_wks
--   FROM customers WHERE acct_management_interval_wks IS NOT NULL LIMIT 5;
--   -- All non-null values should match what they were before the rename.
-- =============================================================================
