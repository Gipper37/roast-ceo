-- Roasted on, and best by, worked out for you.
--
-- Owner, 2026-09-07: *"the date/lot label should auto generate the roasted on
-- and best buy (a settings option defaulted to 6 months and made clear when
-- printing where to adjust it and also having the option to manually set it
-- there)"*.
--
-- Two things this fixes.
--
-- 1. THE LABEL HAD NO ROAST DATE, which is the date a coffee person actually
--    looks for on a bag. It was showing the day it was BAGGED, which is not the
--    same thing and is sometimes days later. The roast date comes from the
--    batches the run was made from — the latest of them, which is the
--    conventional reading for a bag blended from more than one.
--
-- 2. THE SHELF LIFE WAS A HARDCODED YEAR in the browser. It is now a per-tenant
--    setting defaulting to six months, which is the usual figure for roasted
--    coffee, and the bagging screen computes best-before from it.
--
-- ── Why an override writes to the record ────────────────────────────────────
-- Changing the best-before at print time UPDATES the pack run rather than
-- printing something the record does not say. A label that disagrees with the
-- traceability record is worse than either one alone: it is the thing an
-- auditor finds and cannot explain, and the customer holding the bag believes
-- the label.

begin;

create table if not exists public.fs_settings (
  company_id      text primary key references public.companies(company_id) on delete cascade,
  -- Six months. The usual figure for roasted coffee, and only a default: the
  -- roaster owns this claim, not us.
  shelf_life_days int not null default 183 check (shelf_life_days between 1 and 3650),
  updated_at      timestamptz not null default now(),
  updated_by      text
);

comment on table public.fs_settings is
  'Per-tenant food-safety defaults. shelf_life_days seeds best-before at bagging; it is a default, never a constraint — the roaster owns the quality claim.';

alter table public.fs_settings enable row level security;
create policy fs_settings_read on public.fs_settings
  for select using (company_id in (select auth_company_ids()));
create policy fs_settings_write on public.fs_settings
  for all using (company_id in (select auth_company_ids()) and public.auth_has_permission('pack.configure', company_id))
  with check (company_id in (select auth_company_ids()) and public.auth_has_permission('pack.configure', company_id));

-- ── The label needs the roast date and the shelf life ───────────────────────
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
    'lot_code',     pr.lot_code,
    'product',      coalesce(pr.product_name_snapshot, p.product_name),
    'coffee_prep',  pr.coffee_prep,
    'packed_on',    pr.packed_on,
    'best_before',  pr.best_before,
    -- The date a coffee person looks for. The LATEST of the batches this run was
    -- made from: a bag blended from Monday and Wednesday is a Wednesday roast.
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
    'formats', (
      select jsonb_object_agg(d.kind, coalesce(
        (select to_jsonb(f) from public.fs_label_format f
          where f.company_id = pr.company_id and f.kind = d.kind),
        jsonb_build_object(
          'kind', d.kind, 'preset','custom', 'width_mm', d.w, 'height_mm', d.h,
          'sheet_cols',3,'sheet_rows',8,'case_qty',null,
          'show_company',true,'show_product',true,
          -- On by default now: a bag without a roast date is a bag nobody trusts.
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

alter table public.fs_label_format
  add column if not exists show_roasted_on boolean not null default true;

-- ── Correcting a best-before writes to the record ───────────────────────────
create or replace function public.set_pack_run_best_before(p_pack_run_id text, p_best_before date)
returns date
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_company text; v_packed date;
begin
  select company_id, packed_on into v_company, v_packed
    from public.pack_run
   where pack_run_id = p_pack_run_id and company_id in (select auth_company_ids());
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
  return p_best_before;
end;
$$;

comment on function public.set_pack_run_best_before is
  'Corrects the best-before ON THE RECORD, so the label and the traceability record cannot disagree — a label that says something the record does not is what an auditor finds and nobody can explain.';

revoke all on function public.label_data(text) from public;
revoke all on function public.set_pack_run_best_before(text, date) from public;
grant execute on function public.label_data(text) to authenticated;
grant execute on function public.set_pack_run_best_before(text, date) to authenticated;

commit;
