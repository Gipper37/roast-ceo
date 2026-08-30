-- Reminders nag weekly, not daily.
--
-- The 24-hour gate in reminder_candidates was written as an anti-double-send
-- guard but became the CADENCE: an overdue customer was emailed every day
-- until they ordered or opted out. One Social Hour customer received seven
-- consecutive daily reminders (Aug 23-29) and two of the twelve enrolled
-- customers unsubscribed. Owner's call (2026-08-30): weekly while overdue —
-- first reminder when due, then at most every 7 days.
--
-- One interval changes; every other predicate stands exactly as it was.

begin;

CREATE OR REPLACE FUNCTION public.reminder_candidates()
 RETURNS TABLE(customer_id text, company_id text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT c.customer_id, c.company_id
  FROM public.customers c
  WHERE c.management_type = 'Customer-Initiated with Reminders'
    AND c.order_reminders_unsubscribed IS NULL
    AND (c.reminder_snoozed_until IS NULL OR c.reminder_snoozed_until < CURRENT_DATE)
    -- Weekly while overdue. The old 24-hour version made this a daily nag,
    -- which reads as spam and converts enrollees into unsubscribes.
    AND (c.last_reminder_sent_at IS NULL OR c.last_reminder_sent_at < now() - interval '7 days')
    AND c.last_order_date IS NOT NULL
    AND c.effective_interval_wks IS NOT NULL
    AND c.is_active = true
    AND c.email IS NOT NULL
    AND c.email_bounced_at IS NULL  -- skip bouncing addresses
    AND c.company_id IS NOT NULL
    AND c.last_order_date
        + (c.effective_interval_wks || ' weeks')::interval
        - (
            COALESCE(
              (SELECT cp.value_number::integer FROM public.company_parameters cp
                 WHERE cp.parameter_id = 'reminder_lead_days'
                   AND cp.facility_id = c.facility_id
                   AND cp.value_number IS NOT NULL LIMIT 1),
              (SELECT sp.amount::integer FROM public.standard_parameters sp
                 WHERE sp.parameters_id = 'reminder_lead_days' LIMIT 1),
              3
            ) || ' days'
        )::interval
        <= CURRENT_DATE;
$function$;

commit;
