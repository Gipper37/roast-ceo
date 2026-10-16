-- Moving a product in or out of a RESERVED collection needs shop permission.
--
-- `20261015000003` gave `product_group_collection` a tenancy policy and no
-- permission check:
--
--   for all to authenticated
--   using      (company_id in (select auth_company_ids()))
--   with check (company_id in (select auth_company_ids()))
--
-- That matches the posture of most of this schema (see project_m11_phase2: 124
-- ungated write tables), so the PATTERN is not new. What is new is that this
-- table now gates VISIBILITY: `20261015000006` put the three allowlists on
-- `collection`, and the storefront's ALL-allow rule means a product's
-- membership of a reserved collection decides who may see and buy it.
--
-- So the severity changed even though the pattern did not. Measured on prod:
--
--   product.edit           6 roles: company_admin, facility_admin, manager,
--                          roastery_manager, roastmaster, accounting_admin
--   shop.products_publish  3 roles: company_admin, facility_admin, manager
--
-- Three roles hold the first and not the second. Through the collection bulk
-- bar, or through PostgREST directly, any of them could DELETE a membership
-- row and publish a private label to every buyer -- an un-reservation they are
-- not allowed to perform on the product itself.
--
-- 🔴 ONLY WHEN THE COLLECTION IS ACTUALLY RESERVED. Filing a coffee on the
-- Decaf shelf is ordinary catalogue work and stays on `product.edit`.
-- Requiring the shop permission for every shelf change would stop a
-- roastmaster doing their job over a rule about somebody else's collection,
-- which is the kind of restriction whose main benefit is that an edge case
-- disappears.
--
-- 🔴 AND THE KEY AND THE POLICY MUST ADMIT THE SAME ROLES, in both directions,
-- because both failures are silent: a policy stricter than the UI means the
-- bulk bar reports success over zero rows, and a UI stricter than the policy
-- means the check is decoration. `setProductsCollection` makes the same test
-- and answers in a sentence naming the collection; this is the enforcement
-- behind it, because a server action is reachable without the form.
--
-- No new permission key: `shop.products_publish` already exists, is granted in
-- role_permissions and plan_permissions, and is what the per-product
-- visibility controls already use. A new key would need its own rows and would
-- be denied silently until they landed.

begin;

-- One definition of "this collection restricts who can buy", so the policy and
-- anything else that asks cannot drift apart.
create or replace function public.collection_is_reserved(p_collection_id text)
returns boolean
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
  select exists (
    select 1
      from public.collection c
     where c.id = p_collection_id
       and (coalesce(array_length(c.exclusive_to_customer_ids, 1), 0) > 0
         or coalesce(array_length(c.exclusive_to_chain_ids, 1), 0) > 0
         or coalesce(array_length(c.excluded_from_customer_ids, 1), 0) > 0)
  )
$$;

comment on function public.collection_is_reserved(text) is
  'TRUE when a collection carries any of the three allowlists, i.e. when its membership decides who may buy. The one definition, used by product_group_collection''s write policies.';

-- SECURITY DEFINER and it reads `collection`, so it must not be callable by
-- the browser on its own: it would answer about another tenant's collection.
-- The policies below invoke it as the table owner.
revoke all on function public.collection_is_reserved(text) from public;

-- ── The policies ──────────────────────────────────────────────────────────
--
-- Split from one FOR ALL into four, because the four verbs need different
-- things said about them:
--   SELECT  tenancy only. Reading what is on a shelf is not a privilege, and
--           every catalogue surface does it.
--   INSERT  tenancy + product.edit, and shop permission when reserved.
--   UPDATE  the same, on both sides of the change.
--   DELETE  the same. This is the verb the finding was about.
-- 🔴 EVERY ONE DROPPED FIRST, not just the old blanket policy.
-- `create policy` has no IF NOT EXISTS, and prod applies each migration once
-- while CI applies the WHOLE pending set to staging -- which may already hold
-- these. The first draft dropped only `..._tenant` and ERRORED on a second
-- application with "policy product_group_collection_read already exists". A
-- migration that cannot be re-applied cannot be rehearsed either, and that is
-- how it was found: the attempt to restore this file after a sabotage failed,
-- which silently left the sabotage in place and made the NEXT check report the
-- previous one's error.
drop policy if exists product_group_collection_tenant on public.product_group_collection;
drop policy if exists product_group_collection_read   on public.product_group_collection;
drop policy if exists product_group_collection_insert on public.product_group_collection;
drop policy if exists product_group_collection_update on public.product_group_collection;
drop policy if exists product_group_collection_delete on public.product_group_collection;

create policy product_group_collection_read on public.product_group_collection
  for select to authenticated
  using (company_id in (select auth_company_ids()));

create policy product_group_collection_insert on public.product_group_collection
  for insert to authenticated
  with check (
    company_id in (select auth_company_ids())
    and public.auth_has_permission('product.edit', company_id)
    and (
      not public.collection_is_reserved(collection_id)
      or public.auth_has_permission('shop.products_publish', company_id)
    )
  );

create policy product_group_collection_update on public.product_group_collection
  for update to authenticated
  using (
    company_id in (select auth_company_ids())
    and public.auth_has_permission('product.edit', company_id)
    and (
      not public.collection_is_reserved(collection_id)
      or public.auth_has_permission('shop.products_publish', company_id)
    )
  )
  with check (
    company_id in (select auth_company_ids())
    and public.auth_has_permission('product.edit', company_id)
    and (
      not public.collection_is_reserved(collection_id)
      or public.auth_has_permission('shop.products_publish', company_id)
    )
  );

create policy product_group_collection_delete on public.product_group_collection
  for delete to authenticated
  using (
    company_id in (select auth_company_ids())
    and public.auth_has_permission('product.edit', company_id)
    and (
      not public.collection_is_reserved(collection_id)
      or public.auth_has_permission('shop.products_publish', company_id)
    )
  );

do $verify$
DECLARE
  v_policies int;
  v_reserved boolean;
  v_plain    boolean;
  v_coll     text;
  v_company  text;
BEGIN
  -- Four policies, and the old blanket one gone.
  select count(*) into v_policies
    from pg_policies
   where schemaname = 'public' and tablename = 'product_group_collection';
  if v_policies <> 4 then
    raise exception 'expected 4 policies on product_group_collection, found %', v_policies;
  end if;
  if exists (select 1 from pg_policies
              where schemaname = 'public' and tablename = 'product_group_collection'
                and policyname = 'product_group_collection_tenant') then
    raise exception 'the old blanket FOR ALL policy is still there';
  end if;
  -- SELECT must NOT carry a permission check: reading a shelf is not a
  -- privilege, and gating it would empty every catalogue surface.
  if exists (select 1 from pg_policies
              where schemaname = 'public' and tablename = 'product_group_collection'
                and cmd = 'SELECT' and qual like '%auth_has_permission%') then
    raise exception 'the read policy gained a permission check; that empties the catalogue';
  end if;
  -- And each write verb must carry BOTH checks.
  if (select count(*) from pg_policies
       where schemaname = 'public' and tablename = 'product_group_collection'
         and cmd in ('INSERT','UPDATE','DELETE')
         and coalesce(qual, '') || coalesce(with_check, '') like '%shop.products_publish%') <> 3 then
    raise exception 'a write verb is missing the shop.products_publish condition';
  end if;

  -- 🔴 The predicate itself, against real rows rather than asserted. A
  -- verify block that only counted policies would pass with the condition
  -- inverted.
  select c.id, c.company_id into v_coll, v_company
    from public.collection c
   where coalesce(array_length(c.exclusive_to_customer_ids, 1), 0) > 0
      or coalesce(array_length(c.exclusive_to_chain_ids, 1), 0) > 0
      or coalesce(array_length(c.excluded_from_customer_ids, 1), 0) > 0
   limit 1;

  if v_coll is null then
    -- None reserved yet on this database, which is the ordinary state today.
    -- Build one, test both answers, and remove it.
    select company_id into v_company from public.collection limit 1;
    if v_company is null then
      raise notice 'no collections here, skipping the predicate check';
    else
      insert into public.collection (id, name, company_id, is_active, exclusive_to_customer_ids)
      values ('zzverify-reserved', 'zzverify reserved', v_company, true, array['zzverify-cust'])
      returning id into v_coll;
      insert into public.collection (id, name, company_id, is_active)
      values ('zzverify-plain', 'zzverify plain', v_company, true);

      v_reserved := public.collection_is_reserved('zzverify-reserved');
      v_plain    := public.collection_is_reserved('zzverify-plain');
      if not v_reserved then raise exception 'a collection with an allowlist read as unreserved'; end if;
      if v_plain      then raise exception 'a collection with no allowlist read as reserved'; end if;

      delete from public.collection where id in ('zzverify-reserved','zzverify-plain');
    end if;
  else
    if not public.collection_is_reserved(v_coll) then
      raise exception 'collection % carries an allowlist but read as unreserved', v_coll;
    end if;
    -- An unreserved one must answer false, or the condition is a tautology and
    -- every shelf change would need the shop permission.
    if exists (select 1 from public.collection c
                where coalesce(array_length(c.exclusive_to_customer_ids, 1), 0) = 0
                  and coalesce(array_length(c.exclusive_to_chain_ids, 1), 0) = 0
                  and coalesce(array_length(c.excluded_from_customer_ids, 1), 0) = 0
                  and public.collection_is_reserved(c.id)) then
      raise exception 'an unreserved collection read as reserved; the condition is a tautology';
    end if;
  end if;

  -- A collection id that does not exist must be FALSE, not null: a membership
  -- row pointing at a deleted collection must stay editable by product.edit.
  if public.collection_is_reserved('zzverify-no-such-collection') is not false then
    raise exception 'an unknown collection did not answer false';
  end if;

  raise notice 'reserved collections now need shop.products_publish to change what is in them';
END;
$verify$;

commit;
