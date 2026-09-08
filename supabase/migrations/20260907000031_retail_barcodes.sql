-- Retail barcodes, and one label instead of two.
--
-- Owner, 2026-09-07: *"can we build a barcode generator into the app that can
-- then print barcodes (into zebra, brother, etc). if so could we couple the lot
-- code into that same label so they only have to print one label."*
--
-- Yes — with one line that has to be said plainly, because getting it wrong is
-- expensive and irreversible:
--
-- 🔴 A GTIN IS ALLOCATED, NOT GENERATED. The number comes from a GS1 company
-- prefix the roaster buys, and Costco requires a registered one. STRATA draws
-- the symbol for a number they own and refuses one whose check digit does not
-- add up. It must never invent a number: an invented GTIN collides with somebody
-- else's product on a real till, and unlike a bad label that cannot be recalled.
--
-- So `products.gtin` is the roaster's own number, validated on the way in by
-- `gs1_check_ok()` — the same weighted-modulo-ten rule that governs UPC-A (12),
-- EAN-13 (13) and GTIN-14, which is why one function covers all of them.
--
-- ── Why a bag gets two symbols and a case gets one ──────────────────────────
-- A till scanner reads UPC-A/EAN-13 and nothing else, so on a retail bag the
-- price-lookup code and the lot code have to be two separate symbols — that is
-- not a limitation we can design around. A case never crosses a till, so one
-- GS1-128 carries (01) GTIN, (17) best-before and (10) lot together, which is
-- exactly what a distributor's receiving scanner expects.
--
-- Either way it is ONE label, which was the ask.

begin;

-- ── The check digit, in the database ────────────────────────────────────────
-- In the DB and not only in the form: a GTIN can arrive from an import or the
-- API, and a wrong one is not visible by eye.
create or replace function public.gs1_check_ok(p_code text)
returns boolean
language plpgsql
immutable
as $$
declare v_sum int := 0; v_len int; v_j int; v_digit int;
begin
  if p_code is null or p_code = '' then return true; end if;      -- absent is fine
  if p_code !~ '^[0-9]+$' then return false; end if;
  v_len := length(p_code);
  if v_len not in (8, 12, 13, 14) then return false; end if;

  -- Weight 3,1,3,1… counting from the RIGHT of the data digits.
  for v_j in 1 .. (v_len - 1) loop
    v_digit := substring(p_code from (v_len - v_j) for 1)::int;
    v_sum := v_sum + v_digit * (case when v_j % 2 = 1 then 3 else 1 end);
  end loop;

  return ((10 - (v_sum % 10)) % 10) = substring(p_code from v_len for 1)::int;
end;
$$;

comment on function public.gs1_check_ok is
  'The GS1 check digit rule — one function for UPC-A (12), EAN-13 (13) and GTIN-14. A GTIN is allocated from a purchased GS1 prefix, never generated: this validates, it does not mint.';

-- ── The roaster's own number, on the variant that carries it ────────────────
-- On `products` (the VARIANT) rather than product_groups, because the barcode
-- identifies a size and channel — a 12oz and a 5lb bag of the same coffee are
-- different GTINs, which is the whole point of the number.
alter table public.products
  add column if not exists gtin text;

alter table public.products drop constraint if exists products_gtin_valid;
alter table public.products add constraint products_gtin_valid
  check (gtin is null or public.gs1_check_ok(gtin));

comment on column public.products.gtin is
  'The variant''s retail barcode number (UPC-A / EAN-13 / GTIN-14), ALLOCATED from the roaster''s own GS1 prefix. Check digit enforced. A 12oz and a 5lb bag of the same coffee are different GTINs — that is what the number is for.';

-- Two variants sharing a GTIN is always a mistake, and it is the mistake that
-- rings up the wrong price. Partial so the overwhelming majority (null) are free.
create unique index if not exists uq_products_gtin
  on public.products (company_id, gtin) where gtin is not null;

-- ── What the label carries ──────────────────────────────────────────────────
alter table public.fs_label_format
  add column if not exists label_kind text not null default 'retail',
  add column if not exists show_retail_barcode boolean not null default true,
  add column if not exists case_qty int;

alter table public.fs_label_format drop constraint if exists fs_label_format_kind_check;
alter table public.fs_label_format add constraint fs_label_format_kind_check
  check (label_kind in ('retail', 'case'));

comment on column public.fs_label_format.label_kind is
  'retail = a bag: the till''s UPC plus a Code 128 lot code, two symbols because a till scanner reads only the first. case = a carton: one GS1-128 carrying (01)(17)(10) together.';

-- ── The label needs the number ──────────────────────────────────────────────
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
    -- Live, not snapshotted, and deliberately: a GTIN identifies the product for
    -- the rest of its life. If it changed, the old one was wrong.
    'gtin',         p.gtin,
    'company_name', c.company_name,
    'format', coalesce(
      (select to_jsonb(f) from public.fs_label_format f where f.company_id = pr.company_id),
      jsonb_build_object(
        'preset','50x25','width_mm',50.8,'height_mm',25.4,
        'sheet_cols',3,'sheet_rows',8,
        'label_kind','retail','show_retail_barcode',true,'case_qty',null,
        'show_company',true,'show_product',true,'show_packed_on',false,
        'show_best_before',true,'show_net_weight',false,'show_barcode',true,
        'extra_line',null)))
    from public.pack_run pr
    left join public.products p on p.product_id = pr.product_id
    left join public.companies c on c.company_id = pr.company_id
   where pr.pack_run_id = p_pack_run_id
     and pr.company_id in (select auth_company_ids());
$$;

revoke all on function public.label_data(text) from public;
grant execute on function public.label_data(text) to authenticated;

commit;
