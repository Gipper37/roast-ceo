-- ============================================================
-- Equipment Phase 8.7: equipment_tech role + cost-gating perms
-- ============================================================
-- Two changes:
--
-- A) New role `equipment_tech` — for staff whose job is the equipment
--    side (service techs, maintenance assistants). Hands-on access:
--    view, create, edit, log_maintenance. NOT cost — that's manager+.
--
-- B) Two new permissions for cost gating:
--      equipment.view_cost  — see labor rates, part costs, totals,
--                             markup, visit invoices. Manager+ only.
--      equipment.edit_cost  — set labor rates, part costs, markup,
--                             visit fees/tax/discount. Manager+ only.
--    Non-cost users can still log maintenance (description, hours,
--    parts list) — they just don't enter or see prices.
--
-- Also tightens existing role grants for the equipment surface:
--   - assistant_roaster: was view-only → now also log_maintenance + edit
--   - sales_person: stays view-only (account-management visibility)
--   - staff: stays view-only
-- ============================================================


-- ────────────────────────────────────────────────────────────────
-- A) New role
-- ────────────────────────────────────────────────────────────────
INSERT INTO public.user_roles (role_id) VALUES ('equipment_tech')
ON CONFLICT (role_id) DO NOTHING;


-- ────────────────────────────────────────────────────────────────
-- B) Cost-gating permissions
-- ────────────────────────────────────────────────────────────────
INSERT INTO public.permissions
  (permission_id, category, label, description, default_deny_message, is_plan_gated, sort_order)
VALUES
  ('equipment.view_cost', 'equipment', 'View equipment cost data',
    'See labor rates, part costs, markup, maintenance totals, and visit invoice amounts.',
    'You do not have permission to view equipment cost data.', true, 160),
  ('equipment.edit_cost', 'equipment', 'Edit equipment cost data',
    'Set labor rates, part costs, markup percentages, visit trip fees, tax, and discounts when logging maintenance or service visits.',
    'You do not have permission to enter equipment cost data.', true, 170)
ON CONFLICT (permission_id) DO NOTHING;


-- ────────────────────────────────────────────────────────────────
-- Plan grants for the two cost perms — Pro+ tier (same as base)
-- ────────────────────────────────────────────────────────────────
INSERT INTO public.plan_permissions (plan_id, permission_id, granted)
SELECT p.plan_id, perm.permission_id, true
FROM public.subscription_plans p
CROSS JOIN (VALUES ('equipment.view_cost'), ('equipment.edit_cost')) perm(permission_id)
WHERE p.plan_id IN ('pro','enterprise','enterprise_plus')
ON CONFLICT (plan_id, permission_id) DO UPDATE SET granted = true;


-- ────────────────────────────────────────────────────────────────
-- Role grants — comprehensive sweep
-- ────────────────────────────────────────────────────────────────

-- equipment_tech: view, create, edit, log_maintenance (NOT cost,
--                 NOT archive, NOT admin)
INSERT INTO public.role_permissions (role_id, permission_id, granted)
SELECT 'equipment_tech', perm.permission_id, true
FROM (VALUES
  ('equipment.view'),
  ('equipment.create'),
  ('equipment.edit'),
  ('equipment.log_maintenance')
) perm(permission_id)
ON CONFLICT (role_id, permission_id) DO UPDATE SET granted = true;

-- assistant_roaster: tighten existing view-only by adding edit + log
INSERT INTO public.role_permissions (role_id, permission_id, granted)
SELECT 'assistant_roaster', perm.permission_id, true
FROM (VALUES
  ('equipment.edit'),
  ('equipment.log_maintenance')
) perm(permission_id)
ON CONFLICT (role_id, permission_id) DO UPDATE SET granted = true;

-- Cost perms: company_admin, facility_admin, manager only
INSERT INTO public.role_permissions (role_id, permission_id, granted)
SELECT r.role_id, perm.permission_id, true
FROM public.user_roles r
CROSS JOIN (VALUES ('equipment.view_cost'), ('equipment.edit_cost')) perm(permission_id)
WHERE r.role_id IN ('company_admin', 'facility_admin', 'manager')
ON CONFLICT (role_id, permission_id) DO UPDATE SET granted = true;

-- Explicitly deny cost perms to lower roles (so deny_message is
-- pulled when they try; and so the dev portal shows them as denied
-- with a clear false rather than absent). Insert with granted=false.
INSERT INTO public.role_permissions (role_id, permission_id, granted)
SELECT r.role_id, perm.permission_id, false
FROM public.user_roles r
CROSS JOIN (VALUES ('equipment.view_cost'), ('equipment.edit_cost')) perm(permission_id)
WHERE r.role_id IN ('roastmaster', 'assistant_roaster', 'equipment_tech', 'sales_person', 'staff')
ON CONFLICT (role_id, permission_id) DO UPDATE SET granted = false;

-- ────────────────────────────────────────────────────────────────
-- Hierarchy comment for the frontend (ROLE_HIERARCHY in
-- lib/permissions/constants.ts must mirror this — see frontend
-- companion commit).
--   company_admin (0) > facility_admin (1) > manager (2) >
--   sales_person (3) > roastmaster (4) > equipment_tech (5) >
--   assistant_roaster (6) > staff (7)
-- ────────────────────────────────────────────────────────────────
