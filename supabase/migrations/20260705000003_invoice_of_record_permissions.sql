-- Invoice-of-record (Mode A) permissions: invoice.send, invoice.void,
-- payment.record, ar.view. All Enterprise + Enterprise+ plan-gated (mirrors the
-- config.import_data / sales.tasks gate). Role grants mirror the money-touching
-- payments.charge/refund family (admin/facility_admin/manager tier).
--
-- FK-safe CROSS JOIN + ON CONFLICT idiom (per 20260517000006_equipment_permissions):
-- staging (no seed plans/roles) no-ops cleanly; prod (all plans + roles present)
-- gets the grants. category + label + default_deny_message + is_plan_gated +
-- sort_order are all NOT NULL on prod — every catalog INSERT supplies them.
--
-- NOTE: these perms are the SECOND gate. The primary Mode-A/B switch is
-- billing_settings.invoice_of_record='strata', re-asserted server-side at every
-- callsite; since all live companies are Enterprise the plan-gate is inert as
-- live protection, so the mode assertion + DB guard-trigger RAISEs are the real
-- Mode-B-leak defense.

-- ── 1. Permission catalog (category='Payments' keeps them beside payments.*) ──
INSERT INTO public.permissions
  (permission_id, category, label, description, default_deny_message, is_plan_gated, sort_order)
VALUES
  ('invoice.send','Payments','Send invoices',
    'Finalize an order into a STRATA invoice (allocate number, lock, mark open) and email the PDF. Enterprise plans, invoice-of-record mode only.',
    'You do not have permission to send invoices.', true, 50),
  ('invoice.void','Payments','Void invoices',
    'Void a posted STRATA invoice. Enterprise plans, invoice-of-record mode only.',
    'You do not have permission to void invoices.', true, 60),
  ('payment.record','Payments','Record payments',
    'Record a manual payment (check, ACH, cash, wire, card, adjustment) or credit memo against a customer invoice. Enterprise plans, invoice-of-record mode only.',
    'You do not have permission to record payments.', true, 70),
  ('ar.view','Payments','View accounts receivable',
    'View A/R aging, customer balances, statements, and manage invoice-of-record billing settings. Enterprise plans only.',
    'Accounts receivable is available on Enterprise plans.', true, 80)
ON CONFLICT (permission_id) DO NOTHING;

-- ── 2. Plan grants — Enterprise + Enterprise+ only; explicit pro/starter=false ─
--     (mirrors config.import_data so the gate is visible in the dev portal).
INSERT INTO public.plan_permissions (plan_id, permission_id, granted, updated_reason)
SELECT p.plan_id, perm.permission_id,
       (p.plan_id IN ('enterprise','enterprise_plus')) AS granted,
       'Invoice-of-record billing — Enterprise and above'
FROM public.subscription_plans p
CROSS JOIN (VALUES ('invoice.send'),('invoice.void'),('payment.record'),('ar.view')) perm(permission_id)
WHERE p.plan_id IN ('starter','pro','enterprise','enterprise_plus')
ON CONFLICT (plan_id, permission_id)
DO UPDATE SET granted = EXCLUDED.granted, updated_reason = EXCLUDED.updated_reason;

-- ── 3. Role grants — admin/facility_admin/manager for all 4 (mirrors ──────────
--     payments.charge/refund; intentionally EXCLUDES roastmaster/staff — A/R is
--     admin/manager, not roast-scoped). sales_person ar.view is intentionally
--     HELD (company-wide balance visibility has no per-account scoping) — add
--     later if desired.
INSERT INTO public.role_permissions (role_id, permission_id, granted)
SELECT r.role_id, perm.permission_id, true
FROM public.user_roles r
CROSS JOIN (VALUES ('invoice.send'),('invoice.void'),('payment.record'),('ar.view')) perm(permission_id)
WHERE r.role_id IN ('company_admin','facility_admin','manager')
ON CONFLICT (role_id, permission_id) DO UPDATE SET granted = true;

NOTIFY pgrst, 'reload schema';
