-- A bagger can bag against the drum in front of them.
--
-- For a pre-blend the components are already mixed, so one roast is one
-- physical batch with a route sheet (a bin card) on it. The owner: "for pre
-- blend the bagger may be pulling a batch lot and bagging against that ... it
-- would have to force consumption of that bin code, not fifo the bagged
-- coffee if the bagger chose a bin code to bag against."
--
-- pack_draw_plan gains an optional p_pin_roast_log_id. When given, that batch
-- sorts first in every place a batch is chosen; FIFO then covers only what the
-- batch could not, because you cannot take 100 lbs out of an 80 lb drum. The
-- returned object gains 'pinned', which is false when the batch was asked for
-- and has since been bagged, so the screen can say so rather than silently
-- reverting to oldest-first.
--
-- Why pin the planner and not pass named sources to close_pack_run: that path
-- exists and is already wired, but it performs no remaining-lbs check. A
-- client-computed weight could draw a batch past zero, and every later draw
-- filters remaining_lbs > 0.01 -- the overdrawn batch would disappear from the
-- system with no error. Pinning here keeps the existing least(remaining, need)
-- ceiling.
--
-- Additive: the argument is optional and every existing caller is unchanged.
-- None of this is on prod yet; the whole pack-run chain is in the pending
-- release.

begin;

CREATE OR REPLACE FUNCTION public.pack_draw_plan(p_company_id text, p_recipe_id text, p_lbs numeric, p_days integer DEFAULT 180, p_facility_id text DEFAULT NULL::text, p_pin_roast_log_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_type  text;
  v_draw  jsonb := '[]'::jsonb;
  v_taken numeric := 0;
  v_need  numeric;
  v_basis text := 'fifo';
  v_pin_ok boolean := false;
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

  -- A bagger standing at a drum with a route sheet on it is not asking the
  -- system to choose; they are telling it which coffee is in their hands.
  -- The pinned batch is drawn first and FIFO only covers whatever it cannot.
  -- Pinning the PLANNER rather than passing named sources to close_pack_run
  -- is deliberate: that override performs no remaining-lbs check, so a
  -- client-computed figure could overdraw a batch past zero, and every later
  -- draw filters on remaining_lbs > 0.01 -- the batch would quietly vanish.
  -- Here the existing least(remaining, need) still applies.
  if p_pin_roast_log_id is not null then
    select exists (select 1 from _avail where roast_log_id = p_pin_roast_log_id)
      into v_pin_ok;
  end if;

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
                order by (roast_log_id = p_pin_roast_log_id) desc, roast_date asc
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
    for b in select * from _avail where remaining_lbs > 0.01
                order by (roast_log_id = p_pin_roast_log_id) desc, roast_date asc
    loop
      exit when v_need <= 0.001;
      declare v_take numeric := least(b.remaining_lbs, v_need);
      begin
        v_draw := v_draw || jsonb_build_object(
          'roast_log_id', b.roast_log_id, 'lbs_used', v_take,
          'roast_date', b.roast_date, 'origin_id', b.origin_id,
          'origin_name', b.origin_name,
          'reason', case when b.roast_log_id = p_pin_roast_log_id then 'pinned'
                          when v_basis = 'ratio' then 'topped up' else 'fifo' end);
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
    'shortfall', round(greatest(p_lbs - v_taken, 0), 2), 'basis', v_basis,
    -- false when a batch was asked for and is no longer available, so the
    -- screen can say so instead of quietly serving FIFO.
    'pinned', (p_pin_roast_log_id is not null and v_pin_ok));
end;
$function$;

revoke all on function public.pack_draw_plan(text, text, numeric, integer, text, text) from public;
grant execute on function public.pack_draw_plan(text, text, numeric, integer, text, text) to authenticated;

commit;
