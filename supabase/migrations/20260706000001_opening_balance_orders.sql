-- Invoice-of-record P3 (part 1): the opening-balance order write path.
-- At cutover, open A/R from QuickBooks is imported as LINE-LESS orders (one per
-- outstanding invoice) carrying the QB open balance directly in order_total and
-- the original QB Num in invoice_number. These are LIVE receivables
-- (is_legacy_import=false, invoice_state='open', posted=true) — NOT archived
-- history. This migration makes them safe to write:
--   1. update_order_metrics must NOT clobber their app-set order_total to 0.
--   2. they must NOT pollute customer cadence / last-order metrics.
-- Plan: memory/project_invoice_of_record.md (P3).

-- ── is_opening_balance flag ───────────────────────────────────────────────────
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS is_opening_balance boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN public.orders.is_opening_balance IS
  'True for line-less imported open-A/R stubs written at cutover. A live receivable (is_legacy_import=false) but NOT a real sale — carries an app-set order_total and is excluded from cadence/lifetime/revenue rollups.';

-- ── update_order_metrics: don''t rederive order_total for opening balances ─────
-- BLOCKER FIX: this BEFORE INSERT/UPDATE trigger normally sets
-- order_total := SUM(order_details.total_price). A line-less opening-balance
-- order has no details, so that would book every imported receivable at $0
-- (while a file-based reconcile still shows PASS). Guarded SURGICALLY on
-- is_opening_balance so NORMAL orders are completely unchanged (still 0 when
-- empty, resummed on every edit) — only opening balances keep their app-set total.
CREATE OR REPLACE FUNCTION public.update_order_metrics()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    prev_date DATE;
    v_cat TEXT;
    v_area TEXT;
    v_facility_id TEXT;
BEGIN
    -- 0. Identify Facility
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    -- 1. Grab from Customer record (Isolated by Facility)
    SELECT customer_category, sales_area
    INTO v_cat, v_area
    FROM customers
    WHERE customer_id = NEW.customer_id
      AND facility_id = v_facility_id;

    NEW.customer_category := v_cat;
    NEW.area := v_area;

    -- 2. Sum up totals from "Order Details" so the header stays in sync with the
    --    lines. SKIPPED for opening-balance stubs, which are line-less and carry
    --    the imported open balance in order_total already.
    IF NOT COALESCE(NEW.is_opening_balance, false) THEN
        SELECT
            COALESCE(SUM(total_price), 0),
            COALESCE(SUM(roasted_weight), 0)
        INTO NEW.order_total, NEW.total_weight
        FROM order_details
        WHERE order_id = NEW.order_id;
    END IF;

    -- 3. Find previous order date for interval calculation (Isolated by Facility)
    SELECT MAX(order_date) INTO prev_date
    FROM orders
    WHERE customer_id = NEW.customer_id
      AND order_date < NEW.order_date
      AND order_status != 'Canceled'
      AND facility_id = v_facility_id;

    -- 4. Calculate interval math
    IF prev_date IS NOT NULL THEN
        NEW.interval_days := (NEW.order_date - prev_date);
        NEW.interval_wks := GREATEST(1, ROUND(CAST((NEW.order_date - prev_date) AS numeric) / 7.0, 1));
    ELSE
        NEW.interval_days := 0;
        NEW.interval_wks := 0;
    END IF;

    RETURN NEW;
END;
$function$;

-- ── update_customer_metrics_on_order: exclude opening balances from cadence ────
-- HIGH FIX: opening-balance stubs (order_status='Delivered', OLD QB dates) would
-- otherwise pollute avg cadence + last_order_id/date via trigger_refresh_customer_stats,
-- corrupting the managed-account/reminder engine. Exact copy of the live function
-- with `AND COALESCE(is_opening_balance,false) = false` added to BOTH the cadence
-- window and the last-order lookup. Everything else unchanged (incl. RETURN NEW).
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

    SELECT ROUND(CAST(AVG(order_date - prev_date) / 7.0 AS numeric), 1)
    INTO v_avg_interval
    FROM (
        SELECT order_date, LAG(order_date) OVER (ORDER BY order_date) AS prev_date
        FROM orders
        WHERE customer_id = NEW.customer_id
          AND order_status != 'Canceled'
          AND order_date > (CURRENT_DATE - INTERVAL '180 days')
          AND facility_id = v_facility_id
          AND COALESCE(is_opening_balance, false) = false
    ) sub
    WHERE prev_date IS NOT NULL;

    v_avg_interval := COALESCE(v_avg_interval, 0);

    SELECT order_date, order_id
    INTO v_latest_order_date, v_latest_order_id
    FROM orders
    WHERE customer_id = NEW.customer_id
      AND order_status != 'Canceled'
      AND facility_id = v_facility_id
      AND COALESCE(is_opening_balance, false) = false
    ORDER BY order_date DESC
    LIMIT 1;

    UPDATE customers
    SET
        last_order_id = v_latest_order_id,
        last_order_date = v_latest_order_date,
        days_since_last_order = (CURRENT_DATE - v_latest_order_date),
        weeks_since_last_order = CEIL((CURRENT_DATE - v_latest_order_date) / 7.0),
        avg_interval_wks = v_avg_interval,
        effective_interval_wks = COALESCE(
            acct_management_interval_wks,
            CASE WHEN v_avg_interval > 0 THEN GREATEST(1, v_avg_interval) ELSE NULL END
        )
    WHERE customer_id = NEW.customer_id
      AND facility_id = v_facility_id;

    RETURN NEW;
END;
$function$;

-- ── Integrity CHECKs (NOT VALID — all 14,269 live rows have invoice_state NULL) ─
-- An 'open' invoice is a live STRATA receivable, never archived legacy history.
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_open_not_legacy_chk;
ALTER TABLE public.orders ADD CONSTRAINT orders_open_not_legacy_chk
  CHECK (NOT (invoice_state = 'open' AND COALESCE(is_legacy_import, false) = true)) NOT VALID;

-- An 'open' invoice must always carry a total (guards the clobber-to-$0 regression).
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_open_has_total_chk;
ALTER TABLE public.orders ADD CONSTRAINT orders_open_has_total_chk
  CHECK (invoice_state <> 'open' OR order_total IS NOT NULL) NOT VALID;

NOTIFY pgrst, 'reload schema';
