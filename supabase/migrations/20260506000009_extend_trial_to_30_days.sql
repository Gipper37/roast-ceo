-- Extend the standard trial from 14 days to 30 days.
--
-- Backend signup logic + every customer-visible mention of "14-day"
-- already updated in the same change set; this migration brings any
-- still-trialing tenants forward to the new duration. Only rows where
-- trial_end - created_at = 14 days qualify — tenants already on
-- non-default trial windows (extended for support, comp'd, etc.) are
-- preserved as-is.

BEGIN;

UPDATE subscriptions
SET trial_end = created_at + interval '30 days'
WHERE status = 'trialing'
  AND trial_end IS NOT NULL
  AND created_at IS NOT NULL
  AND (trial_end::date - created_at::date) = 14;

COMMIT;
