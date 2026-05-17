-- ============================================================================
-- User-directed permission catalog adjustments.
--
-- After Phase A's "match current behavior" seed, the user walked
-- through every page and prescribed who-can-do-what. This migration
-- applies all of those decisions.
--
-- Five buckets of changes:
--
--   1. ADD — 8 new permission keys for capabilities that previously
--      had no covering key (Connections tab, channel CRUD, etc.) +
--      the staged/completed roast delete split.
--
--   2. REMOVE — 4 keys retired:
--        - roast.manage_roasters (redundant with config.roaster_unit)
--        - customer.delete, order.delete, roast.delete (archive-only
--          policy — STRATA preserves historical data + foreign-key
--          integrity instead of hard-deleting). Per-key replacements
--          via .archive / .cancel / .delete_completed cover the real
--          capabilities.
--
--   3. LOWER — extend existing grants downward to lower-privilege
--      roles (e.g. recipe.archive lowered to roastmaster+, order.edit
--      lowered to asst_roaster+ for pack/deliver/status flow).
--
--   4. RAISE — revoke grants from previously-allowed roles (e.g.
--      company.facilities is now company_admin only; shop.configure
--      raised to facility_admin+).
--
--   5. SPLIT — config.roaster_unit splits into create/edit (roastmaster+)
--      vs archive (manager+). supplier.create/edit lowered while
--      supplier.archive stays manager+.
--
-- Phase B will flip the corresponding TS callsites to consume these
-- new grants. Until then behavior follows the still-hardcoded role
-- arrays — this migration only changes the permission CATALOG, not
-- runtime gating.
-- ============================================================================

BEGIN;

/* ────────────────────────────────────────────────────────────────────
 * 1. ADD — new permission keys
 * ──────────────────────────────────────────────────────────────────── */

INSERT INTO permissions (permission_id, category, label, description, sort_order, is_plan_gated) VALUES
  ('config.connections',      'Configuration', 'Configure connected devices',
    'Bluetooth thermometer, Loring Modbus, future Probat/Giesen integrations. Configures local hardware in the desktop app.',
    35, false),

  ('config.roaster_unit.archive', 'Configuration', 'Archive / restore roaster units',
    'Soft-delete a roaster unit. Distinct from create/edit which is roastmaster+; archive is manager+ since it affects scheduling + historical attribution.',
    32, false),

  ('channel.create',          'Configuration', 'Create sales channels',
    'Add a new sales channel (Wholesale, Online, etc) used for order categorization + reporting.',
    60, false),
  ('channel.edit',            'Configuration', 'Edit sales channels',     '', 61, false),
  ('channel.archive',         'Configuration', 'Archive / restore sales channels', '', 62, false),

  ('roast.edit_completed',    'Roasting', 'Edit completed (post-drop) roasts',
    'Modify a finished roast — adjust events, charge weight, recipe, notes after the fact. Distinct from roast.log which manages staged roasts pre-charge.',
    35, false),

  ('roast.delete_completed',  'Roasting', 'Delete completed roasts',
    'Permanent removal of a roast_log row + its session/nodes/events. Rare; used for clear data-entry mistakes.',
    45, false),

  ('shop.customer_invite',    'Wholesale', 'Invite customers to the wholesale shop',
    'Send shop-access invitations + manage which customers can sign in.',
    25, false)
ON CONFLICT (permission_id) DO UPDATE SET
  category = EXCLUDED.category,
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  sort_order = EXCLUDED.sort_order,
  is_plan_gated = EXCLUDED.is_plan_gated,
  updated_at = now();

/* ────────────────────────────────────────────────────────────────────
 * 2. REMOVE — retire keys we don't need
 *
 *    Cascade via FK on role_permissions / plan_permissions, so this
 *    drops the grants too.
 * ──────────────────────────────────────────────────────────────────── */

DELETE FROM permissions WHERE permission_id IN (
  'roast.manage_roasters', -- redundant with config.roaster_unit
  'customer.delete',       -- archive-only model
  'order.delete',          -- archive-only model (order.cancel covers it)
  'roast.delete'           -- replaced by roast.delete_completed split
);

/* ────────────────────────────────────────────────────────────────────
 * 3. Plan grants for new permissions
 *    None of the new ones are plan-gated → granted to every plan.
 * ──────────────────────────────────────────────────────────────────── */

INSERT INTO plan_permissions (plan_id, permission_id, granted)
SELECT sp.plan_id, perm, true
FROM subscription_plans sp
CROSS JOIN (VALUES
  ('config.connections'),
  ('config.roaster_unit.archive'),
  ('channel.create'),
  ('channel.edit'),
  ('channel.archive'),
  ('roast.edit_completed'),
  ('roast.delete_completed'),
  ('shop.customer_invite')
) AS p(perm)
ON CONFLICT (plan_id, permission_id) DO UPDATE SET granted = true, updated_at = now();

/* ────────────────────────────────────────────────────────────────────
 * 4. Role grants — explicit per-role per-permission. Layered on top
 *    of Phase A's seed: this block only modifies what changes.
 * ──────────────────────────────────────────────────────────────────── */

-- Helper: idempotent grant
CREATE OR REPLACE FUNCTION pg_temp.grant_perm(p_role text, p_perm text) RETURNS void AS $$
BEGIN
  INSERT INTO role_permissions (role_id, permission_id, granted)
  VALUES (p_role, p_perm, true)
  ON CONFLICT (role_id, permission_id) DO UPDATE SET granted = true, updated_at = now();
END;
$$ LANGUAGE plpgsql;

-- Helper: idempotent revoke (sets granted=false vs delete so the dev
-- portal can flip it back without losing the row's deny_message).
CREATE OR REPLACE FUNCTION pg_temp.revoke_perm(p_role text, p_perm text) RETURNS void AS $$
BEGIN
  INSERT INTO role_permissions (role_id, permission_id, granted)
  VALUES (p_role, p_perm, false)
  ON CONFLICT (role_id, permission_id) DO UPDATE SET granted = false, updated_at = now();
END;
$$ LANGUAGE plpgsql;

-- ── company_admin / facility_admin: granted everything new ──────────
-- (other than the 'company.*' carve-outs already in Phase A which
--  remain — facility_admin still doesn't get company.edit / company.subscription)
INSERT INTO role_permissions (role_id, permission_id, granted)
SELECT 'company_admin', permission_id, true FROM permissions
ON CONFLICT (role_id, permission_id) DO UPDATE SET granted = true, updated_at = now();

INSERT INTO role_permissions (role_id, permission_id, granted)
SELECT 'facility_admin', permission_id, true FROM permissions
WHERE permission_id NOT IN ('company.edit', 'company.subscription')
ON CONFLICT (role_id, permission_id) DO UPDATE SET granted = true, updated_at = now();

-- ── Configuration ──────────────────────────────────────────────────
SELECT pg_temp.grant_perm('roastmaster',  'config.import_data');     -- LOWER
SELECT pg_temp.grant_perm('roastmaster',  'config.connections');     -- ADD (new key)
SELECT pg_temp.grant_perm('manager',      'config.connections');     -- ADD
SELECT pg_temp.grant_perm('manager',      'config.roaster_unit.archive'); -- ADD (new key)

-- ── Roaster unit (split) ───────────────────────────────────────────
-- create/edit lowered to roastmaster+; archive lives in its own key
-- granted to manager+ only (revoking from roastmaster).
SELECT pg_temp.grant_perm('roastmaster',  'config.roaster_unit');    -- LOWER

-- ── Channels (all new keys, manager+) ──────────────────────────────
SELECT pg_temp.grant_perm('manager',      'channel.create');
SELECT pg_temp.grant_perm('manager',      'channel.edit');
SELECT pg_temp.grant_perm('manager',      'channel.archive');

-- ── Products + variants (LOWER to roastmaster+) ───────────────────
SELECT pg_temp.grant_perm('roastmaster',  'product.create');
SELECT pg_temp.grant_perm('roastmaster',  'product.edit');
SELECT pg_temp.grant_perm('roastmaster',  'product.archive');

-- ── Recipes — recipe.archive added to roastmaster ──────────────────
-- (recipe.create / recipe.edit already granted to roastmaster in Phase A)
SELECT pg_temp.grant_perm('roastmaster',  'recipe.archive');         -- LOWER

-- ── Inventory (Coffees + Consumables) — LOWER to roastmaster+ ──────
SELECT pg_temp.grant_perm('roastmaster',  'inventory.edit');
SELECT pg_temp.grant_perm('roastmaster',  'inventory.archive');

-- ── Inventory.receive — LOWER to asst_roaster+ ────────────────────
SELECT pg_temp.grant_perm('roastmaster',       'inventory.receive');
SELECT pg_temp.grant_perm('assistant_roaster', 'inventory.receive');

-- ── Suppliers — split: create/edit roastmaster+, archive manager+ ──
SELECT pg_temp.grant_perm('roastmaster',  'supplier.create');        -- LOWER
SELECT pg_temp.grant_perm('roastmaster',  'supplier.edit');          -- LOWER
-- supplier.archive stays manager+ (no change from Phase A)

-- ── Orders ─────────────────────────────────────────────────────────
-- order.create stays staff+ (already correct)
-- order.edit lowered to asst_roaster+ (pack/deliver/status flow)
SELECT pg_temp.grant_perm('roastmaster',       'order.edit');
SELECT pg_temp.grant_perm('assistant_roaster', 'order.edit');
-- order.cancel lowered to roastmaster+ (was manager+)
SELECT pg_temp.grant_perm('roastmaster',  'order.cancel');

-- ── Roast — completed split ────────────────────────────────────────
SELECT pg_temp.grant_perm('roastmaster',  'roast.edit_completed');
SELECT pg_temp.grant_perm('roastmaster',  'roast.delete_completed');
-- staged delete is implicit in roast.log (asst_roaster+ already has it)

-- ── Shop ───────────────────────────────────────────────────────────
-- shop.products_publish stays manager+ (already correct)
-- shop.customer_invite (new) at manager+
SELECT pg_temp.grant_perm('manager',  'shop.customer_invite');
-- shop.configure RAISED to facility_admin+ — revoke from manager
SELECT pg_temp.revoke_perm('manager', 'shop.configure');

-- ── Company.facilities RAISED to company_admin only ────────────────
SELECT pg_temp.revoke_perm('manager',        'company.facilities');
SELECT pg_temp.revoke_perm('facility_admin', 'company.facilities');
-- company_admin still has it via the company_admin-grants-everything
-- block above.

COMMIT;
