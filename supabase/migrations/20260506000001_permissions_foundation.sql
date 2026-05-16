-- ============================================================================
-- Permissions foundation — granular permission grants per role + per plan
-- + developer-user override.
--
-- Replaces the inline `role IN ('manager','company_admin')` checks scattered
-- across server actions and React components with a centralized, editable
-- model. Three axes:
--
--   1. Permissions — atomic capability keys ('customer.delete',
--      'recipe.edit', 'payments.refund', etc).
--
--   2. Role grants — role_permissions(role × permission). A role has the
--      capability when granted=true. Per-row deny_message overrides the
--      permission's default for industry-standard "hidden but explainable"
--      UX.
--
--   3. Plan grants — plan_permissions(plan × permission). The
--      subscription tier the company is on must ALSO grant the permission.
--      Both must say yes for the action to proceed.
--
-- Plus:
--
--   • developer_users — flag on the auth user (NOT in user_roles, which is
--     team-scoped). A developer logs in, sees the dev portal, can
--     impersonate any company as company_admin.
--
--   • developer_impersonation_log — audit row per impersonation session.
--     Required for compliance + support transparency.
--
-- Phase A intent: stand up the schema + seed initial grants to MATCH
-- current hardcoded behavior exactly so flipping to permission-driven
-- checks in Phase B is a no-op for existing users. Anything we want to
-- change behaviorally (e.g. wholesale shop becoming plan-agnostic) is
-- done as a follow-up data migration, never silently.
-- ============================================================================

BEGIN;

/* ────────────────────────────────────────────────────────────────────
 * 1. permissions — the catalog of atomic capabilities
 * ──────────────────────────────────────────────────────────────────── */

CREATE TABLE IF NOT EXISTS permissions (
  permission_id        text PRIMARY KEY,        -- e.g. 'customer.delete'
  category             text NOT NULL,           -- 'Customers' / 'Inventory' / etc, drives portal UI grouping
  label                text NOT NULL,           -- human-readable: "Delete customers"
  description          text,                    -- context shown in the dev portal
  default_deny_message text NOT NULL DEFAULT
    'You don''t have permission to do that. Contact your administrator if you need access.',
  -- Set to true when the capability is meaningless without a network
  -- (e.g. payments) so the portal can disable rather than hide rows
  -- when the company's plan doesn't include it.
  is_plan_gated        boolean NOT NULL DEFAULT false,
  sort_order           integer NOT NULL DEFAULT 0,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE permissions IS
  'Catalog of atomic capability keys ("customer.delete", "recipe.edit"). '
  'role_permissions + plan_permissions both reference this. Source of '
  'truth for what permission strings exist in the system.';

CREATE INDEX IF NOT EXISTS idx_permissions_category_sort
  ON permissions (category, sort_order, permission_id);

/* ────────────────────────────────────────────────────────────────────
 * 2. role_permissions — does a role have a permission?
 * ──────────────────────────────────────────────────────────────────── */

CREATE TABLE IF NOT EXISTS role_permissions (
  role_id        text NOT NULL REFERENCES user_roles(role_id) ON DELETE CASCADE,
  permission_id  text NOT NULL REFERENCES permissions(permission_id) ON DELETE CASCADE,
  granted        boolean NOT NULL DEFAULT false,
  -- Per-role override of the permission's default deny message. NULL =
  -- use the default. Lets the developer-portal customize the message
  -- per role ("Roastmasters can't delete customers — talk to a manager")
  -- without scattering text across the codebase.
  deny_message   text,
  updated_at     timestamptz NOT NULL DEFAULT now(),
  updated_by     text,
  PRIMARY KEY (role_id, permission_id)
);

COMMENT ON TABLE role_permissions IS
  'Per-role grant table. Edited from the developer portal. '
  'Cascades on permission/role removal so we can never end up with '
  'orphan grants.';

/* ────────────────────────────────────────────────────────────────────
 * 3. plan_permissions — does a subscription tier include a permission?
 * ──────────────────────────────────────────────────────────────────── */

CREATE TABLE IF NOT EXISTS plan_permissions (
  plan_id        text NOT NULL REFERENCES subscription_plans(plan_id) ON DELETE CASCADE,
  permission_id  text NOT NULL REFERENCES permissions(permission_id) ON DELETE CASCADE,
  granted        boolean NOT NULL DEFAULT false,
  updated_at     timestamptz NOT NULL DEFAULT now(),
  -- When changing plan grants for existing customers we want a paper
  -- trail (marketing, billing, support all need to know). updated_reason
  -- is captured by the dev portal on every edit and surfaced on the
  -- audit log.
  updated_reason text,
  PRIMARY KEY (plan_id, permission_id)
);

COMMENT ON TABLE plan_permissions IS
  'Per-plan grant table. Edits are heavily gated in the dev portal '
  'because changing a tier affects every active subscriber.';

/* ────────────────────────────────────────────────────────────────────
 * 4. developer_users — internal staff with cross-company access
 * ──────────────────────────────────────────────────────────────────── */

CREATE TABLE IF NOT EXISTS developer_users (
  auth_user_id  uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  granted_by    text,                                  -- email of who granted; manual for first row
  granted_at    timestamptz NOT NULL DEFAULT now(),
  notes         text,
  is_active     boolean NOT NULL DEFAULT true,
  -- Soft-revoke ts. Permanent removal = DELETE row.
  revoked_at    timestamptz
);

COMMENT ON TABLE developer_users IS
  'Per-auth-user developer flag (NOT a team role — separate from team.role '
  'which is company-scoped). Developer users see /dev portal on login + '
  'can impersonate any company as company_admin via the portal.';

/* ────────────────────────────────────────────────────────────────────
 * 5. developer_impersonation_log — audit trail
 * ──────────────────────────────────────────────────────────────────── */

CREATE TABLE IF NOT EXISTS developer_impersonation_log (
  log_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  developer_id  uuid NOT NULL REFERENCES auth.users(id),
  company_id    text NOT NULL,
  facility_id   text,
  started_at    timestamptz NOT NULL DEFAULT now(),
  ended_at      timestamptz,
  -- Free-text reason the developer entered when starting the session.
  reason        text,
  -- IP + user-agent for compliance — captured at session start.
  ip_address    inet,
  user_agent    text
);

COMMENT ON TABLE developer_impersonation_log IS
  'Append-only audit log. Every developer-portal session that opens '
  'a customer company gets a row here. Required for compliance + '
  'support transparency. Never updated except to set ended_at.';

CREATE INDEX IF NOT EXISTS idx_dev_imp_log_developer_started
  ON developer_impersonation_log (developer_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_dev_imp_log_company_started
  ON developer_impersonation_log (company_id, started_at DESC);

/* ────────────────────────────────────────────────────────────────────
 * 6. Seed initial permission catalog
 *
 *    Each row: a key + category + label + (optional) description.
 *    Initial set was derived from a code audit: every distinct
 *    role-array check in the codebase mapped to one permission per
 *    capability.
 *
 *    Categories follow the natural app navigation so the dev portal
 *    can group them sensibly without extra tables.
 * ──────────────────────────────────────────────────────────────────── */

INSERT INTO permissions (permission_id, category, label, description, sort_order, is_plan_gated) VALUES
  -- Customers
  ('customer.view',          'Customers',     'View customers',                'See the customers list and individual customer pages.', 10, false),
  ('customer.create',        'Customers',     'Create customers',              'Add new customers from the customers tab or order form.', 20, false),
  ('customer.edit',          'Customers',     'Edit customer details',         'Update name, address, contacts, payment terms, etc.', 30, false),
  ('customer.archive',       'Customers',     'Archive / restore customers',   'Soft-delete a customer + bring them back later.', 40, false),
  ('customer.delete',        'Customers',     'Permanently delete customers',  'Hard delete. Rarely needed; archive is preferred.', 50, false),
  ('customer.merge',         'Customers',     'Merge customers',               'Combine two customer records into one.', 60, false),

  -- Orders
  ('order.view',             'Orders',        'View orders',                   '', 10, false),
  ('order.create',           'Orders',        'Create orders',                 '', 20, false),
  ('order.edit',             'Orders',        'Edit orders',                   'Adjust line items, weights, delivery zone, status.', 30, false),
  ('order.cancel',           'Orders',        'Cancel orders',                 '', 40, false),
  ('order.delete',           'Orders',        'Delete orders',                 'Hard delete. Cancel is preferred.', 50, false),

  -- Products + Recipes
  ('product.view',           'Products',      'View products',                 '', 10, false),
  ('product.create',         'Products',      'Create products',               '', 20, false),
  ('product.edit',           'Products',      'Edit products',                 'Includes price, COGS overrides, etc.', 30, false),
  ('product.archive',        'Products',      'Archive / restore products',    '', 40, false),
  ('recipe.view',            'Products',      'View recipes',                  '', 50, false),
  ('recipe.create',          'Products',      'Create recipes',                '', 60, false),
  ('recipe.edit',            'Products',      'Edit recipes',                  'Components, percentages, retention factor.', 70, false),
  ('recipe.archive',         'Products',      'Archive / restore recipes',     '', 80, false),

  -- Inventory (coffee + consumables) — plan-gated
  ('inventory.view',         'Inventory',     'View inventory',                '', 10, true),
  ('inventory.count',        'Inventory',     'Record inventory counts',       'Roastmasters typically have this.', 20, true),
  ('inventory.edit',         'Inventory',     'Edit inventory rows',           'Par, restock, supplier, etc.', 30, true),
  ('inventory.archive',      'Inventory',     'Archive / restore inventory items', '', 40, true),
  ('inventory.purchase',     'Inventory',     'Create purchases / shipments',  'New coffee / consumable orders.', 50, true),
  ('inventory.receive',      'Inventory',     'Receive shipments',             'Mark a shipment as received + log actuals.', 60, true),
  ('inventory.void',         'Inventory',     'Void shipments',                '', 70, true),
  ('coffee_source.create',   'Inventory',     'Create coffee sources (lots)',  '', 80, true),
  ('coffee_source.edit',     'Inventory',     'Edit coffee sources',           '', 90, true),

  -- Roasting
  ('roast.view',             'Roasting',      'View roast log + roast page',   '', 10, false),
  ('roast.log',              'Roasting',      'Log roasts',                    'Add to staged + start a roast session.', 20, false),
  ('roast.edit',             'Roasting',      'Edit completed roasts',         '', 30, false),
  ('roast.delete',           'Roasting',      'Delete roasts',                 '', 40, false),
  ('roast_target.edit',      'Roasting',      'Edit weekly roast targets',     'Per-recipe target overrides.', 50, false),
  ('roast_stock.edit',       'Roasting',      'Edit in-stock roasted',         'Manual roasted-stock adjustment.', 60, false),

  -- Cost Center + Reports — plan-gated
  ('cost_center.view',       'Cost Center',   'View cost center',              '', 10, true),
  ('cost_center.edit',       'Cost Center',   'Edit cost center entries',      '', 20, true),
  ('reports.view',           'Reports',       'View reports',                  '', 10, true),

  -- Configuration
  ('config.parameters',      'Configuration', 'Edit company parameters',       'Retention factor, charge weight defaults, currency, etc.', 10, false),
  ('config.restock_category','Configuration', 'Manage restock categories',     '', 20, false),
  ('config.roaster_unit',    'Configuration', 'Add / edit roaster units',      '', 30, false),
  ('config.import_data',     'Configuration', 'Import roast history',          'Roastmaster + Artisan importers.', 40, false),
  ('config.shopify',         'Configuration', 'Configure Shopify integration', '', 50, false),

  -- Suppliers
  ('supplier.create',        'Suppliers',     'Add suppliers',                 '', 10, false),
  ('supplier.edit',           'Suppliers',    'Edit suppliers',                '', 20, false),
  ('supplier.archive',       'Suppliers',     'Archive / restore suppliers',   '', 30, false),

  -- Wholesale shop (per latest direction: plan-agnostic)
  ('shop.view',              'Wholesale',     'View shop config',              '', 10, false),
  ('shop.configure',         'Wholesale',     'Configure shop (slug, branding, hours, products)', '', 20, false),
  ('shop.products_publish',  'Wholesale',     'Publish products to shop',      '', 30, false),

  -- Payments — plan-gated (Pro+ for now; was Enterprise+)
  ('payments.onboard',       'Payments',      'Complete merchant onboarding (KYC)', '', 10, true),
  ('payments.charge',        'Payments',      'Run card charges',              'Take payment on a shop order.', 20, true),
  ('payments.refund',        'Payments',      'Refund payments',               '', 30, true),
  ('payments.terms_edit',    'Payments',      'Edit customer payment terms',   'Net 15 / 30 / 60 vs card.', 40, true),

  -- Team management
  ('team.invite',            'Team',          'Invite new team members',       '', 10, false),
  ('team.role_edit',         'Team',          'Change team member roles',      'Up to + including the editor''s own level.', 20, false),
  ('team.archive',           'Team',          'Archive / restore team members','', 30, false),
  ('team.facility_assign',   'Team',          'Assign team members to facilities', '', 40, false),

  -- Company / billing
  ('company.edit',           'Company',       'Edit company name',             'Company-admin level.', 10, false),
  ('company.facilities',     'Company',       'Add / edit facilities',         '', 20, false),
  ('company.subscription',   'Company',       'Manage subscription / billing', 'Stripe portal access.', 30, false),

  -- Sales tools
  ('sales.tasks',            'Sales',         'Create + edit sales tasks',     '', 10, false),
  ('sales.notes',            'Sales',         'Create + edit sales notes',     '', 20, false)
ON CONFLICT (permission_id) DO UPDATE SET
  category = EXCLUDED.category,
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  sort_order = EXCLUDED.sort_order,
  is_plan_gated = EXCLUDED.is_plan_gated,
  updated_at = now();

/* ────────────────────────────────────────────────────────────────────
 * 7. Seed role_permissions to MATCH current hardcoded behavior exactly.
 *
 *    Hierarchy (highest privilege first):
 *      company_admin  → everything
 *      facility_admin → everything except company-level (subscription,
 *                       company name, billing edits)
 *      manager        → most things except cross-team admin + billing
 *      roastmaster    → roasting, recipes, view inventory, count stock
 *      assistant_roaster → roast logging only
 *      sales_person   → customers + orders + sales tools (view-only on
 *                       most operational data)
 *      staff          → view-only across the board, basic order entry
 *
 *    These mirror the role-array constants we audited:
 *      MANAGER_ROLES = ['manager','facility_admin','company_admin']
 *      INVENTORY_ROLES = ['roastmaster','assistant_roaster',
 *                         'manager','facility_admin','company_admin']
 *
 *    Phase B will read these grants instead of hardcoded arrays. Until
 *    then, behavior is identical because the seed precisely matches.
 * ──────────────────────────────────────────────────────────────────── */

-- Helper: grant a permission to a role.
CREATE OR REPLACE FUNCTION pg_temp.grant_perm(p_role text, p_perm text) RETURNS void AS $$
BEGIN
  INSERT INTO role_permissions (role_id, permission_id, granted)
  VALUES (p_role, p_perm, true)
  ON CONFLICT (role_id, permission_id) DO UPDATE SET granted = true, updated_at = now();
END;
$$ LANGUAGE plpgsql;

-- company_admin: every permission
INSERT INTO role_permissions (role_id, permission_id, granted)
SELECT 'company_admin', permission_id, true FROM permissions
ON CONFLICT (role_id, permission_id) DO UPDATE SET granted = true, updated_at = now();

-- facility_admin: every permission except company-level edits + subscription
INSERT INTO role_permissions (role_id, permission_id, granted)
SELECT 'facility_admin', permission_id, true FROM permissions
WHERE permission_id NOT IN ('company.edit', 'company.subscription')
ON CONFLICT (role_id, permission_id) DO UPDATE SET granted = true, updated_at = now();

-- manager: most operational permissions; no role_edit at admin levels
-- (the team.role_edit grant is gated additionally by the level-cap rule
-- in the team-management code itself — we only allow editing roles
-- at or below the editor's own level)
INSERT INTO role_permissions (role_id, permission_id, granted)
SELECT 'manager', permission_id, true FROM permissions
WHERE permission_id IN (
  'customer.view','customer.create','customer.edit','customer.archive','customer.merge',
  'order.view','order.create','order.edit','order.cancel',
  'product.view','product.create','product.edit','product.archive',
  'recipe.view','recipe.create','recipe.edit','recipe.archive',
  'inventory.view','inventory.count','inventory.edit','inventory.archive',
    'inventory.purchase','inventory.receive','inventory.void',
    'coffee_source.create','coffee_source.edit',
  'roast.view','roast.log','roast.edit','roast_target.edit','roast_stock.edit',
  'cost_center.view','cost_center.edit',
  'reports.view',
  'config.parameters','config.restock_category','config.roaster_unit','config.import_data',
    'config.shopify',
  'supplier.create','supplier.edit','supplier.archive',
  'shop.view','shop.configure','shop.products_publish',
  'payments.charge','payments.refund','payments.terms_edit',
  'team.invite','team.role_edit','team.archive','team.facility_assign',
  'company.facilities',
  'sales.tasks','sales.notes'
)
ON CONFLICT (role_id, permission_id) DO UPDATE SET granted = true, updated_at = now();

-- roastmaster: roasting + recipes + view-everything-operational + count
INSERT INTO role_permissions (role_id, permission_id, granted)
SELECT 'roastmaster', permission_id, true FROM permissions
WHERE permission_id IN (
  'customer.view',
  'order.view','order.create',
  'product.view','recipe.view','recipe.create','recipe.edit',
  'inventory.view','inventory.count','coffee_source.create','coffee_source.edit',
  'roast.view','roast.log','roast.edit','roast_target.edit','roast_stock.edit',
  'reports.view',
  'shop.view'
)
ON CONFLICT (role_id, permission_id) DO UPDATE SET granted = true, updated_at = now();

-- assistant_roaster: log roasts; view what's needed to do that
INSERT INTO role_permissions (role_id, permission_id, granted)
SELECT 'assistant_roaster', permission_id, true FROM permissions
WHERE permission_id IN (
  'product.view','recipe.view',
  'inventory.view','inventory.count',
  'roast.view','roast.log'
)
ON CONFLICT (role_id, permission_id) DO UPDATE SET granted = true, updated_at = now();

-- sales_person: customer + order management, sales tools. View-only on ops.
INSERT INTO role_permissions (role_id, permission_id, granted)
SELECT 'sales_person', permission_id, true FROM permissions
WHERE permission_id IN (
  'customer.view','customer.create','customer.edit','customer.archive','customer.merge',
  'order.view','order.create','order.edit','order.cancel',
  'product.view','recipe.view',
  'reports.view',
  'sales.tasks','sales.notes',
  'shop.view'
)
ON CONFLICT (role_id, permission_id) DO UPDATE SET granted = true, updated_at = now();

-- staff: view-only operational + basic order entry
INSERT INTO role_permissions (role_id, permission_id, granted)
SELECT 'staff', permission_id, true FROM permissions
WHERE permission_id IN (
  'customer.view','customer.create',
  'order.view','order.create',
  'product.view','recipe.view',
  'roast.view','inventory.view'
)
ON CONFLICT (role_id, permission_id) DO UPDATE SET granted = true, updated_at = now();

/* ────────────────────────────────────────────────────────────────────
 * 8. Seed plan_permissions
 *
 *    Three plan-gated permission categories:
 *      Inventory         (Pro+)
 *      Cost Center       (Pro+)
 *      Reports           (Pro+)
 *      Payments          (Pro+ — confirmed by user, was Enterprise+)
 *
 *    Wholesale shop is plan-AGNOSTIC per latest direction (we make
 *    money on processing fees, want adoption). All shop.* permissions
 *    are granted to every plan.
 *
 *    Plans currently:  starter, pro, enterprise, enterprise_plus
 * ──────────────────────────────────────────────────────────────────── */

-- All plans: every NON-plan-gated permission (the role grant alone decides)
INSERT INTO plan_permissions (plan_id, permission_id, granted)
SELECT sp.plan_id, p.permission_id, true
FROM subscription_plans sp
CROSS JOIN permissions p
WHERE p.is_plan_gated = false
ON CONFLICT (plan_id, permission_id) DO UPDATE SET granted = true, updated_at = now();

-- starter: only the FREE plan-gated capabilities (none, by design — Starter
-- is "core orders/customers/roasts" only). Inventory + Cost Center +
-- Reports + Payments all OFF.
INSERT INTO plan_permissions (plan_id, permission_id, granted)
SELECT 'starter', permission_id, false FROM permissions
WHERE is_plan_gated = true
ON CONFLICT (plan_id, permission_id) DO UPDATE SET granted = false, updated_at = now();

-- pro / enterprise / enterprise_plus: every plan-gated permission ON
INSERT INTO plan_permissions (plan_id, permission_id, granted)
SELECT plan_id, permission_id, true
FROM (VALUES ('pro'), ('enterprise'), ('enterprise_plus')) AS p(plan_id)
CROSS JOIN permissions
WHERE is_plan_gated = true
ON CONFLICT (plan_id, permission_id) DO UPDATE SET granted = true, updated_at = now();

COMMIT;
