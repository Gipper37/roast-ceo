-- Product image upload has been broken for every tenant since 2026-05-16.
--
-- Reported by SHUSA's admin: adding a picture to a product returns
-- "new row violates row-level security policy".
--
-- The `Generic Pics` bucket has NO policies on storage.objects — not SELECT, not
-- INSERT, not UPDATE, not DELETE. Every other bucket the app writes to has them:
--
--   shop-assets      read + insert + update
--   invoices         read + insert + update
--   delivery-photos  read + insert + update
--   Generic Pics     (none)
--
-- It worked until commit ec3ad6e (2026-05-16, "RLS audit phases 2-4: split Supabase
-- client + convert 69 callers") switched uploadProductGroupImage from the
-- service-role client to createUserClient(). The service-role client bypasses RLS,
-- so the missing policies never mattered; the moment the call became
-- RLS-enforced, every upload started failing. Last successful upload: 2026-04-22.
--
-- SECOND, SILENT SYMPTOM: removeProductGroupImage also deletes with the user client,
-- inside a `catch` commented "Non-fatal — still clear the DB column even if storage
-- delete fails". So removing an image has been clearing product_groups.image and
-- ORPHANING the file. There is already one such orphan in the bucket
-- (product-groups/320c15a7-….png, referenced by no product_group). Hence a DELETE
-- policy here, not just INSERT.
--
-- Policies mirror shop-assets, the closest sibling: a public bucket of product
-- imagery, readable by anyone (the storefront needs it), writable by authenticated
-- users. Authorisation proper still lives in the server action, which requires
-- product.edit before it ever reaches storage.
--
-- ⚠️ KNOWN LIMITATION, deliberately not fixed here: the object path is
-- `product-groups/<group_id>.<ext>` with no company prefix, so an authenticated user
-- who knew another tenant's group_id could overwrite its image. That is equally true
-- of shop-assets today, and fixing it means changing the path scheme and migrating
-- the 18 existing objects — a separate change. This migration restores a broken
-- feature; it does not widen exposure beyond what shop-assets already has.

begin;

-- Public read: the bucket is already marked public, and the storefront renders these.
drop policy if exists generic_pics_public_read on storage.objects;
create policy generic_pics_public_read
  on storage.objects for select
  to public
  using (bucket_id = 'Generic Pics');

drop policy if exists generic_pics_auth_upload on storage.objects;
create policy generic_pics_auth_upload
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'Generic Pics');

-- upsert: true on the upload issues an UPDATE when the object already exists, which
-- is the normal case — the path is deterministic per group, so replacing an image
-- overwrites rather than inserts.
drop policy if exists generic_pics_auth_update on storage.objects;
create policy generic_pics_auth_update
  on storage.objects for update
  to authenticated
  using (bucket_id = 'Generic Pics');

-- Needed by removeProductGroupImage. Without it the delete fails silently and the
-- file is orphaned.
drop policy if exists generic_pics_auth_delete on storage.objects;
create policy generic_pics_auth_delete
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'Generic Pics');

commit;
