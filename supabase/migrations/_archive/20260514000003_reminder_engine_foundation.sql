-- =============================================================================
-- Reminder engine foundation (Phase 2 / Chunk 1)
-- =============================================================================
-- Schema for the "Customer-Initiated with Reminders" management-type feature.
--
-- WHAT THIS DOES:
--   1. Creates `email_log` — append-only record of every outbound email
--      STRATA sends (reminders FIRST, but the table is generic so order
--      confirmations, status updates, invites can write here later too).
--   2. Adds reminder-state columns to `customers`:
--        last_reminder_sent_at      — when the engine last emailed them
--        reminder_snoozed_until     — operator-set "stop pestering them
--                                     until this date"
--      `order_reminders_unsubscribed` (text) already exists; the
--      engine reads it as "non-null = opted out, value is the
--      timestamp they unsubscribed".
--   3. Indexes the cron query path so the hourly "find due
--      customers" scan stays fast as customer count grows.
--
-- WHAT IT DOES NOT DO:
--   - No cron schedule yet (handled in Chunk 3 via Vercel Cron hitting
--     an API endpoint, not pg_cron — keeps the send logic in TypeScript
--     where Resend + token signing live).
--   - No template, no send pipeline, no UI. Those are Chunks 2/4/5.
-- =============================================================================

-- 1) email_log — append-only outbound mail record.
CREATE TABLE IF NOT EXISTS public.email_log (
  email_log_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Tenant scoping — every email belongs to a company. NULL allowed
  -- for system-level mail (forgot-password etc.) but should be set
  -- for everything that originates from a tenant action.
  company_id          text REFERENCES public.companies(company_id) ON DELETE SET NULL,
  -- Customer-targeted mail links here so the customer detail page can
  -- render its own per-customer history without re-querying. Also
  -- lets us cleanly cascade-delete when a customer is permanently
  -- removed (rare; usually just is_active=false).
  customer_id         text REFERENCES public.customers(customer_id) ON DELETE CASCADE,
  -- Generic event tag so other features can write to this table:
  --   'reminder'       — Customer-Initiated with Reminders fire
  --   'order_confirm'  — order confirmation
  --   'order_status'   — pack/ship status updates
  --   'shop_invite'    — wholesale shop invitation
  --   'team_invite'    — team-member invite
  --   'auth.*'         — supabase auth flows (if we ever capture them)
  event_type          text NOT NULL,
  -- Display-recipient address (denormalized — customer.email may
  -- change after the send but the log should preserve what we
  -- actually mailed).
  to_email            text NOT NULL,
  subject             text,
  -- Resend's message id from their POST response. Lets us reconcile
  -- with their dashboard / Resend webhooks if we wire them later.
  resend_message_id   text,
  -- Lifecycle state. Starts at 'sent' on a successful POST; future
  -- Resend webhook handler can update to 'delivered'/'bounced'/
  -- 'opened'/'complained'.
  status              text NOT NULL DEFAULT 'sent'
                      CHECK (status IN ('sent','delivered','bounced','opened','complained','failed')),
  -- If the POST itself failed (network error, missing API key, 4xx
  -- from Resend) record the message here so the operator can debug.
  error_message       text,
  sent_at             timestamptz NOT NULL DEFAULT now(),
  -- Free-form payload so individual event_types can stash extra
  -- context (template variables, deep-link tokens, etc.) without
  -- new columns per feature.
  metadata            jsonb
);

CREATE INDEX IF NOT EXISTS email_log_customer_idx
  ON public.email_log (customer_id, sent_at DESC)
  WHERE customer_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS email_log_company_event_idx
  ON public.email_log (company_id, event_type, sent_at DESC);

-- 2) Customer-side reminder state.
ALTER TABLE public.customers
  ADD COLUMN IF NOT EXISTS last_reminder_sent_at  timestamptz,
  ADD COLUMN IF NOT EXISTS reminder_snoozed_until date;

-- 3) Cron-query index. The hourly job's WHERE clause is going to
-- look something like:
--   WHERE management_type = 'Customer-Initiated with Reminders'
--     AND order_reminders_unsubscribed IS NULL
--     AND (reminder_snoozed_until IS NULL OR reminder_snoozed_until < CURRENT_DATE)
--     AND last_order_date + effective_interval days <= CURRENT_DATE
-- Partial index on the management-type predicate keeps the index tiny
-- (only customers who ACTUALLY want reminders).
CREATE INDEX IF NOT EXISTS customers_reminder_eligible_idx
  ON public.customers (company_id, last_order_date, last_reminder_sent_at)
  WHERE management_type = 'Customer-Initiated with Reminders'
    AND order_reminders_unsubscribed IS NULL;

-- 4) RLS — match the customers table's existing posture (Phase 2 RLS
-- migration enabled tenant scoping there). email_log starts with RLS
-- on but no policies, meaning service_role-only access. Frontend
-- reads will go through server actions that already use service_role.
-- A later policy can grant authenticated viewers read on their own
-- company's rows once the app moves to the authenticated client.
ALTER TABLE public.email_log ENABLE ROW LEVEL SECURITY;

-- The reminder_candidates RPC that the cron calls is defined in
-- migration 20260514000007 — it depends on the renamed column
-- effective_interval_wks (the rename happens in 000004), so it
-- has to run after both this foundation migration and the rename.

-- =============================================================================
-- Verification (run manually post-push):
--   SELECT column_name FROM information_schema.columns
--   WHERE table_name='customers'
--     AND column_name IN ('last_reminder_sent_at','reminder_snoozed_until');
--   -- Expected: 2 rows.
--
--   \d email_log
--   -- Expected: PK on email_log_id, FKs on company_id + customer_id,
--   -- 2 indexes (customer + company/event).
-- =============================================================================
