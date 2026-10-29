-- Creating a product or a customer checks a permission.
--
-- `products`, `product_groups` and `customers` each had ONE write policy:
-- `tenant_company_access`, cmd=ALL, scoped to the tenant and checking no
-- permission at all. So any role with a session could create a product or a
-- customer. They are the three highest-blast-radius tables on the ungated list.
--
-- 🔴 THIS GATES **INSERT ONLY**, AND THAT IS THE WHOLE POINT OF THE MIGRATION.
--
-- The obvious change was INSERT on `.create` and UPDATE on `.edit`, and the role
-- algebra said it was free: measured on prod, no role holds `create`, `archive`,
-- `merge` or `chain_manage` without also holding `edit`.
--
-- **The role algebra is the wrong model, and an adversarial pass caught it
-- before any of this was written.** These tables are also written by SECURITY
-- INVOKER cascade functions, which run as `authenticated` and ARE matched
-- against RLS. Measured, not relayed:
--
--   proname                          | prosecdef | owner    | writes
--   update_customer_metrics_on_order | f         | postgres | customers
--   propagate_coffee_cost_change     | f         | postgres | products
--   product_group_type_cascade       | f         | postgres | products
--
-- 🔴 Breaker 1. `staff` holds `order.pack` and `delivery.mark_delivered` and has
-- NO `customer.edit` grant row. Marking an order packed, shipped or delivered
-- updates `orders`, which fires `trigger_refresh_customer_stats` ->
-- `update_customer_metrics_on_order()` as `authenticated` -> `UPDATE customers`.
-- Under a `customer.edit` gate that matches ZERO ROWS. `last_order_date`,
-- `days_since_last_order` and the cadence columns silently stop advancing, the
-- reminder cron then re-nags customers who have just ordered, and the 03:00
-- `recompute_customer_cadence_daily` job half-repairs it overnight -- so the
-- symptom disappears every morning and reads as reporting lag, not a refusal.
-- Worse at the MCR terminal, where the session is an INTERSECTION: metrics
-- refresh when a roastmaster is PIN'd in and not when a staff member is.
-- Identical hardware, identical button, different person.
--
-- 🔴 Breaker 2. `assistant_roaster` holds `inventory.count` and
-- `inventory.receive` and NO `product.edit`. A floor count runs
-- `record_per_lot_count` -> `coffee_lot_count_recompute` ->
-- `recompute_origin_lot_consumption` -> `_recompute_origin_lot_consumption_core`
-- -> `recalculate_inventory_cost` -> `propagate_coffee_cost_change` ->
-- `UPDATE products`. **Every function in that chain is prosecdef=f.** Under a
-- `product.edit` gate, product COGS silently stops updating.
--
-- 🔴 The lesson, and the reason the comment is this long: **a permission gate on
-- a TABLE is not a gate on a user ACTION.** It is a gate on everything that
-- reaches the table, and a derived-data cascade reaches it carrying the
-- permissions of whoever triggered the ORIGINATING action -- which are the
-- permissions for that action, not for this table. `relforcerowsecurity` is
-- false on all 211 public tables, which exempts the SECURITY DEFINER functions
-- and does nothing for the INVOKER ones, and the definer/invoker split is
-- invisible from the policy, the table and the app.
--
-- So UPDATE keeps exactly today's rule -- tenant-scoped, no permission check --
-- and says so out loud below rather than looking like an oversight. Gating it
-- needs the cascades converted to SECURITY DEFINER owned by `postgres` first
-- (they maintain derived columns; they are plumbing, not user intent). That is
-- its own batch, with its own `search_path` care, and it is on the open list.
--
-- ── Why INSERT is safe, checked one key at a time ────────────────────────
--
-- No SECURITY INVOKER function inserts into `customers` at all, and exactly one
-- inserts into `products`/`product_groups`: `apply_late_fee`, which mints the
-- late-fee product. So the INSERT paths are the application's own, and every one
-- of them already checks a key whose grant set is CONTAINED in the gate key's.
-- Verified by asking for the counter-example rather than eyeballing lists --
-- "which roles hold the writer key but NOT the gate key" -- and every answer was
-- empty:
--
--   ar.late_fee_apply  -> product.create    NONE
--   config.import_data -> product.create    NONE   (staged QuickBooks import)
--   config.import_data -> customer.create   NONE
--   config.shopify     -> customer.create   NONE   (Shopify order import)
--
-- The checkout and the Shopify webhook also insert customers, both on
-- `createAdminClient()` with no session to run as, so RLS does not apply to
-- them and no key is involved.
--
-- Both gate keys are `is_plan_gated = false` with `feature_key = null`, so no
-- plan or module toggle can withdraw the ability to create a product or a
-- customer. A plan-gated gate key would have been a trap: starter tenants would
-- lose the write entirely.
--
-- ── DELETE ───────────────────────────────────────────────────────────────
--
-- No DELETE policy is created. 20261028000017 revoked the DELETE privilege from
-- `authenticated` on these three tables, so delete is already impossible, and
-- RLS with no DELETE policy denies it too. Both doors shut, which is the right
-- direction: restoring delete would have to be deliberate on both.

begin;

-- ── products ────────────────────────────────────────────────────────────
drop policy if exists tenant_company_access on public.products;

create policy products_read on public.products
  for select to authenticated
  using (company_id in (select auth_company_ids()));

create policy products_insert on public.products
  for insert to authenticated
  with check (company_id in (select auth_company_ids())
              and auth_has_permission('product.create', company_id));

-- Deliberately NOT gated: propagate_coffee_cost_change() and
-- product_group_type_cascade() are SECURITY INVOKER and update this table from
-- inside an inventory or product-type write. See the header.
create policy products_update on public.products
  for update to authenticated
  using (company_id in (select auth_company_ids()))
  with check (company_id in (select auth_company_ids()));

-- ── product_groups ──────────────────────────────────────────────────────
drop policy if exists tenant_company_access on public.product_groups;

create policy product_groups_read on public.product_groups
  for select to authenticated
  using (company_id in (select auth_company_ids()));

create policy product_groups_insert on public.product_groups
  for insert to authenticated
  with check (company_id in (select auth_company_ids())
              and auth_has_permission('product.create', company_id));

create policy product_groups_update on public.product_groups
  for update to authenticated
  using (company_id in (select auth_company_ids()))
  with check (company_id in (select auth_company_ids()));

-- ── customers ───────────────────────────────────────────────────────────
-- `shop_buyer_self_customer` (SELECT, scoped by auth_customer_ids()) is NOT
-- touched: it is how a shop buyer reads their own customer record, it is
-- permissive and therefore OR-ed with the tenant read, and only
-- `tenant_company_access` is dropped by name.
drop policy if exists tenant_company_access on public.customers;

create policy customers_read on public.customers
  for select to authenticated
  using (company_id in (select auth_company_ids()));

create policy customers_insert on public.customers
  for insert to authenticated
  with check (company_id in (select auth_company_ids())
              and auth_has_permission('customer.create', company_id));

-- Deliberately NOT gated: update_customer_metrics_on_order() is SECURITY
-- INVOKER and updates this table from inside every orders write. See the header.
create policy customers_update on public.customers
  for update to authenticated
  using (company_id in (select auth_company_ids()))
  with check (company_id in (select auth_company_ids()));

do $$
declare t text; n int; wc text; extra int;
begin
  foreach t in array array['products','product_groups','customers'] loop
    -- the ungated ALL policy is gone
    select count(*) into n from pg_policies
     where schemaname='public' and tablename=t and policyname='tenant_company_access';
    if n <> 0 then raise exception 'tenant_company_access still exists on %', t; end if;

    -- exactly one INSERT policy, and it checks a permission
    select count(*), coalesce(max(with_check),'') into n, wc from pg_policies
     where schemaname='public' and tablename=t and cmd='INSERT';
    if n <> 1 then raise exception '% has % INSERT policies, expected 1', t, n; end if;
    if wc not like '%auth_has_permission%' then
      raise exception 'the INSERT policy on % does not check a permission: %', t, wc;
    end if;
    if wc not like '%auth_company_ids%' then
      raise exception 'the INSERT policy on % lost its tenant scope: %', t, wc;
    end if;

    -- 🔴 reads must stay open to the tenant. gating a read here would take the
    -- product list away from every role that cannot create a product, which is
    -- a worse outage than the thing being fixed.
    select count(*) into n from pg_policies
     where schemaname='public' and tablename=t and cmd='SELECT'
       and coalesce(qual,'') like '%auth_company_ids%'
       and coalesce(qual,'') not like '%auth_has_permission%';
    if n < 1 then raise exception 'no ungated tenant SELECT policy left on %', t; end if;

    -- UPDATE still works and is still tenant-scoped
    select count(*) into n from pg_policies
     where schemaname='public' and tablename=t and cmd='UPDATE'
       and coalesce(qual,'') like '%auth_company_ids%'
       and coalesce(with_check,'') like '%auth_company_ids%';
    if n <> 1 then raise exception '% has no tenant-scoped UPDATE policy', t; end if;

    -- and DELETE stays shut: no policy, and 20261028000017 took the privilege
    select count(*) into n from pg_policies
     where schemaname='public' and tablename=t and cmd='DELETE';
    if n <> 0 then raise exception '% grew a DELETE policy', t; end if;
  end loop;

  -- the shop buyer's own-record read survived
  select count(*) into extra from pg_policies
   where schemaname='public' and tablename='customers' and policyname='shop_buyer_self_customer';
  raise notice 'shop_buyer_self_customer policies on customers: % (1 expected)', extra;

  raise notice 'creating a product or a customer now checks a permission; reads and updates unchanged';
end $$;

commit;
