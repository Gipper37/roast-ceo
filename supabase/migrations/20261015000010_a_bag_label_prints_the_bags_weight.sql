-- A bag label must print the weight of the BAG.
--
-- `pack_run.unit_weight_lbs` is the weight of one thing SOLD, which for a case
-- variant is the whole box. `_label_data_core` handed it to the renderer as
-- `net_weight_lbs` and the retail label printed it as the net weight of a
-- single bag. On MCR's live data:
--
--   Costco Maui Blend - 2lbs (Case of 12)   a 2 lb bag printed "Net 24 lb"
--   Maui Blend - 2oz (Case of 40)           a 2 oz bag printed "Net 5 lb"
--
-- That is a net-weight declaration on a consumer package, wrong by the pack
-- count, on labels a roaster prints to satisfy a food-safety programme. It is
-- the only number on the bag a regulator reads.
--
-- ── Divided here, not in the renderer ─────────────────────────────────────
--
-- Every label surface reads this one function, and there are four formats with
-- more to come. Dividing in the renderer means the next format has to remember;
-- dividing here means it cannot forget. The case total stays available as
-- `case_weight_lbs` for a surface that genuinely means the box, and
-- `units_per_case` comes with it so nothing has to recompute the pack count
-- from a name.
--
-- 🔴 The total weight of the RUN was never wrong and is untouched. An order
-- line for a case variant is a count of cases, so bags x unit_weight_lbs is
-- the right number of pounds; only the per-label figure was reading the box.
--
-- 🔴 THE BODY BELOW IS THE LIVE DEFINITION, dumped with pg_get_functiondef and
-- patched. CREATE OR REPLACE rewrites the whole function.

begin;

CREATE OR REPLACE FUNCTION public._label_data_core(p_pack_run_id text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
    -- 🔴 PER BAG, not per selling unit. pack_run.unit_weight_lbs is the weight
    -- of one thing SOLD, and for a case variant that is the whole box: on MCR's
    -- "Costco Maui Blend - 2lbs (Case of 12)" it is 24. Printed straight onto a
    -- retail label it put "Net 24 lb" on a 2 lb bag, which is a net-weight claim
    -- on a consumer package and wrong by the pack count.
    --
    -- A label goes on the thing it is stuck to. Divided by the pack count here,
    -- in the one place every label surface reads, rather than in the renderer
    -- where the next label format would have to remember.
    'net_weight_lbs', case
                        when coalesce(sz.units_per_case, 1) > 1
                          then round(pr.unit_weight_lbs / sz.units_per_case, 6)
                        else pr.unit_weight_lbs
                      end,
    -- What one selling unit is, so a surface that genuinely means the case (a
    -- case label, a pallet sheet) can ask instead of recomputing.
    'units_per_case', sz.units_per_case,
    'case_weight_lbs', pr.unit_weight_lbs,
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
          'show_best_before',true,'show_net_weight',false,'show_barcode',true,
          'extra_line',null)))
      from defaults d))
    from public.pack_run pr
    left join public.products p on p.product_id = pr.product_id
    left join public.size sz on sz.size_id = p.size
   where pr.pack_run_id = p_pack_run_id
     and pr.company_id in (select auth_company_ids());
$function$

;

do $verify$
declare v_def text; v_bad int;
begin
  select pg_get_functiondef(oid) into v_def from pg_proc where proname = '_label_data_core';
  if v_def is null then raise exception '_label_data_core is gone'; end if;
  if v_def not like '%units_per_case%' then
    raise exception '_label_data_core does not consult the pack count';
  end if;
  -- 🔴 Everything else that was in there still is. A replace that dropped the
  -- tenant fence would turn a label lookup into a cross-company read.
  if v_def not like '%auth_company_ids%' then
    raise exception '_label_data_core lost its tenant fence';
  end if;
  if v_def not like '%pack_run_source%' then
    raise exception '_label_data_core lost the roasted-on lookup';
  end if;
  if not exists (select 1 from pg_proc where proname = '_label_data_core' and prosecdef and provolatile = 's') then
    raise exception '_label_data_core lost SECURITY DEFINER or STABLE';
  end if;

  -- 🔴 THE ARITHMETIC IS CHECKED WITHOUT CALLING THE FUNCTION, deliberately.
  --
  -- `_label_data_core` ends in `pr.company_id in (select auth_company_ids())`,
  -- and a migration runs as postgres with no auth.uid(), so the function
  -- returns NULL here for every row. A check written as
  --
  --   (core(id) ->> 'net_weight_lbs')::numeric >= pr.unit_weight_lbs
  --
  -- would compare NULL, count nothing and pass whatever the function did --
  -- which is exactly how the first draft of this block, and the hand test
  -- beside it, both reported OK against a function returning nothing at all.
  -- A verify that cannot fail is not a verify.
  --
  -- So the same expression is evaluated directly against the tables. It proves
  -- the DATA produces a strictly smaller per-bag figure; the definition checks
  -- above prove the function carries that expression.
  select count(*) into v_bad
    from public.pack_run pr
    join public.products p on p.product_id = pr.product_id
    join public.size sz on sz.size_id = p.size
   where coalesce(sz.units_per_case, 1) > 1
     and pr.unit_weight_lbs is not null
     and round(pr.unit_weight_lbs / sz.units_per_case, 6) >= pr.unit_weight_lbs;
  if v_bad > 0 then
    raise exception '% case pack run(s) would still print the case weight on a bag', v_bad;
  end if;

  raise notice 'a bag label now prints the bag''s weight; % case pack run(s) on this database',
    (select count(*) from public.pack_run pr
      join public.products p on p.product_id = pr.product_id
      join public.size sz on sz.size_id = p.size
     where coalesce(sz.units_per_case, 1) > 1);
end $verify$;

commit;
