-- "Pulling 20.5 lb (Mar 14), 4.63 lb (Mar 14) and 12.38 lb (Mar 14)."
--
-- That is the new bagging screen stating its draw, and it is the old bug in a
-- new place. Three weights, three identical dates, and nothing saying which
-- coffee any of them is. For Analog — 33% High Acidity, 67% Low Acidity — the
-- component is the ONLY thing that distinguishes those rows, and it is the one
-- thing a packer would glance at to know the blend is right.
--
-- pack_draw_plan carried origin_id and no name. 20260908000006 fixed exactly
-- this for the batch list and then left the draw it feeds still speaking in ids
-- — see feedback_ids_are_not_names, which is now three for three on this table.
--
-- With the name the line reads:
--   "Pulling 20.5 lb Low Acidity (Mar 14), 4.63 lb Low Acidity (Mar 14)
--    and 12.38 lb High Acidity (Mar 14). Split by the recipe."
-- and the 67/33 is checkable at a glance by the person holding the bags.

begin;

create or replace function public.pack_draw_plan(
  p_company_id  text,
  p_recipe_id   text,
  p_lbs         numeric,
  p_days        int     default 180,
  p_facility_id text    default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_type  text;
  v_draw  jsonb := '[]'::jsonb;
  v_taken numeric := 0;
  v_need  numeric;
  v_basis text := 'fifo';
  c       record;
  b       record;
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'Not your company.' using errcode = 'insufficient_privilege';
  end if;
  if coalesce(p_lbs, 0) <= 0 or p_recipe_id is null then
    return jsonb_build_object('draw', '[]'::jsonb, 'taken', 0,
                              'shortfall', greatest(coalesce(p_lbs, 0), 0), 'basis', 'none');
  end if;

  select roast_type into v_type from public.roast_recipes
   where recipe_id = p_recipe_id and company_id = p_company_id;

  -- Resolved here, once, rather than handed out as an id for a caller to look
  -- up: coffee_inventory.origin is the name, rl.origin_id is a foreign key.
  create temp table _avail on commit drop as
    select r.roast_log_id, r.roast_date, r.remaining_lbs, rl.origin_id,
           coalesce(ci.origin, nullif(rl.coffee_name_snapshot, '')) as origin_name
      from public.roasts_available_to_pack(p_company_id, p_days, p_facility_id) r
      join public.roast_log rl on rl.roast_log_id = r.roast_log_id
      left join public.coffee_inventory ci on ci.origin_id = rl.origin_id
     where r.recipe_id = p_recipe_id and r.remaining_lbs > 0.01
     order by r.roast_date asc;

  if v_type = 'Post-Blend' and exists (
      select 1 from public.recipe_components
       where recipe_id = p_recipe_id and coalesce(percentage, 0) > 0) then
    v_basis := 'ratio';
    for c in
      select coffee_item, percentage from public.recipe_components
       where recipe_id = p_recipe_id and coalesce(percentage, 0) > 0
       order by percentage desc
    loop
      v_need := round(p_lbs * c.percentage, 2);
      for b in select * from _avail where origin_id = c.coffee_item and remaining_lbs > 0.01
                order by roast_date asc
      loop
        exit when v_need <= 0.001;
        declare v_take numeric := least(b.remaining_lbs, v_need);
        begin
          v_draw := v_draw || jsonb_build_object(
            'roast_log_id', b.roast_log_id, 'lbs_used', v_take,
            'roast_date', b.roast_date, 'origin_id', b.origin_id,
            'origin_name', b.origin_name,
            'share', round(c.percentage * 100)::int,
            'reason', 'ratio');
          update _avail set remaining_lbs = remaining_lbs - v_take where roast_log_id = b.roast_log_id;
          v_need  := v_need - v_take;
          v_taken := v_taken + v_take;
        end;
      end loop;
    end loop;
  end if;

  v_need := round(p_lbs - v_taken, 2);
  if v_need > 0.001 then
    for b in select * from _avail where remaining_lbs > 0.01 order by roast_date asc
    loop
      exit when v_need <= 0.001;
      declare v_take numeric := least(b.remaining_lbs, v_need);
      begin
        v_draw := v_draw || jsonb_build_object(
          'roast_log_id', b.roast_log_id, 'lbs_used', v_take,
          'roast_date', b.roast_date, 'origin_id', b.origin_id,
          'origin_name', b.origin_name,
          'reason', case when v_basis = 'ratio' then 'topped up' else 'fifo' end);
        update _avail set remaining_lbs = remaining_lbs - v_take where roast_log_id = b.roast_log_id;
        v_need  := v_need - v_take;
        v_taken := v_taken + v_take;
      end;
    end loop;
  end if;

  drop table if exists _avail;

  select coalesce(jsonb_agg(d order by d->>'roast_date'), '[]'::jsonb) into v_draw
    from (
      select jsonb_build_object(
               'roast_log_id', e->>'roast_log_id',
               'lbs_used',     round(sum((e->>'lbs_used')::numeric), 2),
               'roast_date',   min(e->>'roast_date'),
               'origin_id',    min(e->>'origin_id'),
               'origin_name',  min(e->>'origin_name'),
               'share',        max((e->>'share')::int),
               -- max(): 'topped up' beats 'ratio' beats 'fifo', so a folded row
               -- names the weaker basis rather than flattering itself.
               'reason',       max(e->>'reason')) as d
        from jsonb_array_elements(v_draw) e
       group by e->>'roast_log_id'
    ) folded;

  return jsonb_build_object(
    'draw', v_draw, 'taken', round(v_taken, 2),
    'shortfall', round(greatest(p_lbs - v_taken, 0), 2), 'basis', v_basis);
end;
$$;

revoke all on function public.pack_draw_plan(text, text, numeric, int, text) from public;
grant execute on function public.pack_draw_plan(text, text, numeric, int, text) to authenticated;

commit;
