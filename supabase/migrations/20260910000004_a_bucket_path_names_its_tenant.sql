-- A bucket path names its tenant, and the policy reads the name.
--
-- Every storage policy the app relies on scoped by bucket_id alone:
--
--   invoices         SELECT/INSERT/UPDATE to authenticated   bucket_id = 'invoices'
--   shop-assets      INSERT/UPDATE to authenticated          bucket_id = 'shop-assets'
--   Generic Pics     INSERT/UPDATE/DELETE to authenticated   bucket_id = 'Generic Pics'
--   delivery-photos  INSERT/UPDATE to authenticated          bucket_id = 'delivery-photos'
--
-- So any authenticated session — a team member of another roastery, a wholesale
-- buyer with a storefront login, the shared demo account — could list and
-- download the 8 supplier invoices Social Hour UK uploaded (their green prices,
-- per kg, from Falcon Coffees), overwrite Maui Coffee Roasters' storefront logo,
-- delete Social Hour's product photography, or write into any order's delivery
-- photo folder. 20260729000003 wrote the limitation down and deferred it.
--
-- The objects already carry the ownership in their names:
--
--   invoices         <company_id>/<facility_id>/<ts>.<ext>
--   shop-assets      <company_id>/logo.png
--   Generic Pics     product-groups/<group_id>.<ext>      (group → company)
--   delivery-photos  <order_id>/<ts>.<ext>                (order → company)
--
-- so no object moves and no stored URL changes. Where the first path segment
-- is the company, the policy compares it with auth_company_ids(); where it is a
-- row id, the policy resolves that row — as the caller, under that table's own
-- RLS, so another tenant's group or order is simply not there.
--
-- Public READ stays public on the three public buckets: those images are on
-- storefronts and receipts by design. The invoices bucket is private and its
-- SELECT is scoped too — that is the one that leaked data rather than defacement.
--
-- Staging has no buckets and only the Generic Pics policies; every drop is
-- `if exists` and a policy is happy to name a bucket that does not exist yet.

begin;

-- ── invoices (private): read, write and remove your own company's only ────
drop policy if exists "Authenticated users can read invoices"   on storage.objects;
drop policy if exists "Authenticated users can upload invoices" on storage.objects;
drop policy if exists "Authenticated users can update invoices" on storage.objects;
drop policy if exists invoices_own_company_read   on storage.objects;
drop policy if exists invoices_own_company_insert on storage.objects;
drop policy if exists invoices_own_company_update on storage.objects;
drop policy if exists invoices_own_company_delete on storage.objects;

create policy invoices_own_company_read on storage.objects
  for select to authenticated
  using (bucket_id = 'invoices'
         and (storage.foldername(name))[1] in (select public.auth_company_ids()));

create policy invoices_own_company_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'invoices'
              and (storage.foldername(name))[1] in (select public.auth_company_ids()));

create policy invoices_own_company_update on storage.objects
  for update to authenticated
  using      (bucket_id = 'invoices'
              and (storage.foldername(name))[1] in (select public.auth_company_ids()))
  with check (bucket_id = 'invoices'
              and (storage.foldername(name))[1] in (select public.auth_company_ids()));

create policy invoices_own_company_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'invoices'
         and (storage.foldername(name))[1] in (select public.auth_company_ids()));

-- ── shop-assets (public bucket): anyone reads, only the owner writes ──────
drop policy if exists shop_assets_auth_upload on storage.objects;
drop policy if exists shop_assets_auth_update on storage.objects;
drop policy if exists shop_assets_own_company_insert on storage.objects;
drop policy if exists shop_assets_own_company_update on storage.objects;
drop policy if exists shop_assets_own_company_delete on storage.objects;

create policy shop_assets_own_company_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'shop-assets'
              and (storage.foldername(name))[1] in (select public.auth_company_ids()));

create policy shop_assets_own_company_update on storage.objects
  for update to authenticated
  using      (bucket_id = 'shop-assets'
              and (storage.foldername(name))[1] in (select public.auth_company_ids()))
  with check (bucket_id = 'shop-assets'
              and (storage.foldername(name))[1] in (select public.auth_company_ids()));

create policy shop_assets_own_company_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'shop-assets'
         and (storage.foldername(name))[1] in (select public.auth_company_ids()));

-- ── Generic Pics (public bucket): the group in the filename must be yours ─
-- product_groups carries RLS, so the subquery only ever finds the caller's own
-- groups; the explicit company test is belt and braces for BYPASSRLS callers.
-- Objects outside product-groups/ (a few legacy marketing images) have no owner
-- and are therefore not writable from the app at all — only by the service role.
drop policy if exists generic_pics_auth_upload on storage.objects;
drop policy if exists generic_pics_auth_update on storage.objects;
drop policy if exists generic_pics_auth_delete on storage.objects;
drop policy if exists generic_pics_own_product_insert on storage.objects;
drop policy if exists generic_pics_own_product_update on storage.objects;
drop policy if exists generic_pics_own_product_delete on storage.objects;

create policy generic_pics_own_product_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'Generic Pics'
    and (storage.foldername(name))[1] = 'product-groups'
    and exists (
      select 1 from public.product_groups g
       where g.group_id::text = regexp_replace(storage.filename(name), '\.[^.]*$', '')
         and g.company_id in (select public.auth_company_ids())
    )
  );

create policy generic_pics_own_product_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'Generic Pics'
    and (storage.foldername(name))[1] = 'product-groups'
    and exists (
      select 1 from public.product_groups g
       where g.group_id::text = regexp_replace(storage.filename(name), '\.[^.]*$', '')
         and g.company_id in (select public.auth_company_ids())
    )
  )
  with check (
    bucket_id = 'Generic Pics'
    and (storage.foldername(name))[1] = 'product-groups'
    and exists (
      select 1 from public.product_groups g
       where g.group_id::text = regexp_replace(storage.filename(name), '\.[^.]*$', '')
         and g.company_id in (select public.auth_company_ids())
    )
  );

create policy generic_pics_own_product_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'Generic Pics'
    and (storage.foldername(name))[1] = 'product-groups'
    and exists (
      select 1 from public.product_groups g
       where g.group_id::text = regexp_replace(storage.filename(name), '\.[^.]*$', '')
         and g.company_id in (select public.auth_company_ids())
    )
  );

-- ── delivery-photos (public bucket): the order in the path must be yours ──
drop policy if exists "Authenticated users can upload delivery photos" on storage.objects;
drop policy if exists "Authenticated users can update delivery photos" on storage.objects;
drop policy if exists delivery_photos_own_order_insert on storage.objects;
drop policy if exists delivery_photos_own_order_update on storage.objects;
drop policy if exists delivery_photos_own_order_delete on storage.objects;

create policy delivery_photos_own_order_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'delivery-photos'
    and exists (
      select 1 from public.orders o
       where o.order_id = (storage.foldername(name))[1]
         and o.company_id in (select public.auth_company_ids())
    )
  );

create policy delivery_photos_own_order_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'delivery-photos'
    and exists (
      select 1 from public.orders o
       where o.order_id = (storage.foldername(name))[1]
         and o.company_id in (select public.auth_company_ids())
    )
  )
  with check (
    bucket_id = 'delivery-photos'
    and exists (
      select 1 from public.orders o
       where o.order_id = (storage.foldername(name))[1]
         and o.company_id in (select public.auth_company_ids())
    )
  );

create policy delivery_photos_own_order_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'delivery-photos'
    and exists (
      select 1 from public.orders o
       where o.order_id = (storage.foldername(name))[1]
         and o.company_id in (select public.auth_company_ids())
    )
  );

commit;
