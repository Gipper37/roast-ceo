-- An accounting admin could create a product, a recipe and a customer, but not
-- a coffee. This records the stopgap grant that fixed it, and says why it is a
-- stopgap.
--
-- REPORTED 2026-11-19: the accounting admin cannot add a coffee or a
-- consumable, "that button and functionality is gone for them".
--
-- WHAT IT ACTUALLY IS. Both the button and the server action gate on
-- `inventory.edit` -- the display via currentUserCan at
-- app/app/(app)/inventory/page.tsx:129, which hides AddOriginButton (:1070)
-- and AddConsumableButton (:1078); the writes via requirePermission at
-- company/actions.ts:504 (addConsumable) and inventory/actions.ts:282
-- (createCoffeeOriginInline), :355 (createBagSizeInline), :414
-- (ensureBagSizeExists). `role_permissions` had NO ROW for
-- (accounting_admin, inventory.edit), and a missing row is a silent deny. So
-- the affordance was never rendered and the action would have refused anyway.
--
-- 🔴 IT IS NOT A REGRESSION. The role has never held the key.
-- `20260813000001_accounting_admin_inventory_access.sql` granted exactly
-- inventory.view, .receive and .purchase and said in so many words that
-- "inventory.edit, .count, .archive and .void stay with the floor and
-- management ... an accountant reconciling paperwork has no business silently
-- changing the count the roasters just took."
--
-- 🔴🔴 AND THE REASON I FIRST GAVE FOR OVERRIDING THAT NOTE WAS WRONG.
-- I told the owner the grant was safe because the August concern was the stock
-- take, which is `inventory.count` and stays withheld. It is not. THREE things
-- on this key are exactly what August was protecting, and I verified every one
-- of them myself after saying otherwise:
--   * `markLotDepleted` (inventory/actions.ts:3678) gates on **inventory.edit**,
--     not .count, renders behind canEdit at CoffeeInventoryTable.tsx:1571, and
--     calls `record_per_lot_count` writing the target lot to 0 -- a full count
--     snapshot. That IS changing the count the roasters just took.
--   * `mergeLotIntoShipmentLine` (:3179) DELETEs a shipment line and can stamp
--     a shipment received.
--   * cost-center/actions.ts:33, :44, :55, :88 retroactively rewrite
--     shipping_cost, cost_lb, cost_unit and fallback_unit_cost -- historical
--     COGS. That page is hidden from the role, but these are exported
--     'use server' endpoints, so the page gate is not the boundary.
--
-- WHY THE GRANT WAS MADE ANYWAY, AND WHY IT IS TEMPORARY. The owner was shown
-- the three items above and chose, 2026-11-19, to take the broad grant NOW and
-- replace it with a create-only key afterwards -- because his accountant was
-- blocked at his own roastery, and because a `release-*` tag applies EVERY
-- unapplied migration, so the correct narrow fix could not reach prod without
-- also shipping the seven-migration count-unit batch sitting in front of it.
--
-- 🔴 THE ROW WAS WRITTEN LIVE ON PROD FIRST, NOT BY THIS FILE. On 2026-11-19
-- the grant was applied directly to prod (`pwpslalerytymorcodlv`) as the
-- same single idempotent upsert this file contains -- equivalent to the dev
-- portal toggle at /app/dev/permissions, which `setRolePermission`
-- (app/(dev)/actions.ts:385) upserts into this same table through an admin
-- client. Verified at the time: BEFORE = NO ROW, AFTER = true; the four
-- operational keys still withheld; all three live tenants on `enterprise_plus`,
-- which admits the key (it is plan-gated, and `starter` denies it);
-- `currentUserCan` is wrapped in React's request-scoped `cache()`, so it took
-- effect on the next page load with no deploy.
-- This file therefore APPLIES AS A NO-OP ON PROD. It exists so the history
-- explains the live row and so staging and any rebuilt environment match prod
-- instead of silently losing it.
--
-- WHAT THE ROLE GAINS: the two add buttons it was reported for, end to end --
-- Inventory > Coffee > Add Origin (createCoffeeOriginInline) and
-- Inventory > Consumables > Add (addConsumable, plus
-- createResoldProductForConsumable which needs product.create, already held).
-- It also unbreaks the Products page, where ProductsTable.tsx:1406 renders the
-- same Add Consumable modal behind `product.edit` -- which the role DOES hold --
-- so that form opened and Save threw.
--
-- WHAT IT STILL CANNOT DO: inventory.count, .archive, .void and .merge stay
-- withheld, and checks 4 and 5 below prove it. Creating a coffee SOURCE under
-- a new coffee also stays blocked -- that is `coffee_source.create`
-- (inventory/actions.ts:74, :126, :3786), which the role does not hold and
-- which this grant deliberately does not touch.
--
-- 🔴 WHAT SUPERSEDES THIS, AND WHY THE REVOKE IS NOT IN THIS FILE. A
-- create-only key moves the six create sites to
-- `requireAnyPermission('inventory.create','inventory.edit')`
-- (lib/permissions/server.ts:353, already used at orders/actions.ts:94) and
-- grants the new key to accounting_admin alone -- the other five roles holding
-- inventory.edit keep working untouched, because either key passes. The revoke
-- of inventory.edit CANNOT ride with that migration: CI applies the DB change
-- on a tag while the frontend is a separate manual promote, so between the two
-- the deployed frontend still names only `inventory.edit` and revoking it there
-- would break the accountant a second time. The revoke is its own migration,
-- after the promote.
--
-- PROVENANCE. One idempotent upsert; no function bodies touched, no triggers,
-- no `role`. Rehearsed on a local copy of prod's schema with the full
-- 139-permission / 722-row grant matrix seeded from prod: bug reproduced
-- (NO ROW), applied exit 0, idempotent on a second apply, and a negative
-- control (granting inventory.count first) proved the verify block can raise.

begin;

insert into public.role_permissions (role_id, permission_id, granted)
values ('accounting_admin', 'inventory.edit', true)
on conflict (role_id, permission_id) do update
  set granted    = true,
      updated_at = now();

do $$
declare v_n integer;
begin
  -- 1. the grant is in force.
  if not exists (
    select 1 from public.role_permissions
     where role_id = 'accounting_admin' and permission_id = 'inventory.edit' and granted
  ) then
    raise exception 'accounting_admin still does not hold inventory.edit, so the add-coffee button stays hidden';
  end if;

  -- 2. the key exists in the catalogue. A key absent from `permissions` is
  --    denied silently however the role rows read, so this is not redundant.
  if not exists (select 1 from public.permissions where permission_id = 'inventory.edit') then
    raise exception 'inventory.edit is missing from the permissions catalogue, so the grant above can never be consulted';
  end if;

  -- 3. 🔴 THE PLAN LEG. A granted role with a denying plan is a silent no, and
  --    both legs must admit the same roles for the gate to open.
  if not exists (
    select 1 from public.plan_permissions
     where permission_id = 'inventory.edit' and plan_id = 'enterprise_plus' and granted
  ) then
    raise exception 'inventory.edit is not granted on enterprise_plus, so the live accounting admin would still be denied by the plan';
  end if;

  -- 4. CONTROLS THAT MUST STILL HOLD: the keys August withheld stay withheld.
  --    Without these, granting the wrong key passes checks 1-3 just as well.
  select count(*) into v_n from public.role_permissions
   where role_id = 'accounting_admin'
     and permission_id in ('inventory.count','inventory.archive','inventory.void','inventory.merge')
     and granted;
  if v_n <> 0 then
    raise exception 'accounting_admin now holds % of the operational inventory keys (count/archive/void/merge); this migration was only meant to grant .edit', v_n;
  end if;

  -- 5. and the three keys it already had are untouched.
  if (select count(*) from public.role_permissions
       where role_id = 'accounting_admin'
         and permission_id in ('inventory.view','inventory.receive','inventory.purchase')
         and granted) <> 3 then
    raise exception 'accounting_admin lost one of inventory.view / .receive / .purchase';
  end if;
end $$;

commit;
