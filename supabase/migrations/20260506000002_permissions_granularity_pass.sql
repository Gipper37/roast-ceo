-- ============================================================================
-- Permission catalog granularity pass — fills gaps surfaced by the
-- privilege-boundary audit done after Phase A landed.
--
-- Three real gaps the initial seed missed:
--
--   1. order.pack — `orders/[id]/page.tsx` line 205 defines PACK_ROLES
--      that explicitly INCLUDES 'staff' (warehouse-floor capability).
--      Different from order.edit which excludes staff. We had order.edit
--      but no order.pack, so staff wouldn't be able to mark items as
--      packed once we flip those callsites to permission-driven checks.
--
--   2. invoice.process — `api/invoice/process/route.ts` line 86 gates
--      AI-driven invoice extraction with MANAGER_ROLES. Was implicit;
--      no permission key existed. Manager+ only.
--
--   3. roast.manage_roasters — `roast/page.tsx` line 254 has a DUAL
--      gate: manager+ role AND Pro+ plan. This is the first compound
--      gate we've explicitly surfaced. Marked is_plan_gated=true and
--      role-granted to manager/facility_admin/company_admin; plan-
--      granted to pro/enterprise/enterprise_plus.
--
-- Considered but DEFERRED (keeping the audit trail):
--
--   • shop.configure was flagged for potential split into
--     oauth_connect / product_sync / pricing_publish. Today MANAGER_ROLES
--     uniformly gates all of them — granular split is premature
--     optimization until the dev portal needs to grant them differently.
--     Re-evaluate once the portal is in roasters' hands.
--
--   • sales.tasks / sales.notes were called out as unreferenced. Kept —
--     they're placeholders for the sales-tools surface that's planned
--     but not yet built. Removing them would just have to re-add later.
--
--   • ActivityPay webhook was flagged for not enforcing payments.refund
--     on void events. Webhooks are server-to-server (signed by AP, not
--     user-initiated), so permissions don't apply. The user-initiated
--     refund flow doesn't exist yet; payments.refund is ready when it
--     does.
--
--   • Demo-mode silent-denial inconsistency — different axis (state
--     gate, not permission). Fix in a separate cleanup pass.
-- ============================================================================

BEGIN;

-- ── 1. New permissions ─────────────────────────────────────────────────────

INSERT INTO permissions (permission_id, category, label, description, sort_order, is_plan_gated) VALUES
  ('order.pack', 'Orders',
   'Pack orders',
   'Mark order line items as packed during fulfillment. Distinct from edit — warehouse staff can pack without being able to change order details.',
   25, false),

  ('invoice.process', 'Inventory',
   'Process supplier invoices (AI extraction)',
   'Use the AI invoice parser to extract line items from a supplier PDF/image. Manager-level capability.',
   55, false),

  ('roast.manage_roasters', 'Roasting',
   'Manage roaster crew + scheduling',
   'Add, edit, or schedule operators for roast slots. Compound gate: requires both manager-level role AND Pro-tier subscription.',
   70, true)
ON CONFLICT (permission_id) DO UPDATE SET
  category = EXCLUDED.category,
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  sort_order = EXCLUDED.sort_order,
  is_plan_gated = EXCLUDED.is_plan_gated,
  updated_at = now();

-- ── 2. Role grants for new permissions ─────────────────────────────────────

-- order.pack — every operational role (matches PACK_ROLES which
-- includes staff). Excludes sales_person which is customer-facing.
INSERT INTO role_permissions (role_id, permission_id, granted)
SELECT role_id, 'order.pack', true
FROM (VALUES ('staff'), ('roastmaster'), ('assistant_roaster'),
             ('manager'), ('facility_admin'), ('company_admin')) AS r(role_id)
ON CONFLICT (role_id, permission_id) DO UPDATE SET granted = true, updated_at = now();

-- invoice.process — manager+
INSERT INTO role_permissions (role_id, permission_id, granted)
SELECT role_id, 'invoice.process', true
FROM (VALUES ('manager'), ('facility_admin'), ('company_admin')) AS r(role_id)
ON CONFLICT (role_id, permission_id) DO UPDATE SET granted = true, updated_at = now();

-- roast.manage_roasters — manager+
INSERT INTO role_permissions (role_id, permission_id, granted)
SELECT role_id, 'roast.manage_roasters', true
FROM (VALUES ('manager'), ('facility_admin'), ('company_admin')) AS r(role_id)
ON CONFLICT (role_id, permission_id) DO UPDATE SET granted = true, updated_at = now();

-- ── 3. Plan grants for new permissions ─────────────────────────────────────

-- order.pack + invoice.process: NOT plan-gated → granted to all plans
INSERT INTO plan_permissions (plan_id, permission_id, granted)
SELECT sp.plan_id, perm, true
FROM subscription_plans sp
CROSS JOIN (VALUES ('order.pack'), ('invoice.process')) AS p(perm)
ON CONFLICT (plan_id, permission_id) DO UPDATE SET granted = true, updated_at = now();

-- roast.manage_roasters: plan-gated. Pro+ only — Starter is solo / 2-team
-- by design; multi-roaster scheduling doesn't apply.
INSERT INTO plan_permissions (plan_id, permission_id, granted)
SELECT 'starter', 'roast.manage_roasters', false
ON CONFLICT (plan_id, permission_id) DO UPDATE SET granted = false, updated_at = now();

INSERT INTO plan_permissions (plan_id, permission_id, granted)
SELECT plan_id, 'roast.manage_roasters', true
FROM (VALUES ('pro'), ('enterprise'), ('enterprise_plus')) AS p(plan_id)
ON CONFLICT (plan_id, permission_id) DO UPDATE SET granted = true, updated_at = now();

COMMIT;
