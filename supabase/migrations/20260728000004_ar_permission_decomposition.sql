-- A/R permissions: unlock the Accounting portal, and decompose by VERB RISK CLASS.
--
-- 🔴 THE BUG THIS FIXES FIRST: the Accounting portal is a locked empty room.
-- `accounting_view` and `accounting_admin` hold `accounting.view` (which gates the
-- /app/accounting page) but NOT `ar.view` (which gates every A/R query behind it).
-- So the roles built for outsourced bookkeepers can reach the page and see nothing.
--
-- The rest decomposes the coarse keys by what a verb can COST, not by which object it
-- touches. Per-object keys (statement.view, aging.view, creditmemo.view…) are all
-- reads of the same A/R dataset and belong under `ar.view` — that way lies a 40-key
-- matrix nobody can reason about.
--
-- NOT DONE HERE, deliberately: the plan-tier move (READ+OPERATE from Enterprise+ down
-- to Pro). That is a pricing/packaging decision for the owner, not a technical one, so
-- every new key below matches the existing Enterprise+ gating and can be re-tiered in
-- one statement later.

begin;

-- ── 1. New keys ────────────────────────────────────────────────────────────
-- Each is a distinct risk class, not a finer slice of an existing one:
--   ar.export         — data leaves the building (a viewer reading a page and a
--                       viewer walking out with the customer list are different acts)
--   invoice.write_off — a P&L event. NOT payment.record: recording a payment says
--                       money arrived; a write-off says it never will.
--   ar.late_fee_apply — assess or WAIVE a fee on one invoice (operators)
--   ar.dunning_manage — configure the ladder + fee policy for everyone (admins)
--   ar.close_period   — lock a reported month. Highest-blast-radius A/R act.
--   billing.configure — change invoice numbering / terms / billing settings.
--                       ar.view is currently doing this job, which is a READ key
--                       gating WRITES.
insert into public.permissions
  (permission_id, category, label, description, default_deny_message, is_plan_gated, sort_order)
values
  ('ar.export', 'Payments', 'Export A/R data',
   'Download A/R reports (aging, invoice register, payments register) as files.',
   'You do not have permission to export A/R data.', true, 81),
  ('invoice.write_off', 'Payments', 'Write off invoices',
   'Write an uncollectable invoice off to bad debt. A P&L event, not a payment.',
   'You do not have permission to write off invoices.', true, 62),
  ('ar.late_fee_apply', 'Payments', 'Apply or waive late fees',
   'Assess or waive a late fee on a specific invoice.',
   'You do not have permission to apply or waive late fees.', true, 82),
  ('ar.dunning_manage', 'Payments', 'Manage reminders & late-fee policy',
   'Configure the payment-reminder ladder and the late-fee policy for the company.',
   'You do not have permission to manage reminders or late-fee policy.', true, 83),
  ('ar.close_period', 'Payments', 'Close accounting periods',
   'Lock a period so nothing can post into an already-reported month.',
   'You do not have permission to close accounting periods.', true, 84),
  ('billing.configure', 'Payments', 'Configure billing settings',
   'Change invoice numbering, payment terms defaults, and billing configuration.',
   'You do not have permission to change billing settings.', true, 85)
on conflict (permission_id) do nothing;

-- Plan gate: match the rest of invoice-of-record (Enterprise / Enterprise+).
insert into public.plan_permissions (plan_id, permission_id, granted)
select pl.plan_id, k.permission_id, pl.plan_id in ('enterprise', 'enterprise_plus')
from   (values ('starter'), ('pro'), ('enterprise'), ('enterprise_plus')) as pl(plan_id)
cross join (values
  ('ar.export'), ('invoice.write_off'), ('ar.late_fee_apply'),
  ('ar.dunning_manage'), ('ar.close_period'), ('billing.configure')
) as k(permission_id)
on conflict (plan_id, permission_id) do nothing;

-- ── 2. Role grants ─────────────────────────────────────────────────────────
-- Three bundles, so the matrix stays readable:
--   READ    = ar.view, ar.export
--   OPERATE = READ + invoice.send, payment.record, ar.late_fee_apply
--   CONTROL = OPERATE + invoice.void, invoice.write_off, payment.refund,
--             ar.close_period, ar.dunning_manage, billing.configure
insert into public.role_permissions (role_id, permission_id, granted)
values
  -- accounting_view — READ. The fix for the locked empty room.
  ('accounting_view',  'ar.view',            true),
  ('accounting_view',  'ar.export',          true),

  -- accounting_admin — CONTROL. This is the outsourced-bookkeeper role; if it cannot
  -- close a period or write off bad debt it cannot do the job it exists for.
  ('accounting_admin', 'ar.view',            true),
  ('accounting_admin', 'ar.export',          true),
  ('accounting_admin', 'ar.late_fee_apply',  true),
  ('accounting_admin', 'invoice.write_off',  true),
  ('accounting_admin', 'ar.close_period',    true),
  ('accounting_admin', 'ar.dunning_manage',  true),

  -- Company/facility admins — everything, including the config keys.
  ('company_admin',    'ar.export',          true),
  ('company_admin',    'invoice.write_off',  true),
  ('company_admin',    'ar.late_fee_apply',  true),
  ('company_admin',    'ar.dunning_manage',  true),
  ('company_admin',    'ar.close_period',    true),
  ('company_admin',    'billing.configure',  true),
  ('facility_admin',   'ar.export',          true),
  ('facility_admin',   'invoice.write_off',  true),
  ('facility_admin',   'ar.late_fee_apply',  true),
  ('facility_admin',   'ar.dunning_manage',  true),
  ('facility_admin',   'ar.close_period',    true),
  ('facility_admin',   'billing.configure',  true),

  -- Manager — OPERATE only. A manager reconciles the books; writing off bad debt,
  -- refunding, and closing a period are owner-level acts.
  ('manager',          'ar.export',          true),
  ('manager',          'ar.late_fee_apply',  true)
on conflict (role_id, permission_id) do update set granted = excluded.granted;

-- ── 3. Retire the dead keys ────────────────────────────────────────────────
-- Zero callsites across app/, lib/ and components/ (verified before writing this).
-- payments.refund is a straight duplicate of payment.refund, which IS wired (3
-- callsites) — two keys for one act is how a permission matrix rots. Left in place
-- but marked, rather than deleted, so an existing grant can't error mid-request.
update public.permissions
set    label       = label || ' (deprecated)',
       description = 'DEPRECATED — no callsites. payments.refund is superseded by payment.refund; payments.charge and payments.onboard were never wired. Do not grant.'
where  permission_id in ('payments.charge', 'payments.onboard', 'payments.refund');

commit;

notify pgrst, 'reload schema';
