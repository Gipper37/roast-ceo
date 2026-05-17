-- =============================================================================
-- reminder_candidates RPC — eligibility query for the hourly cron
-- =============================================================================
-- Encapsulates the cadence math the JS Supabase client can't compose
-- inline (`last_order_date + (effective_interval_wks || ' weeks')::interval`).
-- Called by /api/cron/reminders to find customers due for a nudge.
--
-- Eligibility (each AND condition):
--   - On the reminder management type
--   - Has not opted out (order_reminders_unsubscribed IS NULL)
--   - Not currently snoozed (snooze date in the past or null)
--   - Not reminded in the last 24 h — per-customer floor on top of
--     the cadence override; prevents the same customer being
--     re-mailed on every cron tick once they cross the due line
--   - Has a last_order_date AND has reached/exceeded the cadence
--     window (last_order_date + effective_interval_wks weeks <= today)
--   - Active customer with a real email + company
--
-- Returns customer_id + company_id pairs; the cron does the per-
-- company plan check + per-customer send.
--
-- Pairs with the partial index in migration 20260514000003 to keep
-- the scan O(reminder-eligible-customers), not O(all-customers).
--
-- SECURITY DEFINER so the route's service_role client can call it
-- without needing direct table grants beyond the RPC. Read-only.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.reminder_candidates()
RETURNS TABLE(customer_id text, company_id text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT c.customer_id, c.company_id
  FROM public.customers c
  WHERE c.management_type = 'Customer-Initiated with Reminders'
    AND c.order_reminders_unsubscribed IS NULL
    AND (c.reminder_snoozed_until IS NULL OR c.reminder_snoozed_until < CURRENT_DATE)
    AND (c.last_reminder_sent_at IS NULL OR c.last_reminder_sent_at < now() - interval '24 hours')
    AND c.last_order_date IS NOT NULL
    AND c.effective_interval_wks IS NOT NULL
    AND c.last_order_date + (c.effective_interval_wks || ' weeks')::interval <= CURRENT_DATE
    AND c.is_active = true
    AND c.email IS NOT NULL
    AND c.company_id IS NOT NULL
$$;

REVOKE ALL ON FUNCTION public.reminder_candidates() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reminder_candidates() TO service_role;
