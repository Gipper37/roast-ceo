-- The roastery name comes off the label entirely.
--
-- Owner: *"drop the compan name option altogether. dont need it"*. It was
-- defaulted off one migration ago; a toggle nobody will ever turn on is still a
-- row in a settings panel and a branch in the layout maths, so it goes.
--
-- The bag the sticker is applied to already says who roasted the coffee.

begin;

alter table public.fs_label_format drop column if exists show_company;

drop function if exists public.save_label_format(
  text, text, numeric, numeric, text, text, int, int,
  boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, text);

create or replace function public.save_label_format(
  p_company_id       text,
  p_kind             text,
  p_width_mm         numeric,
  p_height_mm        numeric,
  p_preset           text    default 'roll',
  p_printer_note     text    default null,
  p_sheet_cols       int     default null,
  p_sheet_rows       int     default null,
  p_show_product     boolean default null,
  p_show_roasted_on  boolean default null,
  p_show_best_before boolean default null,
  p_show_packed_on   boolean default null,
  p_show_net_weight  boolean default null,
  p_show_barcode     boolean default null,
  p_show_gtin_text   boolean default null,
  p_extra_line       text    default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_company_id is null or not exists (
    select 1 from unnest(array(select auth_company_ids())) c(id) where c.id = p_company_id
  ) then
    raise exception 'Not your company.' using errcode = 'insufficient_privilege';
  end if;
  if not public.auth_has_permission('pack.configure', p_company_id) then
    raise exception 'You do not have permission to change label setup.' using errcode = 'insufficient_privilege';
  end if;
  if p_kind not in ('combined','retail','lot','case') then
    raise exception 'Unknown label.' using errcode = 'invalid_parameter_value';
  end if;
  if p_width_mm is null or p_height_mm is null
     or p_width_mm not between 10 and 300 or p_height_mm not between 10 and 300 then
    raise exception 'A label has to be between 10 and 300 mm on each side.'
      using errcode = 'invalid_parameter_value';
  end if;

  insert into public.fs_label_format as f
    (company_id, kind, preset, width_mm, height_mm, printer_note, sheet_cols, sheet_rows,
     show_product, show_roasted_on, show_best_before, show_packed_on,
     show_net_weight, show_barcode, show_gtin_text, extra_line, updated_at)
  values (p_company_id, p_kind, coalesce(p_preset,'roll'), p_width_mm, p_height_mm,
          nullif(trim(p_printer_note), ''), coalesce(p_sheet_cols, 3), coalesce(p_sheet_rows, 8),
          coalesce(p_show_product, true),
          coalesce(p_show_roasted_on, true), coalesce(p_show_best_before, true),
          coalesce(p_show_packed_on, false), coalesce(p_show_net_weight, false),
          coalesce(p_show_barcode, true), coalesce(p_show_gtin_text, false),
          nullif(trim(p_extra_line), ''), now())
  on conflict (company_id, kind) do update
    set preset       = excluded.preset,
        width_mm     = excluded.width_mm,
        height_mm    = excluded.height_mm,
        printer_note = excluded.printer_note,
        sheet_cols   = coalesce(p_sheet_cols, f.sheet_cols),
        sheet_rows   = coalesce(p_sheet_rows, f.sheet_rows),
        show_product     = coalesce(p_show_product,     f.show_product),
        show_roasted_on  = coalesce(p_show_roasted_on,  f.show_roasted_on),
        show_best_before = coalesce(p_show_best_before, f.show_best_before),
        show_packed_on   = coalesce(p_show_packed_on,   f.show_packed_on),
        show_net_weight  = coalesce(p_show_net_weight,  f.show_net_weight),
        show_barcode     = coalesce(p_show_barcode,     f.show_barcode),
        show_gtin_text   = coalesce(p_show_gtin_text,   f.show_gtin_text),
        extra_line       = coalesce(nullif(trim(p_extra_line), ''), f.extra_line),
        updated_at   = now();
end;
$$;

create or replace function public.label_data(p_pack_run_id text)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with defaults as (
    select * from (values
      ('combined', 76.2, 50.8),
      ('retail',   50.8, 31.8),
      ('lot',      50.8, 25.4),
      ('case',    101.6, 50.8)
    ) as d(kind, w, h)
  )
  select jsonb_build_object(
    'pack_run_id',  pr.pack_run_id,
    'company_id',   pr.company_id,
    'lot_code',     pr.lot_code,
    'product',      coalesce(pr.product_name_snapshot, p.product_name),
    'coffee_prep',  pr.coffee_prep,
    'packed_on',    pr.packed_on,
    'best_before',  pr.best_before,
    'roasted_on',   (select max(rl.roast_date)::date
                       from public.pack_run_source s
                       join public.roast_log rl on rl.roast_log_id = s.roast_log_id
                      where s.pack_run_id = pr.pack_run_id),
    'bags',         pr.bags,
    'net_weight_lbs', pr.unit_weight_lbs,
    'gtin',         p.gtin,
    'shelf_life_days', coalesce(
      (select st.shelf_life_days from public.fs_settings st where st.company_id = pr.company_id), 183),
    'default_kind', coalesce(
      (select st.default_label_kind from public.fs_settings st where st.company_id = pr.company_id), 'lot'),
    'formats', (
      select jsonb_object_agg(d.kind, coalesce(
        (select to_jsonb(f) from public.fs_label_format f
          where f.company_id = pr.company_id and f.kind = d.kind),
        jsonb_build_object(
          'kind', d.kind, 'preset','roll', 'width_mm', d.w, 'height_mm', d.h,
          'sheet_cols',3,'sheet_rows',8,'case_qty',null,'printer_note',null,
          'show_product',true,'show_roasted_on',true,'show_packed_on',false,
          'show_best_before',true,'show_net_weight',false,
          'show_barcode',true,'show_gtin_text',false,
          'extra_line',null)))
      from defaults d))
    from public.pack_run pr
    left join public.products p on p.product_id = pr.product_id
   where pr.pack_run_id = p_pack_run_id
     and pr.company_id in (select auth_company_ids());
$$;

revoke all on function public.label_data(text) from public;
revoke all on function public.save_label_format(
  text, text, numeric, numeric, text, text, int, int,
  boolean, boolean, boolean, boolean, boolean, boolean, boolean, text) from public;
grant execute on function public.label_data(text) to authenticated;
grant execute on function public.save_label_format(
  text, text, numeric, numeric, text, text, int, int,
  boolean, boolean, boolean, boolean, boolean, boolean, boolean, text) to authenticated;

commit;
