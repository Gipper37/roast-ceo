-- The optional lines are part of the setup, so they save with it.
--
-- `save_label_format` took only the size and the printer note, but the fit
-- warning now tells somebody to "turn off a line you do not need" — and a
-- control that suggests an action it cannot save is worse than no control.
--
-- On a 1"-tall date sticker these are exactly what gets dropped: the bag it goes
-- on already says who roasted the coffee and what it is.

begin;

drop function if exists public.save_label_format(text, text, numeric, numeric, text, text, int, int);

create or replace function public.save_label_format(
  p_company_id       text,
  p_kind             text,
  p_width_mm         numeric,
  p_height_mm        numeric,
  p_preset           text    default 'roll',
  p_printer_note     text    default null,
  p_sheet_cols       int     default null,
  p_sheet_rows       int     default null,
  p_show_company     boolean default null,
  p_show_product     boolean default null,
  p_show_roasted_on  boolean default null,
  p_show_best_before boolean default null,
  p_show_packed_on   boolean default null,
  p_show_net_weight  boolean default null,
  p_show_barcode     boolean default null,
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
     show_company, show_product, show_roasted_on, show_best_before, show_packed_on,
     show_net_weight, show_barcode, extra_line, updated_at)
  values (p_company_id, p_kind, coalesce(p_preset,'roll'), p_width_mm, p_height_mm,
          nullif(trim(p_printer_note), ''), coalesce(p_sheet_cols, 3), coalesce(p_sheet_rows, 8),
          coalesce(p_show_company, true), coalesce(p_show_product, true),
          coalesce(p_show_roasted_on, true), coalesce(p_show_best_before, true),
          coalesce(p_show_packed_on, false), coalesce(p_show_net_weight, false),
          coalesce(p_show_barcode, true), nullif(trim(p_extra_line), ''), now())
  on conflict (company_id, kind) do update
    set preset       = excluded.preset,
        width_mm     = excluded.width_mm,
        height_mm    = excluded.height_mm,
        printer_note = excluded.printer_note,
        sheet_cols   = coalesce(p_sheet_cols, f.sheet_cols),
        sheet_rows   = coalesce(p_sheet_rows, f.sheet_rows),
        -- Null means "leave it alone", so a caller that only moves the size does
        -- not silently reset every line back to its default.
        show_company     = coalesce(p_show_company,     f.show_company),
        show_product     = coalesce(p_show_product,     f.show_product),
        show_roasted_on  = coalesce(p_show_roasted_on,  f.show_roasted_on),
        show_best_before = coalesce(p_show_best_before, f.show_best_before),
        show_packed_on   = coalesce(p_show_packed_on,   f.show_packed_on),
        show_net_weight  = coalesce(p_show_net_weight,  f.show_net_weight),
        show_barcode     = coalesce(p_show_barcode,     f.show_barcode),
        extra_line       = coalesce(nullif(trim(p_extra_line), ''), f.extra_line),
        updated_at   = now();
end;
$$;

revoke all on function public.save_label_format(
  text, text, numeric, numeric, text, text, int, int,
  boolean, boolean, boolean, boolean, boolean, boolean, boolean, text) from public;
grant execute on function public.save_label_format(
  text, text, numeric, numeric, text, text, int, int,
  boolean, boolean, boolean, boolean, boolean, boolean, boolean, text) to authenticated;

commit;
