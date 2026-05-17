-- ============================================================
-- Equipment permissions (Phase 1 of equipment project)
-- ============================================================
-- 6 new permission keys. All Pro-plan-gated (Starter plans see "Upgrade
-- to Pro" instead of the equipment nav item). Role grants follow the
-- existing customer.* pattern.
-- ============================================================

INSERT INTO public.permissions (permission_id, category, label, description, default_deny_message, is_plan_gated, sort_order)
VALUES
  ('equipment.view',            'equipment', 'View equipment',
    'See the equipment list, equipment details, and maintenance history.',
    'You do not have permission to view equipment.', true, 100),

  ('equipment.create',          'equipment', 'Add equipment',
    'Add a new piece of equipment to a customer profile or in-house location.',
    'You do not have permission to add equipment.', true, 110),

  ('equipment.edit',            'equipment', 'Edit equipment',
    'Edit equipment details (brand, model, serial, location, status).',
    'You do not have permission to edit equipment.', true, 120),

  ('equipment.archive',         'equipment', 'Archive / decommission equipment',
    'Mark equipment as decommissioned or restore decommissioned equipment.',
    'You do not have permission to archive equipment.', true, 130),

  ('equipment.log_maintenance', 'equipment', 'Log maintenance',
    'Record completed maintenance tasks, parts used, and costs.',
    'You do not have permission to log maintenance.', true, 140),

  ('equipment.admin',           'equipment', 'Manage equipment catalog + tech contacts',
    'Override global brand / model / template catalogs and manage tech contact directory for the company.',
    'You do not have permission to manage the equipment catalog.', true, 150)
ON CONFLICT (permission_id) DO NOTHING;


-- ------------------------------------------------------------
-- Plan grants — Pro, Enterprise, Enterprise+ get equipment access.
-- Starter does NOT (mirrors customer.* + roast.* gating).
--
-- FK-safe SELECT: only inserts rows for plans that actually exist in
-- subscription_plans. Staging (squashed baseline, no seed data) has
-- zero plan rows so this becomes a no-op there; prod has all 4 and
-- gets the grants.
-- ------------------------------------------------------------
INSERT INTO public.plan_permissions (plan_id, permission_id, granted)
SELECT p.plan_id, perm.permission_id, true
FROM public.subscription_plans p
CROSS JOIN (VALUES
  ('equipment.view'),
  ('equipment.create'),
  ('equipment.edit'),
  ('equipment.archive'),
  ('equipment.log_maintenance'),
  ('equipment.admin')
) perm(permission_id)
WHERE p.plan_id IN ('pro','enterprise','enterprise_plus')
ON CONFLICT (plan_id, permission_id) DO UPDATE SET granted = true;


-- ------------------------------------------------------------
-- Role grants — same FK-safe pattern against user_roles.
-- ------------------------------------------------------------
-- company_admin, manager, facility_admin: all 6 permissions
INSERT INTO public.role_permissions (role_id, permission_id, granted)
SELECT r.role_id, perm.permission_id, true
FROM public.user_roles r
CROSS JOIN (VALUES
  ('equipment.view'),
  ('equipment.create'),
  ('equipment.edit'),
  ('equipment.archive'),
  ('equipment.log_maintenance'),
  ('equipment.admin')
) perm(permission_id)
WHERE r.role_id IN ('company_admin','manager','facility_admin')
ON CONFLICT (role_id, permission_id) DO UPDATE SET granted = true;

-- roastmaster: view + log_maintenance
INSERT INTO public.role_permissions (role_id, permission_id, granted)
SELECT r.role_id, perm.permission_id, true
FROM public.user_roles r
CROSS JOIN (VALUES ('equipment.view'), ('equipment.log_maintenance')) perm(permission_id)
WHERE r.role_id = 'roastmaster'
ON CONFLICT (role_id, permission_id) DO UPDATE SET granted = true;

-- assistant_roaster, staff, sales_person: view only
INSERT INTO public.role_permissions (role_id, permission_id, granted)
SELECT r.role_id, 'equipment.view', true
FROM public.user_roles r
WHERE r.role_id IN ('assistant_roaster','staff','sales_person')
ON CONFLICT (role_id, permission_id) DO UPDATE SET granted = true;
