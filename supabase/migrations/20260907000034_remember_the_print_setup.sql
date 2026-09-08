-- Remember how they print.
--
-- Owner, 2026-09-07: *"the print set up should be saved in memory so it surfaces
-- that as the default option in every future print. they set upc as 2x1 on zebra
-- and lot code as 1x0.5 on X printer and it remembers for next but still can be
-- changed. or they print them both on a bigger one or they print each on a 2x1,
-- you get the idea"*.
--
-- Three things, all of them "set it once":
--
--   · which label they normally print, so the screen opens on it
--   · the stock size for EACH label, which the per-kind rows already hold —
--     what was missing is being able to set them from the print screen instead
--     of a settings page
--   · which printer each one goes to. We cannot select a printer from a browser
--     — the print dialog owns that — so this is a NOTE shown beside the size,
--     not a promise. Naming it honestly ("Lot code · 1×0.5 · Brother by the
--     bench") is worth more than pretending to drive the hardware.
--
-- `preset` collapses to just 'roll' or 'sheet'. It was carrying two ideas at
-- once — a named size AND whether the layout is a roll or a grid — and the size
-- is already in width_mm/height_mm, so the names were a second source of truth
-- for the same numbers.

begin;

alter table public.fs_settings
  add column if not exists default_label_kind text not null default 'lot';

alter table public.fs_settings drop constraint if exists fs_settings_default_kind_check;
alter table public.fs_settings add constraint fs_settings_default_kind_check
  check (default_label_kind in ('combined', 'retail', 'lot', 'case'));

comment on column public.fs_settings.default_label_kind is
  'What the print screen opens on. Set by using it, not by configuring it.';

alter table public.fs_label_format
  add column if not exists printer_note text;

comment on column public.fs_label_format.printer_note is
  'Which printer this stock is loaded in, in the operator''s own words. A reminder, not a driver — a browser cannot choose a printer, and saying so plainly beats pretending otherwise.';

-- Collapse preset to the one thing it actually decides.
-- The DROP comes first: the old inline check still forbids 'roll', so updating
-- the rows before removing it fails on the first row.
alter table public.fs_label_format drop constraint if exists fs_label_format_preset_check;
update public.fs_label_format set preset = 'roll' where preset <> 'sheet';
alter table public.fs_label_format add constraint fs_label_format_preset_check
  check (preset in ('roll', 'sheet'));
alter table public.fs_label_format alter column preset set default 'roll';

-- ── Save a label's setup from the screen you print on ───────────────────────
create or replace function public.save_label_format(
  p_company_id   text,
  p_kind         text,
  p_width_mm     numeric,
  p_height_mm    numeric,
  p_preset       text default 'roll',
  p_printer_note text default null,
  p_sheet_cols   int  default null,
  p_sheet_rows   int  default null
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
  -- Generous, but not nonsense: below about 10mm nothing readable fits, and
  -- above 300mm it is not a label.
  if p_width_mm is null or p_height_mm is null
     or p_width_mm not between 10 and 300 or p_height_mm not between 10 and 300 then
    raise exception 'A label has to be between 10 and 300 mm on each side.'
      using errcode = 'invalid_parameter_value';
  end if;

  insert into public.fs_label_format as f
    (company_id, kind, preset, width_mm, height_mm, printer_note, sheet_cols, sheet_rows, updated_at)
  values (p_company_id, p_kind, coalesce(p_preset,'roll'), p_width_mm, p_height_mm,
          nullif(trim(p_printer_note), ''), coalesce(p_sheet_cols, 3), coalesce(p_sheet_rows, 8), now())
  on conflict (company_id, kind) do update
    set preset = excluded.preset,
        width_mm = excluded.width_mm,
        height_mm = excluded.height_mm,
        printer_note = excluded.printer_note,
        sheet_cols = coalesce(p_sheet_cols, f.sheet_cols),
        sheet_rows = coalesce(p_sheet_rows, f.sheet_rows),
        updated_at = now();
end;
$$;

-- ── The screen opens on whatever they printed last ──────────────────────────
create or replace function public.set_default_label_kind(p_company_id text, p_kind text)
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
  -- Deliberately gated on pack.run, not pack.configure: this is a preference set
  -- by USING the screen, and the packer who prints every day is exactly who
  -- should be setting it.
  if not public.auth_has_permission('pack.run', p_company_id) then
    raise exception 'You do not have permission to do that.' using errcode = 'insufficient_privilege';
  end if;
  if p_kind not in ('combined','retail','lot','case') then
    raise exception 'Unknown label.' using errcode = 'invalid_parameter_value';
  end if;

  insert into public.fs_settings (company_id, default_label_kind)
  values (p_company_id, p_kind)
  on conflict (company_id) do update set default_label_kind = excluded.default_label_kind, updated_at = now();
end;
$$;

-- ── label_data carries the remembered choice and the printer notes ──────────
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
    'company_name', c.company_name,
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
          'show_company',true,'show_product',true,
          'show_roasted_on',true,'show_packed_on',false,
          'show_best_before',true,'show_net_weight',false,'show_barcode',true,
          'extra_line',null)))
      from defaults d))
    from public.pack_run pr
    left join public.products p on p.product_id = pr.product_id
    left join public.companies c on c.company_id = pr.company_id
   where pr.pack_run_id = p_pack_run_id
     and pr.company_id in (select auth_company_ids());
$$;

-- ── A best-by they typed becomes the next default ──────────────────────────
-- Owner: *"the best buy should also remember the latest input"*. Correcting a
-- date once and then retyping it on every run is the kind of small repeated
-- friction that quietly stops people recording anything.
--
-- The new shelf life is measured from the ROAST date, not the bagging date,
-- because that is what the claim is actually about — coffee ages from the roast.
-- It is reported back to the caller so the screen can say what changed rather
-- than silently moving a default under them.
--
-- Dropped rather than replaced: it returned `date` before, and Postgres will not
-- change a function's return type in place.
drop function if exists public.set_pack_run_best_before(text, date);

create or replace function public.set_pack_run_best_before(p_pack_run_id text, p_best_before date)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_company text; v_packed date; v_roasted date; v_days int;
begin
  select pr.company_id, pr.packed_on,
         (select max(rl.roast_date)::date
            from public.pack_run_source s
            join public.roast_log rl on rl.roast_log_id = s.roast_log_id
           where s.pack_run_id = pr.pack_run_id)
    into v_company, v_packed, v_roasted
    from public.pack_run pr
   where pr.pack_run_id = p_pack_run_id and pr.company_id in (select auth_company_ids());
  if v_company is null then raise exception 'No such pack run.' using errcode = 'no_data_found'; end if;
  if not public.auth_has_permission('pack.run', v_company) then
    raise exception 'You do not have permission to change this.' using errcode = 'insufficient_privilege';
  end if;
  if p_best_before is not null and p_best_before < v_packed then
    raise exception 'A best-before date cannot fall before the day the coffee was bagged.'
      using errcode = 'invalid_parameter_value';
  end if;

  update public.pack_run
     set best_before = p_best_before, updated_at = now()
   where pack_run_id = p_pack_run_id;

  -- Remember it, when it is a sane shelf life measured from the roast.
  if p_best_before is not null and coalesce(v_roasted, v_packed) is not null then
    v_days := p_best_before - coalesce(v_roasted, v_packed);
    if v_days between 1 and 3650 then
      insert into public.fs_settings (company_id, shelf_life_days)
      values (v_company, v_days)
      on conflict (company_id) do update
        set shelf_life_days = excluded.shelf_life_days, updated_at = now();
    else
      v_days := null;
    end if;
  end if;

  return jsonb_build_object('best_before', p_best_before, 'shelf_life_days', v_days);
end;
$$;

revoke all on function public.set_pack_run_best_before(text, date) from public;
grant execute on function public.set_pack_run_best_before(text, date) to authenticated;

revoke all on function public.label_data(text) from public;
revoke all on function public.save_label_format(text, text, numeric, numeric, text, text, int, int) from public;
revoke all on function public.set_default_label_kind(text, text) from public;
grant execute on function public.label_data(text) to authenticated;
grant execute on function public.save_label_format(text, text, numeric, numeric, text, text, int, int) to authenticated;
grant execute on function public.set_default_label_kind(text, text) to authenticated;

commit;
