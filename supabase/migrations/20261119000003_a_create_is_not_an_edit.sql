-- A create is not an edit.
--
-- THE COMPLAINT, 2026-11-19. The accounting admin could not add a coffee or a
-- consumable: "that button and functionality is gone for them". Both the button
-- and the write gate on `inventory.edit`, and `role_permissions` had no row for
-- (accounting_admin, inventory.edit). A missing row is a SILENT DENY, so the
-- affordance never rendered and the action would have refused anyway.
--
-- WHY THE BROAD GRANT WAS MADE LIVE FIRST. On 2026-11-19 (accounting_admin,
-- inventory.edit) was written straight onto prod -- the same single idempotent
-- upsert 20261119000002 records, equivalent to the dev-portal toggle at
-- /app/dev/permissions. It was done that way for one reason: a `release-*` tag
-- applies EVERY unapplied migration, and the correct narrow fix could not reach
-- prod without also shipping the seven-migration count-unit batch sitting in
-- front of it. The owner was shown what the broad key carries, and chose to
-- take it now and split it afterwards -- "toggle now, split later" -- because
-- his accountant was blocked at his own roastery.
--
-- WHAT THIS FILE REPLACES. The toggle, and only the toggle. `inventory.edit` is
-- not "may add an item". The same key also carries, every one verified:
--   * markLotDepleted (app/app/(app)/inventory/actions.ts:3678) -- calls
--     record_per_lot_count writing the target lot to 0, i.e. a full count
--     snapshot. 20260813000001 withheld .edit from this role in exactly those
--     words: an accountant reconciling paperwork "has no business silently
--     changing the count the roasters just took".
--   * mergeLotIntoShipmentLine (:3179) -- DELETEs a shipment line and can stamp
--     a shipment received.
--   * cost-center/actions.ts:33, :44, :55, :88 -- retroactively rewrite
--     shipping_cost, cost_lb, cost_unit and fallback_unit_cost: historical COGS.
--     That page is hidden from the role, but these are exported 'use server'
--     endpoints, so the page gate is not the boundary.
--   * the Inventory > Invoices tab (inventory/page.tsx:188, :1374).
--
-- WHAT THE ROLE GAINS. `inventory.create`: add a coffee group, add a consumable.
-- Nothing else. Named for the family it joins -- product.create, recipe.create,
-- coffee_source.create, supplier.create -- and slotted at sort_order 25 so the
-- Inventory heading reads count (20), create (25), edit (30), the same
-- create-then-edit order coffee_source.create (80) / .edit (90) already uses.
--
-- WHAT IT STILL CANNOT DO. Everything above, plus: run or alter a count, archive
-- or restore, void, merge two stock rows, rename an item or edit its
-- description, type, unit size, shipping weight, lead time, supplier or restock
-- category, set a fallback unit cost, or open the Cost Center. It also does NOT
-- carry creating a coffee SOURCE or a supplier -- those are coffee_source.create
-- and supplier.create, which this role does not hold and this file does not
-- grant.
--
-- WHERE IT IS CONSUMED. FOUR create call sites move from
-- requirePermission('inventory.edit') to
-- requireAnyPermission('inventory.create','inventory.edit')
-- (lib/permissions/server.ts:353, already used at orders/actions.ts:94 and
-- food-safety/actions.ts:253): addConsumable (company/actions.ts:504),
-- createCoffeeOriginInline (inventory/actions.ts:282), addOrigin
-- (roast/actions.ts:1084) and addCoffee (company/actions.ts:321). The narrow key
-- goes FIRST because requireAnyPermission names permissions[0] in the denial, so
-- the person refused is told about the key they could actually be granted --
-- which is why this key carries its own default_deny_message.
--
-- 🔴 AND NOT THE TWO BAG-SIZE WRITERS, though the first pass had them. Neither
-- createBagSizeInline (inventory/actions.ts:355) nor ensureBagSizeExists (:414)
-- is reachable-and-completable by this role, and moving them would buy a
-- half-write instead of a flow:
--   * The add-a-coffee-group modal never touches a bag size. AddOriginModal
--     (roast/logger/EntityAddModals.tsx:240) collects name, restock category,
--     supplier and description and makes exactly one call,
--     createCoffeeOriginInline -- whose own header says "bag_size lives on
--     coffee_source". All three callers of createBagSizeInline are coffee-SOURCE
--     surfaces, and all three completing writes are keys this role lacks:
--     addCoffeeSourceSmart (:3786) and createCoffeeSourceInline (:74) need
--     coffee_source.create, updateCoffeeSource (:187) needs coffee_source.edit.
--   * ensureBagSizeExists has ONE caller, BagSizeField.tsx:311, and line 312 is
--     updateCoffeeSource -- coffee_source.edit again. "Update standard" would
--     still refuse; the only difference would be that the bag_sizes row had
--     already committed first.
--   `bag_sizes` is PRIMARY KEY (bag_size_id) ALONE, platform-wide, so each such
--   abandoned attempt squats a weight for every other tenant. Letting the
--   refusal land at the first write is the better behaviour. If the owner wants
--   the accountant creating coffee sources, that is a coffee_source.create
--   decision and needs its own question.
--
-- GRANTED TO accounting_admin AND TO WHOEVER HOLDS inventory.edit when this
-- applies. Only accounting_admin NEEDS it -- requireAnyPermission passes on
-- either key, so every existing .edit holder keeps working untouched either way.
-- It goes to them anyway because `permissions` x `role_permissions` is the one
-- place an admin answers "who may add a coffee", and a single-role row there
-- would say roastmaster may not, which is false. Read from the live grants
-- rather than from a frozen list of six so that a role which LOST .edit between
-- the measurement and the tag is not silently re-widened, and so the insert and
-- the checks below agree instead of the file asserting against what it just
-- wrote. The five roles that cannot add inventory today are excluded from the
-- insert by name, so a stray .edit grant cannot carry them in. Drift either way
-- is reported as a NOTICE, not an exception: it is a premise change a human
-- should read, not a reason to roll back nine migrations.
--
-- PLAN PROFILE MIRRORED, NOT CHOSEN. is_plan_gated = true with starter=false and
-- pro/enterprise/enterprise_plus=true, which is inventory.edit's profile
-- exactly. Un-gated, or true on starter, would hand a starter tenant an
-- inventory capability it does not have today. feature_key stays NULL: adding
-- stock is not an optional module.
--
-- 🔴 THE REVOKE OF (accounting_admin, inventory.edit) IS NOT IN THIS FILE, AND
-- CANNOT BE. Three independent reasons.
--   1. A `release-*` tag applies the database; the production frontend is a
--      separate manual rebuild-and-promote. Between the two, the deployed
--      frontend names only `inventory.edit`, so revoking it in this same run
--      would hide the two add buttons again -- the original complaint,
--      re-created by its own fix -- plus the shipment cost/receive cells, the
--      shipment detail page's Edit Shipment and Add item, the consumable
--      fallback-cost box, supplier assignment and the Invoices tab, all of
--      which read inventory.edit while their writes ask for inventory.purchase,
--      inventory.receive or product.edit.
--   2. The revoke's safety precondition is a DEPLOYED FRONTEND, not a database
--      state. No verify block can assert what Vercel is serving, so the proof
--      has to be a human opening the live page between the two tags. That
--      boundary is the migration boundary.
--   3. 20261119000002's own check 1 RAISES if accounting_admin does not hold
--      inventory.edit. A grant and a revoke of the same row in one run is
--      self-contradictory history; a revoke in a LATER file applies after it in
--      timestamp order, which stays consistent on prod and on any rebuilt
--      environment.
--
-- PROVENANCE. Three idempotent upserts in FK order, no function bodies, no
-- triggers, no `role`. Additive only: it revokes nothing, so applying it while
-- the stopgap is still in force changes no role's effective access.

begin;

-- ── 1. The key ──────────────────────────────────────────────────────────────
-- Category spelled 'Inventory' to the byte: the dev permissions matrix and the
-- plans matrix both group by this column verbatim, and a lowercase one opens a
-- second section of its own (20260924000009).
insert into public.permissions
  (permission_id, category, label, description, default_deny_message, is_plan_gated, sort_order)
values
  ('inventory.create', 'Inventory', 'Add inventory items',
   'Add a new coffee or a new consumable to inventory. Creating a row is not the same act as correcting one: this key opens the two add buttons without opening counts, lot merges, archiving, voiding or historical cost.',
   'You don''t have permission to add new inventory items. Contact your administrator if you need access.',
   true, 25)
on conflict (permission_id) do update
  set category             = excluded.category,
      label                = excluded.label,
      description          = excluded.description,
      default_deny_message = excluded.default_deny_message,
      is_plan_gated        = excluded.is_plan_gated,
      sort_order           = excluded.sort_order,
      updated_at           = now();

-- ── 2. Who may do it ────────────────────────────────────────────────────────
-- accounting_admin unconditionally -- it is the role this file exists for and
-- the one asserted below -- plus whoever actually holds inventory.edit at apply
-- time, minus the five roles that cannot add inventory today. Excluding them
-- here rather than only asserting it below is deliberate: the file must not be
-- able to cause the violation it then fails on.
insert into public.role_permissions (role_id, permission_id, granted, updated_by)
select r.role_id, 'inventory.create', true, 'migration:20261119000003'
  from (
    select 'accounting_admin'::text as role_id
    union
    select rp.role_id
      from public.role_permissions rp
     where rp.permission_id = 'inventory.edit'
       and rp.granted
       and rp.role_id <> all (array['assistant_roaster','staff','sales_person',
                                    'accounting_view','equipment_tech'])
  ) r
on conflict (role_id, permission_id) do update
  set granted      = true,
      deny_message = null,
      updated_at   = now(),
      updated_by   = 'migration:20261119000003';

-- ── 3. Which plans ──────────────────────────────────────────────────────────
-- Named explicitly, including the false one, so a plan added later has to be
-- decided rather than inheriting a yes.
insert into public.plan_permissions (plan_id, permission_id, granted, updated_reason)
values
  ('enterprise_plus', 'inventory.create', true,  'Adding a coffee or a consumable: mirrors inventory.edit, which this splits'),
  ('enterprise',      'inventory.create', true,  'Adding a coffee or a consumable: mirrors inventory.edit, which this splits'),
  ('pro',             'inventory.create', true,  'Adding a coffee or a consumable: mirrors inventory.edit, which this splits'),
  ('starter',         'inventory.create', false, 'Inventory is not on this plan, so neither is adding to it')
on conflict (plan_id, permission_id) do update
  set granted        = excluded.granted,
      updated_reason = excluded.updated_reason,
      updated_at     = now();

-- ── 4. Verify ───────────────────────────────────────────────────────────────
do $$
declare
  v_gated    boolean;
  v_category text;
  v_order    integer;
  v_feature  text;
  v_plans    integer;
  v_mismatch integer;
  v_roles    text;
begin
  -- ── CONTROLS THAT MUST PASS, non-vacuity first ───────────────────────────
  -- Every mirror check further down compares the new key against
  -- inventory.edit, and a comparison against a key with no rows passes for
  -- free. These three say the thing being mirrored is really there.
  if not exists (select 1 from public.permissions
                  where permission_id = 'inventory.edit' and is_plan_gated) then
    raise exception 'inventory.edit is absent or no longer plan-gated, so there is no plan profile for this file to mirror';
  end if;

  if (select count(*) from public.role_permissions
       where permission_id = 'inventory.edit' and granted) = 0 then
    raise exception 'nobody holds inventory.edit, so the create sites OR against nothing and the role leg below would prove nothing';
  end if;

  if (select count(*) from public.plan_permissions where permission_id = 'inventory.edit')
     <> (select count(*) from public.subscription_plans) then
    raise exception 'inventory.edit does not cover every plan, so mirroring it cannot settle the new key''s plan leg';
  end if;

  -- ── CONTROL: the catalogue row exists and is shaped right ────────────────
  -- buildPermissionSnapshot iterates the ROWS OF `permissions`
  -- (lib/permissions/server.ts:576), so a key with no row is never visited and
  -- reads denied for every role with no message at all, however the grants
  -- below read.
  select is_plan_gated, category, sort_order, feature_key
    into v_gated, v_category, v_order, v_feature
    from public.permissions
   where permission_id = 'inventory.create';

  if v_gated is null then
    raise exception 'inventory.create is missing from the permissions catalogue, so every grant below is unreachable and every gate reads denied with no message';
  end if;
  if v_category <> 'Inventory' then
    raise exception 'inventory.create is filed under %, not Inventory, so it renders as a section of its own in the dev matrix', v_category;
  end if;
  if v_order <> 25 then
    raise exception 'inventory.create sorts at %, not 25, so it no longer reads immediately before inventory.edit', v_order;
  end if;
  if not v_gated then
    raise exception 'inventory.create is not plan-gated, so its plan rows are inert and a starter tenant would gain it';
  end if;
  if v_feature is not null then
    raise exception 'inventory.create is tied to the % feature module; adding stock is not an optional module', v_feature;
  end if;

  -- ── CONTROL: the one role this split exists for, named rather than counted ─
  if not exists (select 1 from public.role_permissions
                  where role_id = 'accounting_admin'
                    and permission_id = 'inventory.create' and granted) then
    raise exception 'accounting_admin does not hold inventory.create, which is the one role this split exists for';
  end if;

  -- ── ASSERTION THAT MUST NOT FIRE: it stays off the floor ─────────────────
  -- 🔴 A KEY AND ITS POLICY MUST ADMIT THE SAME ROLES, and both directions fail
  -- silently. A create-only key is still a WRITE, and nobody who cannot add
  -- inventory today should gain it from a split whose purpose is to take access
  -- AWAY. The insert above excludes these five, so a row here was written by
  -- something else -- the dev portal, or a hand-edit of this file.
  select string_agg(role_id, ', ' order by role_id) into v_roles
    from public.role_permissions
   where permission_id = 'inventory.create' and granted
     and role_id in ('assistant_roaster','staff','sales_person',
                     'accounting_view','equipment_tech');
  if v_roles is not null then
    raise exception 'inventory.create is granted to %, which cannot add inventory today; the insert above excludes those roles, so that row came from somewhere else', v_roles;
  end if;

  -- ── The plan leg ─────────────────────────────────────────────────────────
  -- Coverage against the plans table rather than a hardcoded 4, because a
  -- plan-gated key with a missing plan row is denied in silence.
  select count(*) into v_plans
    from public.plan_permissions where permission_id = 'inventory.create';
  if v_plans <> (select count(*) from public.subscription_plans) then
    raise exception 'inventory.create covers % plan(s), not every plan there is, and a plan-gated key with a missing plan row is denied in silence', v_plans;
  end if;

  -- Checked plan for plan against the key it splits rather than against this
  -- file's own four booleans, so the two cannot drift apart later.
  select count(*) into v_mismatch
    from public.plan_permissions c
    join public.plan_permissions e on e.plan_id = c.plan_id
   where c.permission_id = 'inventory.create'
     and e.permission_id = 'inventory.edit'
     and c.granted is distinct from e.granted;
  if v_mismatch > 0 then
    raise exception 'inventory.create and inventory.edit disagree on % plan(s); splitting a key must not move which plans may add stock', v_mismatch;
  end if;

  -- CONTROLS THAT MUST PASS, stated as values as well as a comparison: the
  -- mirror above would also be satisfied if BOTH keys were wrong the same way.
  if not exists (select 1 from public.plan_permissions
                  where permission_id = 'inventory.create'
                    and plan_id = 'enterprise_plus' and granted) then
    raise exception 'inventory.create is denied on enterprise_plus, the plan every live tenant is on, so the two add buttons would stay hidden';
  end if;
  if exists (select 1 from public.plan_permissions
              where permission_id = 'inventory.create'
                and plan_id = 'starter' and granted) then
    raise exception 'inventory.create is granted on starter, which hands a starter tenant an inventory capability it does not have today';
  end if;

  -- ── NOTICES, NOT ASSERTIONS ──────────────────────────────────────────────
  -- Premise drift is something a human should read in the CI log. It is not a
  -- reason to abort a release tag that carries eight other migrations, and
  -- role_permissions is editable outside migrations through the dev portal --
  -- which is how the live grant this file replaces was made.
  select string_agg(t.role_id, ', ' order by t.role_id) into v_roles
    from unnest(array['accounting_admin','company_admin','facility_admin',
                      'manager','roastery_manager','roastmaster']) as t(role_id)
   where not exists (select 1 from public.role_permissions rp
                      where rp.role_id = t.role_id
                        and rp.permission_id = 'inventory.edit' and rp.granted);
  if v_roles is not null then
    raise notice 'inventory.edit is no longer held by %, though it was on 2026-11-19. Nothing was widened -- the insert reads the live grants -- but the premise this file mirrors has changed and someone should look.', v_roles;
  end if;

  select string_agg(rp.role_id, ', ' order by rp.role_id) into v_roles
    from public.role_permissions rp
   where rp.permission_id = 'inventory.edit' and rp.granted
     and rp.role_id <> all (array['accounting_admin','company_admin','facility_admin',
                                  'manager','roastery_manager','roastmaster'])
  ;
  if v_roles is not null then
    raise notice 'inventory.edit has since been granted to %, so inventory.create went to that role too. Correct if that grant was.', v_roles;
  end if;

  -- NOT an assertion, deliberately. If the stopgap has already come off, this
  -- file is the only thing restoring the two add buttons, and raising here
  -- would roll the fix back along with every other migration in the tag.
  if not exists (select 1 from public.role_permissions
                  where role_id = 'accounting_admin'
                    and permission_id = 'inventory.edit' and granted) then
    raise notice 'accounting_admin no longer holds inventory.edit, so inventory.create is now the only key behind the two add buttons: the frontend that names it must already be live in production.';
  end if;
end $$;

commit;
