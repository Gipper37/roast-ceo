-- Bagging a post-blend: the coffee is on the children's roasts.
--
-- Step 2 of the post-blend wiring, and like step 1 it must land before any
-- product moves.
--
-- `pack_draw_plan` builds the shelf of roasts a pack run can draw from with
-- `where r.recipe_id = p_recipe_id`, and picks which drums to take with a loop
-- over `recipe_components.coffee_item`. A post-blend parent is never roasted
-- and holds no green directly, so both come back empty: every Maui Blend pack
-- run would report a FULL SHORTFALL and write no `pack_run_source` rows, which
-- is the recall chain.
--
-- Two changes, both no-ops for an ordinary recipe:
--
--   the shelf   also accepts roasts logged against the recipe's component
--               recipes. The subquery is empty unless the recipe has
--               component_recipe_id rows, which no production recipe does yet.
--   a new branch draws a parent from its CHILDREN by recipe, in their shares,
--               ahead of the existing origin-ratio branch, which is untouched.
--
-- 🔴 BY RECIPE, NOT BY ORIGIN, and that distinction is the point. MB DK and
-- MB LT are PRE-BLENDS: their drums are mixed green charged as one, so a drum
-- carries no single origin for a ratio to match. Resolving the parent's 50/50
-- down to green and matching on origin_id finds nothing, and the draw falls
-- through to the FIFO top-up, which would put five pounds of dark roast in a
-- bag that is supposed to be half light. The proof caught exactly that: a test
-- parent came back `basis: ratio` with zero lines.
--
-- 🔴 The new branch is gated on having `component_recipe_id` rows, NOT on
-- roast_type, so it cannot capture an ordinary Post-Blend, whose components
-- are origins and whose existing behaviour is untouched.
--
-- 🔴 ONE LEVEL, matching `recipe_effective_green` and `recipe_demand_source`.
-- A grandchild's drums are deliberately not reachable.
--
-- Body taken from the LIVE definition and patched by script at two sites,
-- never retyped.

begin;

CREATE OR REPLACE FUNCTION public.pack_draw_plan(p_company_id text, p_recipe_id text, p_lbs numeric, p_days integer DEFAULT 180, p_facility_id text DEFAULT NULL::text, p_only_roast_log_ids text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_type        text;
  v_draw        jsonb := '[]'::jsonb;
  v_taken       numeric := 0;
  v_need        numeric;
  v_basis       text := 'fifo';
  v_restricted  boolean := p_only_roast_log_ids is not null
                           and cardinality(p_only_roast_log_ids) > 0;
  v_unavailable jsonb := '[]'::jsonb;
  c             record;
  b             record;
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'Not your company.' using errcode = 'insufficient_privilege';
  end if;
  if coalesce(p_lbs, 0) <= 0 or p_recipe_id is null then
    return jsonb_build_object('draw', '[]'::jsonb, 'taken', 0,
                              'shortfall', greatest(coalesce(p_lbs, 0), 0), 'basis', 'none',
                              'restricted', v_restricted, 'unavailable', '[]'::jsonb);
  end if;

  select roast_type into v_type from public.roast_recipes
   where recipe_id = p_recipe_id and company_id = p_company_id;

  -- Resolved here, once, rather than handed out as an id for a caller to look
  -- up: coffee_inventory.origin is the name, rl.origin_id is a foreign key.
  --
  -- The restriction lands HERE, on the shelf itself, rather than on the two
  -- selection loops below. Filtering the shelf is what makes "these drums and
  -- no others" true for every path through this function at once -- the ratio
  -- loop, the top-up loop, and the shortfall that falls out of both.
  create temp table _avail on commit drop as
    select r.roast_log_id, r.roast_date, r.remaining_lbs, rl.origin_id,
           r.recipe_id,
           coalesce(ci.origin, nullif(rl.coffee_name_snapshot, '')) as origin_name
      from public.roasts_available_to_pack(p_company_id, p_days, p_facility_id) r
      join public.roast_log rl on rl.roast_log_id = r.roast_log_id
      left join public.coffee_inventory ci on ci.origin_id = rl.origin_id
     where (r.recipe_id = p_recipe_id
            -- A post-blend parent is never roasted; its coffee sits on roasts
            -- logged against its component recipes. The subquery is empty for
            -- an ordinary recipe, so the shelf is unchanged for everyone else.
            or r.recipe_id in (select rc.component_recipe_id
                                 from public.recipe_components rc
                                where rc.recipe_id = p_recipe_id
                                  and rc.component_recipe_id is not null))
       and r.remaining_lbs > 0.01
       and (not v_restricted or r.roast_log_id = any(p_only_roast_log_ids))
     order by r.roast_date asc;

  -- Named and not on the shelf: already bagged, emptied, out of the p_days
  -- window, at another facility, on another recipe, or not this company's at
  -- all. The screen needs to say WHICH, so return the ids rather than a flag.
  if v_restricted then
    select coalesce(jsonb_agg(x), '[]'::jsonb) into v_unavailable
      from unnest(p_only_roast_log_ids) x
     where x not in (select roast_log_id from _avail);
  end if;

  -- ── A parent drawn from its children, in their shares ───────────────────
  --
  -- 🔴 BY RECIPE, NOT BY ORIGIN, and that distinction is the whole reason this
  -- branch exists. MB DK and MB LT are PRE-BLENDS: their drums are mixed green
  -- charged as one, so a drum carries no single origin to match a ratio
  -- against. Matching the parent's 50/50 on `origin_id` finds nothing and the
  -- draw falls through to FIFO, which would happily put five pounds of dark
  -- roast in a bag that is supposed to be half light.
  --
  -- So a recipe built from recipes takes its shares from the CHILDREN'S
  -- roasts: half the pounds off MB DK's drums, half off MB LT's.
  if exists (select 1 from public.recipe_components
              where recipe_id = p_recipe_id
                and component_recipe_id is not null
                and coalesce(percentage, 0) > 0) then
    v_basis := 'recipe-ratio';
    for c in
      select component_recipe_id as child_recipe_id, percentage
        from public.recipe_components
       where recipe_id = p_recipe_id
         and component_recipe_id is not null
         and coalesce(percentage, 0) > 0
       order by percentage desc
    loop
      v_need := round(p_lbs * c.percentage, 2);
      for b in select * from _avail
                where recipe_id = c.child_recipe_id and remaining_lbs > 0.01
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
            'reason', 'recipe ratio');
          update _avail set remaining_lbs = remaining_lbs - v_take where roast_log_id = b.roast_log_id;
          v_need  := v_need - v_take;
          v_taken := v_taken + v_take;
        end;
      end loop;
    end loop;
  elsif v_type = 'Post-Blend' and exists (
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
    for b in select * from _avail where remaining_lbs > 0.01
                order by roast_date asc
    loop
      exit when v_need <= 0.001;
      declare v_take numeric := least(b.remaining_lbs, v_need);
      begin
        v_draw := v_draw || jsonb_build_object(
          'roast_log_id', b.roast_log_id, 'lbs_used', v_take,
          'roast_date', b.roast_date, 'origin_id', b.origin_id,
          'origin_name', b.origin_name,
          'reason', case when v_restricted then 'named'
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
               -- max(): 'topped up' beats 'ratio' beats 'named' beats 'fifo',
               -- so a folded row names the weaker basis rather than flattering
               -- itself.
               'reason',       max(e->>'reason')) as d
        from jsonb_array_elements(v_draw) e
       group by e->>'roast_log_id'
    ) folded;

  return jsonb_build_object(
    'draw', v_draw, 'taken', round(v_taken, 2),
    'shortfall', round(greatest(p_lbs - v_taken, 0), 2), 'basis', v_basis,
    -- True when the bagger named drums, so the screen can explain a shortfall
    -- as "you named 20.5 lbs" rather than "the shelf is empty".
    'restricted', v_restricted,
    'unavailable', v_unavailable);
end;
$function$;

do $$
declare n int;
begin
  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'pack_draw_plan'
     and pg_get_functiondef(p.oid) like '%recipe-ratio%'
     and pg_get_functiondef(p.oid) like '%rc.component_recipe_id is not null%';
  if n <> 1 then
    raise exception 'pack_draw_plan needs BOTH the shelf widening and the recipe-ratio branch, found %', n;
  end if;
end $$;

commit;
