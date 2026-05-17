-- Audit table for manual subscription edits made from the dev portal.
--
-- Captures: which company was touched, what action (extend_trial,
-- force_plan_change, comp_paid_period, ...), a JSON delta of before/
-- after values, the reason string the dev typed in, and who did it.
--
-- Read-only from the app's perspective — only the dev portal writes.
-- The /dev/audit page will gain a tab for this once the unified-audit
-- pass lands.

BEGIN;

CREATE TABLE IF NOT EXISTS subscription_admin_log (
  log_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id    text NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
  action        text NOT NULL,
  delta         jsonb NOT NULL DEFAULT '{}'::jsonb,
  reason        text NOT NULL,
  performed_by  text NOT NULL,
  performed_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sub_admin_log_company ON subscription_admin_log(company_id, performed_at DESC);
CREATE INDEX IF NOT EXISTS idx_sub_admin_log_when    ON subscription_admin_log(performed_at DESC);

COMMENT ON TABLE subscription_admin_log IS
  'Audit trail of manual subscription mutations made by developers from /dev/companies/[companyId]. Append-only.';

COMMIT;
