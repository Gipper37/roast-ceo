-- Pro vs Enterprise differentiation pass.
--
-- Until now, Pro and Enterprise had identical plan_permissions — the
-- marketing site promised Enterprise-only features (AI invoice, Shopify,
-- Sales CRM, contact management with roles, custom reporting) but those
-- weren't actually plan-gated in the DB. This migration:
--
--   1. Flips is_plan_gated=true on the permissions that should differ
--      between Pro and Enterprise (so they show up in /dev/plans grid)
--   2. Removes the existing universal grants on those keys
--   3. Re-grants them only to Enterprise + Enterprise+
--   4. Adds the missing contact.* family (Sales CRM "contact management
--      with roles" promise) — Enterprise + Enterprise+
--   5. Adds reports.custom — Enterprise+ ONLY (matches the marketing
--      claim that custom reporting is the top tier exclusive)
--   6. Backfills max_facilities on subscription_plans (Starter=1, Pro=1,
--      Enterprise=NULL/unlimited, Enterprise+=NULL/unlimited)
--   7. Adds max_roaster_units column with caps (Starter=1, Pro=3,
--      Enterprise=NULL, Enterprise+=NULL)
--
-- NOTE: enforcement code for max_facilities + max_roaster_units lives in
-- a separate frontend change (mirroring the existing max_team_members
-- pattern in addTeamMember). This migration only sets the data.

BEGIN;

/* ─── 1. Flip is_plan_gated on Pro→Enterprise differentiators ─── */
--
-- Configuration → Integrations is split across three sub-tabs with
-- different plan requirements:
--   • Connections (BLE thermometer, Loring modbus, hardware)  → Pro+
--   • Roast (Artisan / Cropster / Roastmaster import tools)   → Ent+
--   • Commerce (Shopify, channel sync)                         → Ent+

UPDATE permissions
SET is_plan_gated = true
WHERE permission_id IN (
  'invoice.process',     -- AI invoice processing — Ent+
  'config.shopify',      -- Commerce sub-tab — Ent+
  'config.import_data',  -- Roast sub-tab (import tools) — Ent+
  'config.connections',  -- Connections sub-tab (hardware) — Pro+
  'sales.notes',         -- Sales CRM — Ent+
  'sales.tasks'          -- Sales pipeline — Ent+
);

/* ─── 2. Wipe existing universal grants on those keys ─── */

DELETE FROM plan_permissions
WHERE permission_id IN (
  'invoice.process',
  'config.shopify',
  'config.import_data',
  'config.connections',
  'sales.notes',
  'sales.tasks'
);

/* ─── 3. Grant per the Pro / Enterprise split ─── */

INSERT INTO plan_permissions (plan_id, permission_id, granted, updated_reason)
VALUES
  -- AI invoice processing — Enterprise + Enterprise+
  ('enterprise',      'invoice.process',    true,  'Marketing claim: AI invoice processing — Enterprise and above'),
  ('enterprise_plus', 'invoice.process',    true,  'Marketing claim: AI invoice processing — Enterprise and above'),
  -- Commerce sub-tab (Shopify) — Enterprise + Enterprise+
  ('enterprise',      'config.shopify',     true,  'Integrations → Commerce — Enterprise and above'),
  ('enterprise_plus', 'config.shopify',     true,  'Integrations → Commerce — Enterprise and above'),
  -- Roast sub-tab (Artisan/Cropster/Roastmaster importers) — Ent+
  ('enterprise',      'config.import_data', true,  'Integrations → Roast import tools — Enterprise and above'),
  ('enterprise_plus', 'config.import_data', true,  'Integrations → Roast import tools — Enterprise and above'),
  -- Connections sub-tab (BLE thermometer, modbus hardware) — Pro+
  ('pro',             'config.connections', true,  'Integrations → Connections (hardware) — Pro and above'),
  ('enterprise',      'config.connections', true,  'Integrations → Connections (hardware) — Pro and above'),
  ('enterprise_plus', 'config.connections', true,  'Integrations → Connections (hardware) — Pro and above'),
  -- Sales CRM / pipeline — Enterprise + Enterprise+
  ('enterprise',      'sales.notes',        true,  'Marketing claim: Sales CRM — Enterprise and above'),
  ('enterprise_plus', 'sales.notes',        true,  'Marketing claim: Sales CRM — Enterprise and above'),
  ('enterprise',      'sales.tasks',        true,  'Marketing claim: Sales pipeline — Enterprise and above'),
  ('enterprise_plus', 'sales.tasks',        true,  'Marketing claim: Sales pipeline — Enterprise and above');

-- Explicit not-granted rows for the lower tiers so the dev portal grid
-- shows them as toggleable (rather than missing entirely).
INSERT INTO plan_permissions (plan_id, permission_id, granted, updated_reason)
SELECT plan_id, permission_id, false, 'Pro/Enterprise gating: not included in lower tier'
FROM (VALUES
  ('starter',  'invoice.process'),
  ('pro',      'invoice.process'),
  ('starter',  'config.shopify'),
  ('pro',      'config.shopify'),
  ('starter',  'config.import_data'),
  ('pro',      'config.import_data'),
  ('starter',  'config.connections'),
  ('starter',  'sales.notes'),
  ('pro',      'sales.notes'),
  ('starter',  'sales.tasks'),
  ('pro',      'sales.tasks')
) AS v(plan_id, permission_id);

/* ─── 3b. Drop cost_center.* — collapse into inventory.* ─── */
--
-- Cost-center entries (shipping costs, per-lb / per-unit purchase costs,
-- consumable last-cost) are fundamentally inventory-cost corrections.
-- They feed the same trigger chain as the rest of inventory and the
-- inventory.* keys already gate the feature for Pro+. Having a separate
-- cost_center.* family was redundant and risked drift.

DELETE FROM plan_permissions WHERE permission_id IN ('cost_center.view', 'cost_center.edit');
DELETE FROM role_permissions WHERE permission_id IN ('cost_center.view', 'cost_center.edit');
DELETE FROM permissions      WHERE permission_id IN ('cost_center.view', 'cost_center.edit');

/* ─── 4. Add contact.* family (Sales CRM contact management) ─── */

INSERT INTO permissions (permission_id, category, label, description, sort_order, is_plan_gated, default_deny_message)
VALUES
  ('contact.view',    'Sales', 'View contacts',     'Browse the contact roster with role tags (decision-maker, accounts payable, etc.).', 30, true, 'Contact management is on Enterprise.'),
  ('contact.create',  'Sales', 'Create contacts',   'Add a new contact and link them to a customer.',                                       40, true, 'Contact management is on Enterprise.'),
  ('contact.edit',    'Sales', 'Edit contacts',     'Update contact details, roles, or assigned customer.',                                 50, true, 'Contact management is on Enterprise.'),
  ('contact.archive', 'Sales', 'Archive contacts',  'Soft-delete a contact (data retained for historical reporting).',                      60, true, 'Contact management is on Enterprise.');

-- Roles: roastmaster+ get full access (mirrors customer.* pattern)
INSERT INTO role_permissions (role_id, permission_id, granted)
SELECT r.role_id, p.permission_id, true
FROM (VALUES ('roastmaster'), ('manager'), ('facility_admin'), ('company_admin')) AS r(role_id)
CROSS JOIN (VALUES ('contact.view'), ('contact.create'), ('contact.edit'), ('contact.archive')) AS p(permission_id);

-- Plan grants: Enterprise + Enterprise+ only (matches sales.* gating)
INSERT INTO plan_permissions (plan_id, permission_id, granted, updated_reason)
VALUES
  ('starter',         'contact.view',    false, 'Sales CRM gating'),
  ('pro',             'contact.view',    false, 'Sales CRM gating'),
  ('enterprise',      'contact.view',    true,  'Sales CRM — Enterprise and above'),
  ('enterprise_plus', 'contact.view',    true,  'Sales CRM — Enterprise and above'),
  ('starter',         'contact.create',  false, 'Sales CRM gating'),
  ('pro',             'contact.create',  false, 'Sales CRM gating'),
  ('enterprise',      'contact.create',  true,  'Sales CRM — Enterprise and above'),
  ('enterprise_plus', 'contact.create',  true,  'Sales CRM — Enterprise and above'),
  ('starter',         'contact.edit',    false, 'Sales CRM gating'),
  ('pro',             'contact.edit',    false, 'Sales CRM gating'),
  ('enterprise',      'contact.edit',    true,  'Sales CRM — Enterprise and above'),
  ('enterprise_plus', 'contact.edit',    true,  'Sales CRM — Enterprise and above'),
  ('starter',         'contact.archive', false, 'Sales CRM gating'),
  ('pro',             'contact.archive', false, 'Sales CRM gating'),
  ('enterprise',      'contact.archive', true,  'Sales CRM — Enterprise and above'),
  ('enterprise_plus', 'contact.archive', true,  'Sales CRM — Enterprise and above');

/* ─── 5. Add reports.custom (Enterprise+ EXCLUSIVE) ─── */

INSERT INTO permissions (permission_id, category, label, description, sort_order, is_plan_gated, default_deny_message)
VALUES
  ('reports.custom', 'Reports', 'Custom reports & dashboards', 'Build custom report queries + save dashboard layouts. Top-tier exclusive.', 20, true, 'Custom reporting is exclusive to Enterprise+.');

-- Roles: manager+ (matches reports.view scope)
INSERT INTO role_permissions (role_id, permission_id, granted)
VALUES
  ('manager',         'reports.custom', true),
  ('facility_admin',  'reports.custom', true),
  ('company_admin',   'reports.custom', true);

-- Plan grants: Enterprise+ ONLY
INSERT INTO plan_permissions (plan_id, permission_id, granted, updated_reason)
VALUES
  ('starter',         'reports.custom', false, 'Custom reporting is Enterprise+ exclusive'),
  ('pro',             'reports.custom', false, 'Custom reporting is Enterprise+ exclusive'),
  ('enterprise',      'reports.custom', false, 'Custom reporting is Enterprise+ exclusive'),
  ('enterprise_plus', 'reports.custom', true,  'Custom reporting — top tier exclusive per marketing');

/* ─── 6. Backfill max_facilities ─── */

UPDATE subscription_plans SET max_facilities = 1    WHERE plan_id = 'starter';
UPDATE subscription_plans SET max_facilities = 1    WHERE plan_id = 'pro';
UPDATE subscription_plans SET max_facilities = NULL WHERE plan_id = 'enterprise';      -- unlimited
UPDATE subscription_plans SET max_facilities = NULL WHERE plan_id = 'enterprise_plus';  -- unlimited

/* ─── 7. Add max_roaster_units column ─── */

ALTER TABLE subscription_plans
  ADD COLUMN IF NOT EXISTS max_roaster_units integer;

COMMENT ON COLUMN subscription_plans.max_roaster_units IS
  'Per-facility cap on active roaster units. NULL = unlimited.';

UPDATE subscription_plans SET max_roaster_units = 1    WHERE plan_id = 'starter';
UPDATE subscription_plans SET max_roaster_units = 2    WHERE plan_id = 'pro';
UPDATE subscription_plans SET max_roaster_units = NULL WHERE plan_id = 'enterprise';      -- unlimited
UPDATE subscription_plans SET max_roaster_units = NULL WHERE plan_id = 'enterprise_plus';  -- unlimited

COMMIT;
