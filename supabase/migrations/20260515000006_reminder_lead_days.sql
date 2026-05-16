-- reminder_candidates: fire reminders N days BEFORE strict due date
--
-- User feedback: today the cron sends reminders on the day a customer
-- becomes "overdue" (last_order_date + effective_interval_wks <=
-- CURRENT_DATE). With Saturday orders cutoffs, a Friday-overdue
-- customer's email lands AFTER the cutoff for that week's run —
-- they have to wait until next week before it actually helps.
--
-- Fix: lead the reminder by N days so the customer has time to act
-- before the next orders cutoff. Default 3 days — short enough to
-- still feel relevant, long enough to span a typical 1-2 day reset
-- buffer + a customer needing a day to actually place the order.
--
-- Parameter source (priority order):
--   1. company_parameters.value_number where parameter_id =
--      'reminder_lead_days' for the customer's facility — per-facility override
--   2. standard_parameters.amount for that parameter — system default
--   3. Hardcode 3 days — last resort if the parameter row is missing

-- 1) Standard parameter row so every company gets the default.
INSERT INTO public.standard_parameters (parameters_id, parameter, amount, data_type)
VALUES (
  'reminder_lead_days',
  'Reminder Lead Days',
  3,
  'number'
)
ON CONFLICT (parameters_id) DO NOTHING;

-- 2) Updated RPC. Takes lead-days into account in the due predicate.
--    Same shape (returns customer_id + company_id) so the cron route
--    doesn't need a code change to start using it.
CREATE OR REPLACE FUNCTION public.reminder_candidates()
RETURNS TABLE(customer_id text, company_id text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT c.customer_id, c.company_id
  FROM public.customers c
  WHERE c.management_type = 'Customer-Initiated with Reminders'
    AND c.order_reminders_unsubscribed IS NULL
    AND (c.reminder_snoozed_until IS NULL OR c.reminder_snoozed_until < CURRENT_DATE)
    AND (c.last_reminder_sent_at IS NULL OR c.last_reminder_sent_at < now() - interval '24 hours')
    AND c.last_order_date IS NOT NULL
    AND c.effective_interval_wks IS NOT NULL
    AND c.is_active = true
    AND c.email IS NOT NULL
    AND c.company_id IS NOT NULL
    -- Lead-days predicate: fire when (due_date - lead_days) <= today.
    -- Per-facility override → standard default → hardcode 3.
    AND c.last_order_date
        + (c.effective_interval_wks || ' weeks')::interval
        - (
            COALESCE(
              (
                SELECT cp.value_number::integer
                FROM public.company_parameters cp
                WHERE cp.parameter_id = 'reminder_lead_days'
                  AND cp.facility_id = c.facility_id
                  AND cp.value_number IS NOT NULL
                LIMIT 1
              ),
              (
                SELECT sp.amount::integer
                FROM public.standard_parameters sp
                WHERE sp.parameters_id = 'reminder_lead_days'
                LIMIT 1
              ),
              3
            ) || ' days'
        )::interval
        <= CURRENT_DATE;
$$;

-- Verification (run manually post-push):
--   SELECT * FROM reminder_candidates();
--   -- Expected: now includes customers who are 0-3 days FROM being due.
--
--   SELECT parameters_id, amount FROM standard_parameters WHERE parameters_id='reminder_lead_days';
--   -- Expected: one row, amount = 3.
