-- Auto-flag bouncing customer emails
--
-- The Resend webhook (added in 20260515000004) now writes
-- status='bounced' or 'complained' to email_log rows. Without this
-- migration that info is buried in the log — the operator never sees
-- "this customer's email is dead" until a reminder keeps failing.
--
-- Adds two columns to customers + a trigger that fires when an
-- email_log row's status flips to bounced/complained. The customer
-- row gets stamped so the UI (customer detail, AM tab) can show a
-- "bad email" warning + skip them on the next reminder run.
--
-- Resubscribing / clearing: operator clears the flag by updating
-- the email column on the customer (which the existing customer edit
-- flow can do). No automatic clearing — once it bounced, it stays
-- flagged until the operator acknowledges.

-- 1) Columns
ALTER TABLE public.customers
  ADD COLUMN IF NOT EXISTS email_bounced_at timestamptz,
  ADD COLUMN IF NOT EXISTS email_bounce_reason text;

-- 2) Auto-clear when the email is changed — operator edits the email,
-- we assume they've fixed the issue.
CREATE OR REPLACE FUNCTION public.clear_email_bounce_on_email_change()
RETURNS trigger AS $$
BEGIN
  IF NEW.email IS DISTINCT FROM OLD.email THEN
    NEW.email_bounced_at := NULL;
    NEW.email_bounce_reason := NULL;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_clear_email_bounce_on_email_change ON public.customers;
CREATE TRIGGER trg_clear_email_bounce_on_email_change
  BEFORE UPDATE OF email ON public.customers
  FOR EACH ROW
  EXECUTE FUNCTION public.clear_email_bounce_on_email_change();

-- 3) Flag the customer when a bounce/complaint event lands in email_log.
-- Fires AFTER UPDATE — the Resend webhook UPDATEs an existing
-- email_log row (initially inserted with status='sent') so we listen
-- to status transitions, not inserts.
CREATE OR REPLACE FUNCTION public.flag_customer_on_email_bounce()
RETURNS trigger AS $$
BEGIN
  IF NEW.status IN ('bounced', 'complained')
     AND OLD.status IS DISTINCT FROM NEW.status
     AND NEW.customer_id IS NOT NULL
  THEN
    UPDATE public.customers
       SET email_bounced_at = COALESCE(email_bounced_at, NOW()),
           email_bounce_reason = COALESCE(
             NEW.metadata->>'bounce_reason',
             NEW.status
           )
     WHERE customer_id = NEW.customer_id
       AND email_bounced_at IS NULL;  -- don't overwrite an existing flag
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_flag_customer_on_email_bounce ON public.email_log;
CREATE TRIGGER trg_flag_customer_on_email_bounce
  AFTER UPDATE OF status ON public.email_log
  FOR EACH ROW
  EXECUTE FUNCTION public.flag_customer_on_email_bounce();

-- 4) Update reminder_candidates to skip customers with bounced
-- emails. No point re-mailing a known-dead address every hour.
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
    AND c.email_bounced_at IS NULL  -- NEW: skip bouncing addresses
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
$$;

-- Verification:
--   \d customers  → should show email_bounced_at + email_bounce_reason
--   SELECT proname FROM pg_proc WHERE proname IN ('flag_customer_on_email_bounce','clear_email_bounce_on_email_change');
