-- The accounting admin runs the back office.
--
-- OWNER, 2026-11-20: "i don't give a fuck what you do as long as the accounting
-- admin can do everything she needs to do to manages orders, invoices,
-- shipments, and all items related to those things."
--
-- So the scope is those four areas, COMPLETE, rather than one key at a time.
-- 20261119000002 granted inventory.edit and 20261119000003 split off
-- inventory.create; between them the role could add a coffee and a consumable
-- and nothing else new. This file closes the rest of the back office in one
-- pass. 24 keys, all additive -- it revokes nothing.
--
-- 🔴 IT DELIBERATELY REVERSES 20260813000001, which withheld inventory.edit,
-- .count, .archive and .void from this role because "an accountant reconciling
-- paperwork has no business silently changing the count the roasters just
-- took." That was my judgement, not a requirement, and the owner has now
-- overruled it twice. Taking the key away is what broke her.
--
-- WHY EACH GROUP IS IN SCOPE. Every key below was verified to have a live gate
-- site in the deployed frontend, and every one is granted by `enterprise_plus`,
-- which all four tenants are on -- so no plan leg denies any of them.
--
--   ORDERS, completing the category (she had view/create/edit/cancel):
--     order.pack, order.out_of_stock, order.revision_view,
--     order.revision_acknowledge. Without the last two she cannot see that an
--     order was revised, let alone clear the warning -- she manages orders
--     while being blind to the one state that needs a decision.
--
--   INVOICES / RECEIVABLES:
--     payment.refund -- she can take a card payment by phone
--       (payment.charge_card, held) and record and write off payments, but not
--       reverse one. refundActions.ts:425/:566/:743 all require this key.
--     invoice.process -- supplier-invoice extraction, the Inventory > Invoices
--       tab. Enforced ONLY at app/api/invoice/process/route.ts:91, and it has
--       been since long before the de-blanket; the tab previously rendered for
--       her on inventory.edit and the upload then failed at the route. She is
--       the person who processes supplier invoices.
--
--   SHIPMENTS:
--     inventory.count -- NOT just the stock take. recordLotReceipt (:3580),
--       recordLotReceipts (:3613), dismissLotReceipt (:3640) and
--       recordPerLotCount (:3297) in inventory/actions.ts all require it, and
--       those are the per-lot receiving path. inventory.receive alone does not
--       finish a receive.
--     inventory.void -- void a shipment. inventory.archive, inventory.merge --
--       archive an item, combine two stock rows (the "Combine them" button,
--       ShipmentTable.tsx:1727).
--     trace.waive -- she already reconciles unassigned lots (trace.reconcile);
--       without the waive she reconciles down to the cases that cannot be
--       reconciled and stops.
--
--   THE ITEMS THOSE TOUCH:
--     supplier.create, supplier.edit, supplier.archive -- a shipment comes from
--       a supplier. She could not add one.
--     coffee_source.create, coffee_source.edit -- a received coffee shipment
--       lands as a lot. 20261119000003 explicitly left these out and said they
--       needed their own question; this is the answer to it.
--     product.merge -- the counterpart of inventory.merge for finished goods.
--     pack.count -- count bagged stock, i.e. the finished goods an order ships.
--     customer.merge, customer.chain_manage -- 🔴 THE ONLY TWO FLIPS OF AN
--       EXPLICIT DENY in this file; everything else was a missing row. A
--       customer is the counterparty of every order and invoice, deduping them
--       is an accounting chore, and a chain is a billing structure (a parent
--       billed for its stores). Both are destructive-ish, and she already holds
--       order.cancel, invoice.void and invoice.write_off, which are worse.
--     cost_center.view -- 🔴 THIS ONE TAKES NOTHING NEW. All four Cost Center
--       writers (cost-center/actions.ts:33, :44, :55, :88) already require
--       inventory.edit, which she holds. The page was reachable only by nav,
--       which reads cost_center.view (nav-items.ts:346). So today she can
--       rewrite historical landed cost through the exported 'use server'
--       endpoints but cannot open the page that does it -- hidden-but-allowed,
--       which is the worse of the two failures. This makes the screen match the
--       capability.
--     reports.view, reports.custom -- read-only analysis of exactly the data
--       above. She can export A/R but could not open a report.
--
-- WHAT IS STILL WITHHELD, deliberately, because it is not orders, invoices,
-- shipments or their items -- say the word and any of it is one more row:
--   * Roasting, all 13 (roast.view/.log/.edit_completed/.delete_completed,
--     roast_target.*, roast_stock.*, pack.run/.void/.bin_card, recall.*).
--   * Team, all 7 (invite, role_edit, archive, facility_assign, mfa_reset,
--     floor_staff, terminal.manage).
--   * Company, all 4 -- including company.subscription, which is the STRATA
--     bill rather than a customer invoice.
--   * Configuration, all 19. config.restock_category is the near miss: she can
--     set a lot's restock category (inventory.edit) but not manage the list,
--     and the list lives behind config.view in the Configuration workspace, so
--     granting the one key without the workspace would be a dead grant.
--   * Shop/wholesale, all 5 -- storefront config.
--   * payments.merchant_onboard, payments.credentials_manage -- connecting the
--     gateway and KYC are company-owner acts, not invoice management. Also the
--     four deprecated payments.* keys.
--   * equipment.view_cost/.edit_cost/.admin/.manage_pricing, sales.tasks,
--     sales.notes, label.configure.
--
-- 🔴 NO CONFLICT WITH 20261119000002's CHECK 4, which RAISES if this role holds
-- any of inventory.count/.archive/.void/.merge. That file is already applied on
-- prod and on staging (prod head 20261119000003), and `db push` does not
-- re-apply an applied migration. On a rebuilt environment it runs FIRST in
-- timestamp order, before this one grants those keys, so it still passes. The
-- ordering is the reason this is a separate file.
--
-- NO FRONTEND CHANGE IS NEEDED OR COMING. Every key below is already named by a
-- gate in the deployed production frontend (a1dc1503), display and server both,
-- so these rows light up existing controls. getRequestPermissionSnapshot is
-- wrapped in React's request-scoped cache(), so it takes effect on her next
-- page load with no deploy.
--
-- PROVENANCE. One idempotent upsert over a VALUES list, no function bodies, no
-- triggers, no `role`, no DDL. Additive: nothing is set to false, so no other
-- role's access changes and this cannot re-break her.

begin;

insert into public.role_permissions (role_id, permission_id, granted, deny_message, updated_by)
select 'accounting_admin', k, true, null, 'migration:20261120000001'
  from (values
    -- orders
    ('order.pack'), ('order.out_of_stock'),
    ('order.revision_view'), ('order.revision_acknowledge'),
    -- invoices / receivables
    ('payment.refund'), ('invoice.process'),
    -- shipments
    ('inventory.count'), ('inventory.void'),
    ('inventory.archive'), ('inventory.merge'), ('trace.waive'),
    -- the items those touch
    ('supplier.create'), ('supplier.edit'), ('supplier.archive'),
    ('coffee_source.create'), ('coffee_source.edit'),
    ('product.merge'), ('pack.count'),
    ('customer.merge'), ('customer.chain_manage'),
    ('cost_center.view'),
    -- reading the result
    ('reports.view'), ('reports.custom'),
    -- fulfilment of those orders (she already has view / zones / customer day)
    ('delivery.mark_delivered')
  ) as t(k)
on conflict (role_id, permission_id) do update
  set granted      = true,
      deny_message = null,
      updated_at   = now(),
      updated_by   = 'migration:20261120000001';

do $$
declare
  v_missing text;
  v_n       integer;
  v_keys    text[] := array[
    'order.pack','order.out_of_stock','order.revision_view','order.revision_acknowledge',
    'payment.refund','invoice.process',
    'inventory.count','inventory.void','inventory.archive','inventory.merge','trace.waive',
    'supplier.create','supplier.edit','supplier.archive',
    'coffee_source.create','coffee_source.edit',
    'product.merge','pack.count',
    'customer.merge','customer.chain_manage','cost_center.view',
    'reports.view','reports.custom','delivery.mark_delivered'];
begin
  -- ── CONTROL THAT MUST PASS, non-vacuity first ────────────────────────────
  -- Every check below is a set comparison against v_keys. If the catalogue is
  -- missing one of these, buildPermissionSnapshot never visits it
  -- (lib/permissions/server.ts:576) and the grant is unreachable no matter how
  -- the role row reads -- and the "all granted" check would still pass.
  --
  -- 🔴 BUT IT CANNOT FIRE, AND I MEASURED THAT RATHER THAN ASSUMING IT. Deleting
  -- a catalogue row in the rehearsal raised 23503 from the INSERT above, not
  -- P0001 from here: role_permissions.permission_id has an FK to
  -- permissions(permission_id), so a missing key is refused earlier and more
  -- cheaply than this check could. Same for check 1 below -- in one transaction
  -- it reads back what the insert just wrote. Both are kept as a statement of
  -- intent for whoever edits the VALUES list, NOT as live guards. The checks
  -- that genuinely fire are 2, 3 and 4; each was proved to raise on a seeded
  -- copy of prod's 729-row matrix (P0001, named target, right reason).
  select string_agg(k, ', ' order by k) into v_missing
    from unnest(v_keys) as t(k)
   where not exists (select 1 from public.permissions p where p.permission_id = t.k);
  if v_missing is not null then
    raise exception 'absent from the permissions catalogue, so these grants can never be consulted: %', v_missing;
  end if;

  if array_length(v_keys, 1) <> 24 then
    raise exception 'the key list is % long, not the 24 this file was written for', array_length(v_keys, 1);
  end if;

  -- ── 1. every key is in force for the role ────────────────────────────────
  select string_agg(k, ', ' order by k) into v_missing
    from unnest(v_keys) as t(k)
   where not exists (
     select 1 from public.role_permissions rp
      where rp.role_id = 'accounting_admin' and rp.permission_id = t.k and rp.granted);
  if v_missing is not null then
    raise exception 'accounting_admin still does not hold: %', v_missing;
  end if;

  -- ── 2. 🔴 THE PLAN LEG. A granted role under a denying plan is a silent no.
  -- Checked against enterprise_plus specifically because that is the plan every
  -- live tenant is on; an ungated key has no plan row and is correctly skipped.
  select string_agg(k, ', ' order by k) into v_missing
    from unnest(v_keys) as t(k)
    join public.permissions p on p.permission_id = t.k and p.is_plan_gated
   where not exists (
     select 1 from public.plan_permissions pp
      where pp.permission_id = t.k and pp.plan_id = 'enterprise_plus' and pp.granted);
  if v_missing is not null then
    raise exception 'plan-gated and denied on enterprise_plus, so the live accounting admin stays refused: %', v_missing;
  end if;

  -- ── 3. CONTROL: nothing she already had was lost ─────────────────────────
  -- This file only ever sets granted = true, so a loss here means the upsert
  -- was edited into something else.
  select count(*) into v_n
    from public.role_permissions
   where role_id = 'accounting_admin'
     and permission_id in ('inventory.view','inventory.receive','inventory.purchase',
                           'inventory.create','inventory.edit',
                           'order.view','order.create','order.edit','order.cancel',
                           'invoice.send','invoice.print','invoice.void','invoice.write_off',
                           'payment.record','payment.charge_card','ar.view','ar.export',
                           'customer.view','customer.create','customer.edit',
                           'product.view','product.create','product.edit',
                           'trace.reconcile','accounting.view')
     and granted;
  if v_n <> 25 then
    raise exception 'accounting_admin holds only % of the 25 keys it already had; this migration is additive and must take nothing away', v_n;
  end if;

  -- ── 4. ASSERTION THAT MUST NOT FIRE: it stays off the roasting floor ─────
  -- 🔴 The scope the owner named is orders, invoices, shipments and their
  -- items. Roasting, team and company are not in it, and a grant that reached
  -- them would pass checks 1-3 just as well.
  select string_agg(permission_id, ', ' order by permission_id) into v_missing
    from public.role_permissions
   where role_id = 'accounting_admin' and granted
     and permission_id in ('roast.view','roast.log','roast.edit_completed',
                           'roast.delete_completed','pack.run','pack.void',
                           'team.invite','team.role_edit','team.mfa_reset',
                           'company.edit','company.subscription',
                           'config.features','config.parameters',
                           'shop.configure','shop.products_publish');
  if v_missing is not null then
    raise exception 'accounting_admin now holds %, which is outside orders/invoices/shipments/items; this file does not grant those, so that row came from somewhere else', v_missing;
  end if;

  raise notice 'accounting_admin: 24 keys granted, 25 prior keys intact, roasting/team/company/shop still withheld.';
end $$;

commit;
