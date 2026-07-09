-- ============================================================
-- Accounting roles + accounting-portal permission
-- ============================================================
-- Two new roles for finance/bookkeeping access, scoped to five areas
-- (orders, delivery, products, customers, equipment) + the Accounting
-- portal tab. All other tabs hidden (nav is an allow-list; Roast +
-- Configuration are hidden via hideForRoles in the frontend).
--
--   accounting_admin — view + create + edit + archive/cancel in the five
--                      areas. A back-office role that keeps records current.
--   accounting_view  — VIEW ONLY in the five areas. For outsourced
--                      accountants + the coming reporting engine.
--
-- Both roles are assignable by company_admin only (the frontend
-- MANAGER_ASSIGNABLE_ROLES list deliberately omits them).
--
-- New permission `accounting.view` gates the /app/accounting portal tab +
-- page. NOT plan-gated. Held by both accounting roles + manager /
-- facility_admin / company_admin.
-- ============================================================


-- ── A) Roles ────────────────────────────────────────────────────
INSERT INTO public.user_roles (role_id, role_name, sort_order)
VALUES ('accounting_admin', 'Accounting Admin', 8),
       ('accounting_view',  'Accounting (View Only)', 9)
ON CONFLICT (role_id) DO NOTHING;


-- ── B) Accounting-portal permission ─────────────────────────────
INSERT INTO public.permissions
  (permission_id, category, label, description, default_deny_message, is_plan_gated, sort_order)
VALUES
  ('accounting.view', 'Accounting', 'View the accounting portal',
    'Access the Accounting workspace tab (A/R, invoices, and financial reporting).',
    'You do not have access to the accounting portal.', false, 500)
ON CONFLICT (permission_id) DO NOTHING;


-- ── C) Role grants (SELECT FROM user_roles → FK-safe on baseline envs) ──

-- accounting_admin: full CRUD (view/create/edit/archive-or-cancel) across the
-- five areas + the portal.
INSERT INTO public.role_permissions (role_id, permission_id, granted)
SELECT r.role_id, perm.permission_id, true
FROM public.user_roles r
CROSS JOIN (VALUES
  ('order.view'), ('order.create'), ('order.edit'), ('order.cancel'),
  ('delivery.view'), ('delivery.manage_zones'), ('delivery.assign_customer_day'),
  ('product.view'), ('product.create'), ('product.edit'), ('product.archive'),
  ('recipe.view'), ('recipe.create'), ('recipe.edit'), ('recipe.archive'),
  ('customer.view'), ('customer.create'), ('customer.edit'), ('customer.archive'), ('customer.merge'),
  ('equipment.view'), ('equipment.create'), ('equipment.edit'), ('equipment.archive'), ('equipment.log_maintenance'),
  ('accounting.view')
) perm(permission_id)
WHERE r.role_id = 'accounting_admin'
ON CONFLICT (role_id, permission_id) DO UPDATE SET granted = true;

-- accounting_view: view-only across the five areas + the portal.
INSERT INTO public.role_permissions (role_id, permission_id, granted)
SELECT r.role_id, perm.permission_id, true
FROM public.user_roles r
CROSS JOIN (VALUES
  ('order.view'),
  ('delivery.view'),
  ('product.view'), ('recipe.view'),
  ('customer.view'),
  ('equipment.view'),
  ('accounting.view')
) perm(permission_id)
WHERE r.role_id = 'accounting_view'
ON CONFLICT (role_id, permission_id) DO UPDATE SET granted = true;

-- Portal visibility for the existing admin/manager tiers so they also see the tab.
INSERT INTO public.role_permissions (role_id, permission_id, granted)
SELECT r.role_id, perm.permission_id, true
FROM public.user_roles r
CROSS JOIN (VALUES ('accounting.view')) perm(permission_id)
WHERE r.role_id IN ('company_admin', 'facility_admin', 'manager')
ON CONFLICT (role_id, permission_id) DO UPDATE SET granted = true;

NOTIFY pgrst, 'reload schema';
