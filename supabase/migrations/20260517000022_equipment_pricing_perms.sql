-- ============================================================
-- Permission: equipment.manage_pricing
-- ============================================================
-- Manager+ only. Gates the Configuration → Equipment Pricing tab
-- (CRUD labor rates, default trip fee / tax / markup, parts catalog
-- override). Distinct from equipment.edit_cost which gates per-task
-- price entry at log time.
-- ============================================================

INSERT INTO public.permissions
  (permission_id, category, label, description, default_deny_message, is_plan_gated, sort_order)
VALUES
  ('equipment.manage_pricing', 'equipment', 'Manage equipment pricing catalog',
    'Create and edit labor rates, pricing defaults, and the parts catalog. Distinct from per-task cost entry.',
    'You do not have permission to manage equipment pricing.', true, 180)
ON CONFLICT (permission_id) DO NOTHING;

-- Plan grants — Pro+
INSERT INTO public.plan_permissions (plan_id, permission_id, granted)
SELECT p.plan_id, 'equipment.manage_pricing', true
FROM public.subscription_plans p
WHERE p.plan_id IN ('pro','enterprise','enterprise_plus')
ON CONFLICT (plan_id, permission_id) DO UPDATE SET granted = true;

-- Role grants — manager+ only
INSERT INTO public.role_permissions (role_id, permission_id, granted)
SELECT r.role_id, 'equipment.manage_pricing', true
FROM public.user_roles r
WHERE r.role_id IN ('company_admin', 'facility_admin', 'manager')
ON CONFLICT (role_id, permission_id) DO UPDATE SET granted = true;

-- Explicit deny for lower roles
INSERT INTO public.role_permissions (role_id, permission_id, granted)
SELECT r.role_id, 'equipment.manage_pricing', false
FROM public.user_roles r
WHERE r.role_id IN ('roastmaster', 'assistant_roaster', 'equipment_tech', 'sales_person', 'staff')
ON CONFLICT (role_id, permission_id) DO UPDATE SET granted = false;
