-- A roastery remembers which label stock it runs.
--
-- The label stock list was trapped inside the food-safety label screen and
-- its chosen size was stored in `fs_label_format`, keyed on company plus a
-- food-safety `kind` (combined / retail / lot / case). That table is the right
-- shape for that screen and the wrong shape for everything else: a UPC sticker
-- and a 6x4 packing label are not food-safety kinds, and widening a table
-- named `fs_` to carry them would make its name a lie.
--
-- So: one general table. `fs_label_format` is left exactly as it is, because
-- the food-safety label has field toggles and a case quantity that no other
-- label wants, and merging them would give every other label a dozen columns
-- it ignores.
--
-- ── WHAT A ROW IS ─────────────────────────────────────────────────────────
--
-- One per company per kind of label, holding only the thing that varies by
-- printer: the stock size. Everything else about a label is design, which
-- belongs in code and in the same place for every roastery.
--
--   upc      the barcode sticker, defaulting to 1.5in square
--   packing  the box label, 6x4 landscape
--
-- A missing row means the default in lib/labels/stocks.ts, so a roastery that
-- never opens the setting still prints, and the app never has to carry a
-- "what if there is no row" branch past the read.
--
-- ── THE KEY ───────────────────────────────────────────────────────────────
--
-- `label.configure`, new, because none of the existing keys mean this.
-- `pack.configure` is "choose how this roastery writes a lot code" and
-- `shop.configure` is the storefront. Picking the label stock is a
-- configuration job for whoever owns the printer, so it lands with the same
-- two roles that hold pack.configure.
--
-- 🔴 The key is not a fence until a policy names it, and the write policy
-- below is where it does. Read is open to the tenant: what size label the
-- shop prints on is not a secret from its own staff, and the print screens
-- need it to render a preview.

begin;

create table if not exists public.label_format (
  company_id  text        not null references public.companies(company_id) on delete cascade,
  -- Not an enum: a new kind of label is a code change, and an enum would make
  -- it a migration as well.
  kind        text        not null check (kind in ('upc', 'packing')),
  -- Millimetres, because that is what `@page size` takes and what the stock
  -- list is written in. Bounded so a typo cannot ask a printer for a 4-metre
  -- label: the smallest stock in the list is 12.7mm and the largest 152.4mm.
  width_mm    numeric(6,2) not null check (width_mm  between 10 and 400),
  height_mm   numeric(6,2) not null check (height_mm between 10 and 400),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  updated_by  text,
  primary key (company_id, kind)
);

comment on table public.label_format is
  'Per-roastery label stock size, one row per kind of label. A missing row means the default in lib/labels/stocks.ts.';

alter table public.label_format enable row level security;

-- Same shape as fs_label_format next door, deliberately: read scoped to the
-- tenant, write additionally gated on the permission key.
drop policy if exists label_format_read on public.label_format;
create policy label_format_read on public.label_format
  for select
  using (company_id in (select auth_company_ids()));

drop policy if exists label_format_write on public.label_format;
create policy label_format_write on public.label_format
  for all
  using      (company_id in (select auth_company_ids()) and auth_has_permission('label.configure', company_id))
  with check (company_id in (select auth_company_ids()) and auth_has_permission('label.configure', company_id));

grant select, insert, update, delete on public.label_format to authenticated;

-- ── The permission ─────────────────────────────────────────────────────────
-- do update, not do nothing: `do nothing` cannot correct a row already there
-- with different attributes, and the verify block would then abort the file on
-- exactly the attributes the insert refused to fix.
insert into public.permissions
  (permission_id, category, label, description, is_plan_gated, sort_order)
values
  ('label.configure', 'Configuration', 'Choose label stock',
   'Set the size of label this roastery prints on, for barcode stickers and packing labels. The design of each label is the same everywhere; this is the stock it is printed on, which depends on the printer.',
   true, 38)
on conflict (permission_id) do update set
  category      = excluded.category,
  label         = excluded.label,
  description   = excluded.description,
  is_plan_gated = excluded.is_plan_gated,
  sort_order    = excluded.sort_order,
  updated_at    = now();

-- The two roles that already hold pack.configure. Everyone else is explicit
-- false rather than absent: a missing row reads as denied, but a reviewer
-- cannot tell "decided no" from "forgotten" unless it is written down.
insert into public.role_permissions (role_id, permission_id, granted)
values
  ('company_admin',     'label.configure', true),
  ('facility_admin',    'label.configure', true),
  ('roastery_manager',  'label.configure', false),
  ('manager',           'label.configure', false),
  ('roastmaster',       'label.configure', false),
  ('assistant_roaster', 'label.configure', false),
  ('accounting_admin',  'label.configure', false),
  ('accounting_view',   'label.configure', false),
  ('equipment_tech',    'label.configure', false),
  ('sales_person',      'label.configure', false),
  ('staff',             'label.configure', false)
on conflict (role_id, permission_id) do update set
  granted = excluded.granted;

-- Plan-gated, and on every plan: printing a label is not a feature anybody
-- should have to upgrade for. It is gated at all so the column stays
-- meaningful if that ever changes.
insert into public.plan_permissions (plan_id, permission_id, granted, updated_reason)
values
  ('starter',         'label.configure', true, 'printing a label is not an upsell'),
  ('pro',             'label.configure', true, 'printing a label is not an upsell'),
  ('enterprise',      'label.configure', true, 'printing a label is not an upsell'),
  ('enterprise_plus', 'label.configure', true, 'printing a label is not an upsell')
on conflict (plan_id, permission_id) do update set
  granted        = excluded.granted,
  updated_reason = excluded.updated_reason,
  updated_at     = now();

-- 🔴 This block can only pass or raise on something that is genuinely wrong:
-- it asserts what this file just wrote, nothing about the wider design. A
-- verify block that asserts what the design forbids rolls back the whole
-- release, and two of mine have.
do $$
begin
  if not exists (select 1 from public.permissions where permission_id = 'label.configure') then
    raise exception 'label.configure was not created';
  end if;
  if (select count(*) from public.role_permissions where permission_id = 'label.configure') <> 11 then
    raise exception 'label.configure is missing role rows: every role must say yes or no out loud';
  end if;
  if (select count(*) from public.plan_permissions where permission_id = 'label.configure' and granted) <> 4 then
    raise exception 'label.configure must be granted on all four plans';
  end if;
  if not exists (
    select 1 from pg_policies
    where tablename = 'label_format' and policyname = 'label_format_write'
  ) then
    raise exception 'label_format has no write policy, so the key is not a fence';
  end if;
end $$;

commit;
