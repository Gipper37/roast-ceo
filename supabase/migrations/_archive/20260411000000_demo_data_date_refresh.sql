-- ============================================================================
-- DEMO DATA DATE REFRESH
-- ============================================================================
-- Keeps demo company date-related records fresh relative to CURRENT_DATE.
-- The function finds the most recent order_date in demo orders, computes the
-- gap to CURRENT_DATE, and shifts ALL date columns forward by that gap.
-- This is idempotent: running it multiple times always produces the same
-- result because the offset is recomputed from the actual max date each time.
-- ============================================================================

-- ── 1. Create the refresh function ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.refresh_demo_dates()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_max_order_date   date;
  v_days             integer;    -- offset in whole days
  v_offset           interval;   -- same offset as interval (for timestamp columns)
BEGIN
  -- Skip triggers and audit for bulk date updates
  SET LOCAL session_replication_role = 'replica';
  SET LOCAL app.skip_audit = 'true';

  -- Find the most recent order_date in demo orders
  SELECT MAX(order_date) INTO v_max_order_date
  FROM public.orders
  WHERE company_id = 'demo-aloha-coffee-roasters';

  -- If no demo orders exist, nothing to do
  IF v_max_order_date IS NULL THEN
    RETURN;
  END IF;

  -- Compute offset: how many days to shift forward so the newest order is today
  v_days   := CURRENT_DATE - v_max_order_date;  -- integer subtraction on date columns
  v_offset := v_days * INTERVAL '1 day';

  -- If offset is zero (already fresh), skip everything
  IF v_days = 0 THEN
    RETURN;
  END IF;

  -- ── orders ────────────────────────────────────────────────────────────────
  -- order_date is date; created_at and status_changed_at are timestamptz
  UPDATE public.orders
  SET order_date        = order_date + v_days,
      created_at        = created_at + v_offset,
      status_changed_at = status_changed_at + v_offset
  WHERE company_id = 'demo-aloha-coffee-roasters';

  -- ── order_details ─────────────────────────────────────────────────────────
  -- order_date is date; created_at is timestamptz
  UPDATE public.order_details
  SET order_date  = order_date + v_days,
      created_at  = created_at + v_offset
  WHERE company_id = 'demo-aloha-coffee-roasters';

  -- ── roast_log ─────────────────────────────────────────────────────────────
  -- roast_date is timestamp without time zone (local facility time)
  -- roast_date_utc is timestamptz; created_at is timestamptz
  UPDATE public.roast_log
  SET roast_date     = roast_date + v_offset,
      roast_date_utc = roast_date_utc + v_offset,
      created_at     = created_at + v_offset
  WHERE company_id = 'demo-aloha-coffee-roasters';

  -- ── shipment_received ─────────────────────────────────────────────────────
  -- order_date is date; date_received is date
  UPDATE public.shipment_received
  SET order_date    = order_date + v_days,
      date_received = date_received + v_days
  WHERE company_id = 'demo-aloha-coffee-roasters';

  -- ── coffee_inventory_purchased ────────────────────────────────────────────
  -- created_at is timestamptz
  UPDATE public.coffee_inventory_purchased
  SET created_at = created_at + v_offset
  WHERE company_id = 'demo-aloha-coffee-roasters';

  -- ── coffee_inventory (last_inventory is date, set via history trigger) ────
  UPDATE public.coffee_inventory
  SET last_inventory = last_inventory + v_days
  WHERE facility_id = 'demo-kailua-roastery'
    AND last_inventory IS NOT NULL;

  -- ── consumable_inventory ──────────────────────────────────────────────────
  -- last_inventory_date is date
  UPDATE public.consumable_inventory
  SET last_inventory_date = last_inventory_date + v_days
  WHERE facility_id = 'demo-kailua-roastery'
    AND last_inventory_date IS NOT NULL;

  -- ── coffee_inventory_history ──────────────────────────────────────────────
  -- inventory_date is date
  UPDATE public.coffee_inventory_history
  SET inventory_date = inventory_date + v_days
  WHERE facility_id = 'demo-kailua-roastery';

  -- ── consumable_inventory_history ──────────────────────────────────────────
  -- inventory_date is date
  UPDATE public.consumable_inventory_history
  SET inventory_date = inventory_date + v_days
  WHERE facility_id = 'demo-kailua-roastery';

  -- ── products_price_log ────────────────────────────────────────────────────
  -- date_updated is date; created_at is timestamp without time zone
  UPDATE public.products_price_log
  SET date_updated = date_updated + v_days,
      created_at   = created_at + v_offset
  WHERE company_id = 'demo-aloha-coffee-roasters';

END;
$$;

-- ── 2. Schedule daily refresh at midnight UTC ──────────────────────────────
SELECT cron.schedule(
  'refresh-demo-dates',
  '0 0 * * *',
  $$SELECT public.refresh_demo_dates()$$
);

-- ── 3. Run immediately so data is fresh now ────────────────────────────────
SELECT public.refresh_demo_dates();
