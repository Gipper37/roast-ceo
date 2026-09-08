-- Pick what to print. Each choice has its own stock.
--
-- Owner, 2026-09-07: *"that shouldn't be the flow for the barcode print… it
-- should just allow you to choose both to print or either one. dont complicate
-- things. also should we allow for lot code to be printed on smaller label from
-- different printer… some users will only have the one label size and need to
-- print both on that."*
--
-- Right on both counts. The previous version had ONE saved size and treated
-- "both barcodes will not fit" as an error to be recovered from, which assumed
-- somebody had tried and failed. It is not an error, it is a choice made before
-- printing.
--
-- And both worlds are ordinary in coffee:
--
--   pre-printed bags already carrying the UPC, plus a small date/lot sticker
--   applied at packing — often off a second, cheap thermal printer on a 1"x0.5"
--   or 2"x1" roll. This is the most common setup.
--
--   one bigger label printed on demand carrying everything, for roasters who
--   label their own bags.
--
-- So the format is keyed by WHAT IS ON THE LABEL, and each kind keeps its own
-- size. A roaster with one printer and one roll sets all three the same and
-- never thinks about it; a roaster with a label printer and a date-coder sets
-- them differently. Neither has to explain themselves to the software.

begin;

-- Rekey: the primary key becomes (company_id, kind).
alter table public.fs_label_format
  add column if not exists kind text not null default 'combined';

alter table public.fs_label_format drop constraint if exists fs_label_format_kind_values;
alter table public.fs_label_format add constraint fs_label_format_kind_values
  check (kind in ('combined', 'retail', 'lot', 'case'));

comment on column public.fs_label_format.kind is
  'What is ON the label: combined (UPC + lot) · retail (UPC only) · lot (lot code only, the small date sticker) · case (one GS1-128). Each keeps its own stock size, because a lot sticker and a retail label are usually different rolls on different printers.';

-- The old single-row-per-company shape becomes the 'combined' row.
alter table public.fs_label_format drop constraint if exists fs_label_format_pkey;
alter table public.fs_label_format add primary key (company_id, kind);

-- label_kind / show_retail_barcode described the same thing from the outside and
-- are now redundant: what is on the label IS the kind.
alter table public.fs_label_format drop column if exists label_kind;
alter table public.fs_label_format drop column if exists show_retail_barcode;

-- ── Every kind, in one call ─────────────────────────────────────────────────
-- The print screen switches between them without a round trip, so choosing what
-- to print is instant rather than a page load.
create or replace function public.label_data(p_pack_run_id text)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with defaults as (
    -- What a tenant who never opened the settings gets. The lot sticker is
    -- smaller on purpose: it is the one that goes on a pre-printed bag.
    select * from (values
      ('combined', 76.2, 50.8),
      ('retail',   50.8, 31.8),
      ('lot',      50.8, 25.4),
      ('case',    101.6, 50.8)
    ) as d(kind, w, h)
  )
  select jsonb_build_object(
    'pack_run_id',  pr.pack_run_id,
    'lot_code',     pr.lot_code,
    'product',      coalesce(pr.product_name_snapshot, p.product_name),
    'coffee_prep',  pr.coffee_prep,
    'packed_on',    pr.packed_on,
    'best_before',  pr.best_before,
    'bags',         pr.bags,
    'net_weight_lbs', pr.unit_weight_lbs,
    'gtin',         p.gtin,
    'company_name', c.company_name,
    'formats', (
      select jsonb_object_agg(d.kind, coalesce(
        (select to_jsonb(f) from public.fs_label_format f
          where f.company_id = pr.company_id and f.kind = d.kind),
        jsonb_build_object(
          'kind', d.kind, 'preset','custom', 'width_mm', d.w, 'height_mm', d.h,
          'sheet_cols',3,'sheet_rows',8,'case_qty',null,
          'show_company',true,'show_product',true,'show_packed_on',false,
          'show_best_before',true,'show_net_weight',false,'show_barcode',true,
          'extra_line',null)))
      from defaults d))
    from public.pack_run pr
    left join public.products p on p.product_id = pr.product_id
    left join public.companies c on c.company_id = pr.company_id
   where pr.pack_run_id = p_pack_run_id
     and pr.company_id in (select auth_company_ids());
$$;

comment on function public.label_data is
  'Everything the label screen needs, with a format per kind so switching what to print is instant. Reads the pack run''s SNAPSHOT columns — a label reprinted six months later must say what the bag said on the day.';

revoke all on function public.label_data(text) from public;
grant execute on function public.label_data(text) to authenticated;

commit;
