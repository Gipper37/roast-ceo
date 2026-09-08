-- Getting the lot code onto the bag.
--
-- The bagging screen mints a code and shows it big, and until now the packer
-- wrote it on with a marker. That is the weakest link in the whole chain: an
-- unreadable or transposed code is a bag that cannot be traced, and a recall
-- that starts "we think it was one of these three lots" is not a recall.
--
-- What a label has to carry is short and it is not negotiable: the lot code and
-- the best-before date, legibly. Everything else here is optional because it is
-- a matter of what the roaster already prints on their own packaging — a
-- traceability sticker goes ON a printed bag, it does not replace one. This is
-- deliberately NOT a retail label: ingredients, allergens, nutrition and the
-- responsible-party address are a packaging-design job with its own regulations,
-- and pretending a food-safety module produces a compliant retail label would be
-- the kind of half-answer that gets somebody fined.
--
-- The barcode is the point of the exercise. A handheld scanner is a keyboard, so
-- a Code 128 barcode turns "type the lot code from the returned bag" into
-- "scan it" with no hardware integration at all — see lib/food-safety/code128.ts,
-- which has no dependency and is a pure function of the string.

begin;

create table if not exists public.fs_label_format (
  company_id      text primary key references public.companies(company_id) on delete cascade,
  -- Stock the label is printed on. 'sheet' is the cheap route for a roastery
  -- with no label printer: an A4/Letter sheet of address labels.
  preset          text not null default '50x25'
                  check (preset in ('50x25','75x50','100x50','sheet','custom')),
  width_mm        numeric not null default 50.8,
  height_mm       numeric not null default 25.4,
  -- Sheet layout, used only when preset = 'sheet'.
  sheet_cols      int not null default 3 check (sheet_cols between 1 and 8),
  sheet_rows      int not null default 8 check (sheet_rows between 1 and 20),

  show_company    boolean not null default true,
  show_product    boolean not null default true,
  show_packed_on  boolean not null default false,
  show_best_before boolean not null default true,
  show_net_weight boolean not null default false,
  show_barcode    boolean not null default true,
  -- One free line for whatever the roaster puts on theirs — "Roasted in Maui",
  -- a website, a batch note. Never validated, never required.
  extra_line      text,

  updated_at      timestamptz not null default now(),
  updated_by      text
);

comment on table public.fs_label_format is
  'How a tenant''s bag labels are laid out. A traceability sticker, not a retail label — ingredients, allergens and nutrition are a packaging-design job with its own regulations.';

alter table public.fs_label_format enable row level security;

create policy fs_label_format_read on public.fs_label_format
  for select using (company_id in (select auth_company_ids()));
create policy fs_label_format_write on public.fs_label_format
  for all using (company_id in (select auth_company_ids()) and public.auth_has_permission('pack.configure', company_id))
  with check (company_id in (select auth_company_ids()) and public.auth_has_permission('pack.configure', company_id));

-- ── Everything one label needs, in one call ─────────────────────────────────
-- The print view must not have to join five tables in the browser, and it must
-- read the SNAPSHOT columns rather than the live product row: a label reprinted
-- six months later has to say what the bag said on the day, not what the product
-- is called now.
create or replace function public.label_data(p_pack_run_id text)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'pack_run_id',  pr.pack_run_id,
    'lot_code',     pr.lot_code,
    'product',      coalesce(pr.product_name_snapshot, p.product_name),
    'coffee_prep',  pr.coffee_prep,
    'packed_on',    pr.packed_on,
    'best_before',  pr.best_before,
    'bags',         pr.bags,
    'net_weight_lbs', pr.unit_weight_lbs,
    'company_name', c.company_name,
    'format', coalesce(
      (select to_jsonb(f) from public.fs_label_format f where f.company_id = pr.company_id),
      -- A tenant who never opened the settings still gets a working label.
      jsonb_build_object(
        'preset','50x25','width_mm',50.8,'height_mm',25.4,
        'sheet_cols',3,'sheet_rows',8,
        'show_company',true,'show_product',true,'show_packed_on',false,
        'show_best_before',true,'show_net_weight',false,'show_barcode',true,
        'extra_line',null)))
    from public.pack_run pr
    left join public.products p on p.product_id = pr.product_id
    left join public.companies c on c.company_id = pr.company_id
   where pr.pack_run_id = p_pack_run_id
     and pr.company_id in (select auth_company_ids());
$$;

comment on function public.label_data is
  'Everything one label needs, reading the pack run''s SNAPSHOT columns — a label reprinted six months later must say what the bag said on the day, not what the product is called now.';

revoke all on function public.label_data(text) from public;
grant execute on function public.label_data(text) to authenticated;

commit;
