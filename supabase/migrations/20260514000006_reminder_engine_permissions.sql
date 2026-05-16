-- =============================================================================
-- Reminder engine permissions (Phase 2)
-- =============================================================================
-- Two new permission keys for the smart account-management workflow:
--
--   customer.send_reminder    — Fire a reminder send. Used by the
--                               manual "Send now" button on the
--                               customer detail AND by the cron's
--                               per-customer auto-fire check (cron
--                               skips any customer whose company
--                               plan doesn't have it).
--   customer.manage_reminders — Snooze, unsubscribe a customer,
--                               change reminder cadence overrides.
--
-- Plan gating: Pro+ only.
--   Starter           → NOT granted (granted=false explicit row so
--                       the upsell affordance has something to read)
--   Pro               → granted
--   Enterprise        → granted
--   Enterprise+       → granted
--
-- Starter operators still SEE the "Customer-Initiated with
-- Reminders" management type in the dropdown — it just appears
-- disabled with an upsell tooltip ("Available on Pro plan or
-- higher"). Frontend reads `customer.send_reminder` to decide.
-- =============================================================================

INSERT INTO public.permissions (permission_id, label, category, description, is_plan_gated)
VALUES
  ('customer.send_reminder',
   'Send customer reminder',
   'Customers',
   'Fire reminder emails to customers (manual button + cron auto-send for Customer-Initiated with Reminders management type).',
   true),
  ('customer.manage_reminders',
   'Manage customer reminders',
   'Customers',
   'Snooze, unsubscribe, or change reminder cadence overrides for individual customers.',
   true)
ON CONFLICT (permission_id) DO NOTHING;

-- Plan gates — explicit false rows for Starter so the UI upsell
-- affordance can read a row rather than infer absence.
INSERT INTO public.plan_permissions (plan_id, permission_id, granted, updated_reason)
VALUES
  ('starter',         'customer.send_reminder',    false, 'Reminder engine = Pro+ feature'),
  ('starter',         'customer.manage_reminders', false, 'Reminder engine = Pro+ feature'),
  ('pro',             'customer.send_reminder',    true,  'Reminder engine = Pro+ feature'),
  ('pro',             'customer.manage_reminders', true,  'Reminder engine = Pro+ feature'),
  ('enterprise',      'customer.send_reminder',    true,  'Reminder engine = Pro+ feature'),
  ('enterprise',      'customer.manage_reminders', true,  'Reminder engine = Pro+ feature'),
  ('enterprise_plus', 'customer.send_reminder',    true,  'Reminder engine = Pro+ feature'),
  ('enterprise_plus', 'customer.manage_reminders', true,  'Reminder engine = Pro+ feature')
ON CONFLICT (plan_id, permission_id) DO UPDATE
  SET granted = EXCLUDED.granted, updated_reason = EXCLUDED.updated_reason;

-- Role permissions: company_admin + manager get both perms by
-- default (they already get the full customer.* set today). Lower
-- roles get neither. Adjust later if per-role gating needed.
INSERT INTO public.role_permissions (role_id, permission_id, granted)
SELECT r.role_id, p.permission_id, true
FROM (VALUES ('company_admin'), ('facility_admin'), ('manager')) AS r(role_id)
CROSS JOIN (VALUES ('customer.send_reminder'), ('customer.manage_reminders')) AS p(permission_id)
ON CONFLICT (role_id, permission_id) DO UPDATE SET granted = true;

-- Verification:
--   SELECT * FROM permissions WHERE permission_id LIKE 'customer.%reminder%';
--   SELECT * FROM plan_permissions WHERE permission_id LIKE 'customer.%reminder%' ORDER BY 1, 2;
