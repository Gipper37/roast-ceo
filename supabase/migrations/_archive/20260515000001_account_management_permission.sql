-- =============================================================================
-- customer.account_management — Pro+ plan-gated permission
-- =============================================================================
-- Account management (assigning customers to managed types, viewing the
-- Account Management queue tab) is a distinct capability from basic
-- customer CRUD. A staff member with `customer.edit` should still be
-- able to update phone / email / address, but NOT change a customer's
-- management type or open the Account Management dashboard.
--
-- Plan gates: Pro / Enterprise / Enterprise+ granted; Starter NOT
-- granted (explicit false row so the upsell affordance has something
-- to read). Mirrors the existing reminder permissions (Pro+ feature
-- family).
--
-- Role grants: company_admin / facility_admin / manager get it by
-- default. Lower roles (roastmaster, assistant_roaster, sales_person,
-- staff) NOT granted — they don't manage customer relationships.
-- =============================================================================

INSERT INTO public.permissions (permission_id, label, category, description, is_plan_gated)
VALUES
  ('customer.account_management',
   'Manage customer accounts',
   'Customers',
   'View the Account Management dashboard and assign customers to managed types (Vendor-Managed Inventory, Vendor-Placed Orders, Standing Order, Customer-Initiated with Reminders, Manually Tracked). Distinct from basic customer.edit which only governs contact-info updates.',
   true)
ON CONFLICT (permission_id) DO NOTHING;

INSERT INTO public.plan_permissions (plan_id, permission_id, granted, updated_reason)
VALUES
  ('starter',         'customer.account_management', false, 'Account management = Pro+ feature family (matches reminder engine gating)'),
  ('pro',             'customer.account_management', true,  'Account management = Pro+ feature family'),
  ('enterprise',      'customer.account_management', true,  'Account management = Pro+ feature family'),
  ('enterprise_plus', 'customer.account_management', true,  'Account management = Pro+ feature family')
ON CONFLICT (plan_id, permission_id) DO UPDATE
  SET granted = EXCLUDED.granted, updated_reason = EXCLUDED.updated_reason;

INSERT INTO public.role_permissions (role_id, permission_id, granted)
SELECT r.role_id, 'customer.account_management', true
FROM (VALUES ('company_admin'), ('facility_admin'), ('manager')) AS r(role_id)
ON CONFLICT (role_id, permission_id) DO UPDATE SET granted = true;

-- Verification:
--   SELECT * FROM permissions WHERE permission_id = 'customer.account_management';
--   SELECT * FROM plan_permissions WHERE permission_id = 'customer.account_management' ORDER BY plan_id;
--   SELECT * FROM role_permissions WHERE permission_id = 'customer.account_management' ORDER BY role_id;
