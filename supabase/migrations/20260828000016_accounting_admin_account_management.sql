-- accounting_admin can manage accounts and reminders.
--
-- The role was created 2026-07-09 with 40 of 105 keys and was missing exactly
-- the three plan-gated customer.* keys: account_management, manage_reminders,
-- send_reminder. role_permissions is GLOBAL and the snapshot treats a missing
-- row as denied — so the customer page wrapped the Management type field in a
-- BlurredUpsell whose requiredPlan DEFAULTS to the literal 'Pro', telling an
-- accounting admin on the top plan to "Upgrade to Pro" for a feature her
-- company already pays for. The plan leg was always fine (enterprise_plus
-- grants all three); only these rows were missing.
--
-- Owner approved granting all three, 2026-08-28.

begin;

insert into public.role_permissions (role_id, permission_id, granted)
values
  ('accounting_admin', 'customer.account_management', true),
  ('accounting_admin', 'customer.manage_reminders',  true),
  ('accounting_admin', 'customer.send_reminder',     true)
on conflict (role_id, permission_id) do update set granted = true;

commit;
