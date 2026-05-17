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
-- Starter does NOT (mirrors how customer.* + roast.* are gated).
-- ------------------------------------------------------------
INSERT INTO public.plan_permissions (plan_id, permission_id)
SELECT p.plan_id, perm.permission_id
FROM (VALUES ('pro'), ('enterprise'), ('enterprise_plus')) p(plan_id)
CROSS JOIN (VALUES
  ('equipment.view'),
  ('equipment.create'),
  ('equipment.edit'),
  ('equipment.archive'),
  ('equipment.log_maintenance'),
  ('equipment.admin')
) perm(permission_id)
ON CONFLICT (plan_id, permission_id) DO NOTHING;


-- ------------------------------------------------------------
-- Role grants
-- ------------------------------------------------------------
-- company_admin, manager, facility_admin: everything
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.role_id, perm.permission_id
FROM (VALUES ('company_admin'), ('manager'), ('facility_admin')) r(role_id)
CROSS JOIN (VALUES
  ('equipment.view'),
  ('equipment.create'),
  ('equipment.edit'),
  ('equipment.archive'),
  ('equipment.log_maintenance'),
  ('equipment.admin')
) perm(permission_id)
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- roastmaster: view + log_maintenance (does the in-house roaster work daily)
INSERT INTO public.role_permissions (role_id, permission_id)
VALUES
  ('roastmaster', 'equipment.view'),
  ('roastmaster', 'equipment.log_maintenance')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- assistant_roaster, staff: view only
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.role_id, 'equipment.view'
FROM (VALUES ('assistant_roaster'), ('staff')) r(role_id)
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- sales_person: view (customer equipment matters for them; e.g. "what
-- gear does this account have?" is a sales-relevant question)
INSERT INTO public.role_permissions (role_id, permission_id)
VALUES ('sales_person', 'equipment.view')
ON CONFLICT (role_id, permission_id) DO NOTHING;
