-- email_log — index resend_message_id for the Resend webhook lookup.
--
-- The /api/webhooks/resend route fires per Resend lifecycle event
-- (delivered/opened/clicked/bounced/complained) and looks up the
-- existing log row by resend_message_id. Without an index this is
-- a full scan on a table that grows unbounded.
--
-- Partial index — most rows have a resend_message_id, but system
-- mail (or sends that failed before Resend returned an id) leave
-- it null. Excluding nulls keeps the index small and fast.

CREATE INDEX IF NOT EXISTS email_log_resend_message_id_idx
  ON public.email_log (resend_message_id)
  WHERE resend_message_id IS NOT NULL;
