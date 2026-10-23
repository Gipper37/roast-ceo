-- A product can carry its label artwork.
--
-- Owner, 2026-10-22, after a day of running the roastery on STRATA:
-- *"Where's the custom 4 x 6 Labels in strata. went to labels and only found
-- upc. also need to upload all labels to attach to each product."*
--
-- He added 28 PDFs to ~/my-supabase-project/MCR/5# Labels/. Measured, every
-- one is exactly 4.00 x 6.00in: they are the printed BAG labels, one per
-- coffee, plus a `Generic Label 5#.pdf` for anything without its own.
--
-- ── IT BELONGS TO THE VARIANT, NOT THE PRODUCT ────────────────────────────
--
-- A 5lb bag label and a 12oz bag label are different pieces of artwork for the
-- same coffee, so the artwork hangs off `products` (the VARIANT) exactly as
-- `gtin` does, not off `product_groups`. The folder's one exception proves it:
-- `Maui Blend 2#.pdf` sits beside 27 five-pounders.
--
-- One per variant, so `product_id` is the primary key. Replacing a label is an
-- upsert, which is what a roastery redesigning a bag actually does.
--
-- ── THE BUCKET IS PRIVATE ─────────────────────────────────────────────────
--
-- Unlike `Generic Pics`, which is public because those photos are on a
-- storefront. This is print-ready brand artwork; it is served through a signed
-- URL to somebody who is already signed in. The policies follow the shape
-- 20260910000004 established for `invoices`: the first path segment IS the
-- company, and the policy compares it with auth_company_ids(), so no object
-- can be read, replaced or removed across tenants.
--
--   product-labels/<company_id>/<product_id>.pdf

begin;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('product-labels', 'product-labels', false, 26214400, array['application/pdf'])
on conflict (id) do update set
  public             = excluded.public,
  file_size_limit    = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists product_labels_own_company_read   on storage.objects;
drop policy if exists product_labels_own_company_insert on storage.objects;
drop policy if exists product_labels_own_company_update on storage.objects;
drop policy if exists product_labels_own_company_delete on storage.objects;

create policy product_labels_own_company_read on storage.objects
  for select to authenticated
  using (bucket_id = 'product-labels'
         and (storage.foldername(name))[1] in (select public.auth_company_ids()));

create policy product_labels_own_company_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'product-labels'
              and (storage.foldername(name))[1] in (select public.auth_company_ids()));

create policy product_labels_own_company_update on storage.objects
  for update to authenticated
  using      (bucket_id = 'product-labels'
              and (storage.foldername(name))[1] in (select public.auth_company_ids()))
  with check (bucket_id = 'product-labels'
              and (storage.foldername(name))[1] in (select public.auth_company_ids()));

create policy product_labels_own_company_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'product-labels'
         and (storage.foldername(name))[1] in (select public.auth_company_ids()));

-- ── The row that says a variant has one ───────────────────────────────────

create table if not exists public.product_label (
  product_id    text        primary key references public.products(product_id) on delete cascade,
  company_id    text        not null references public.companies(company_id) on delete cascade,
  storage_path  text        not null,
  -- What the roastery called the file. Printed in the picker, because "Organic
  -- Hapa.pdf" is how they will look for it and the variant name is not.
  file_name     text        not null,
  -- Measured from the PDF on upload rather than assumed. These 28 are 4x6, but
  -- a roastery with a different bag is not wrong, and a printer needs the real
  -- page size.
  width_mm      numeric(6,2),
  height_mm     numeric(6,2),
  uploaded_at   timestamptz not null default now(),
  uploaded_by   text
);

comment on table public.product_label is
  'The printed bag label for a VARIANT, as uploaded artwork. One per variant; the bytes live in the private product-labels bucket at <company_id>/<product_id>.pdf.';

alter table public.product_label enable row level security;

-- Read is tenant scope: anybody who can see the catalogue can see that a bag
-- has artwork, and the print screens need it. Writing is product.edit, the
-- same key that edits the variant's barcode, because this is product data.
drop policy if exists product_label_read on public.product_label;
create policy product_label_read on public.product_label
  for select
  using (company_id in (select auth_company_ids()));

drop policy if exists product_label_write on public.product_label;
create policy product_label_write on public.product_label
  for all
  using      (company_id in (select auth_company_ids()) and auth_has_permission('product.edit', company_id))
  with check (company_id in (select auth_company_ids()) and auth_has_permission('product.edit', company_id));

grant select, insert, update, delete on public.product_label to authenticated;

create index if not exists product_label_company_idx on public.product_label (company_id);

-- 🔴 Asserts only what this file wrote. No existing key is invented here:
-- product.edit already exists and already means "change this variant", so
-- there is no new permission to register and nothing is denied silently.
do $$
begin
  if not exists (select 1 from storage.buckets where id = 'product-labels') then
    raise exception 'the product-labels bucket was not created';
  end if;
  if (select public from storage.buckets where id = 'product-labels') then
    raise exception 'the product-labels bucket is PUBLIC; label artwork must be signed';
  end if;
  if (select count(*) from pg_policies
       where schemaname = 'storage' and tablename = 'objects'
         and policyname like 'product_labels_own_company_%') <> 4 then
    raise exception 'product-labels is missing storage policies: it must have read, insert, update and delete';
  end if;
  if not exists (
    select 1 from pg_policies
     where tablename = 'product_label' and policyname = 'product_label_write'
  ) then
    raise exception 'product_label has no write policy, so product.edit is not a fence on it';
  end if;
end $$;

commit;
