-- Invalidate the COMPANY, not the row's own facility.
--
-- 20261026000013 read facility_id off the changed row and dirtied that one
-- facility. For most inputs that is right, and for two it is WRONG in the
-- dangerous direction -- under-invalidation, which means a plan that is quietly
-- wrong forever with nothing to report it.
--
-- `recipe_components` and `products` both HAVE a facility_id column, and the
-- plan never reads either one. Components reach the plan through
-- `recipe_demand_source` (keyed on recipe, not facility), and products reach it
-- through `orders.facility_id`. So the facility that owns the changed row is not
-- necessarily the facility whose plan moved: a recipe with
-- `roast_recipes.facility_id IS NULL` fans out to EVERY facility of its company,
-- and a product can be ordered by any of them. Prod has no such recipe today,
-- and that is not a reason -- the join explicitly handles NULL, so behaviour
-- comes from the schema, never from one tenant's current values.
--
-- `roast_recipes` has the same shape through its own NULL facility_id, and
-- `facilities` changes the facility x recipe cross product for the whole
-- company when a facility is added, removed, or re-pointed.
--
-- Rather than keep a per-table list of which grain applies -- a list that is
-- wrong the moment someone adds a column -- every input now dirties the whole
-- company. The asymmetry makes this easy: over-invalidating costs one 650ms
-- recompute per facility, and a company has one or two, against a budget that
-- just went from 147 hours a day to minutes. Under-invalidating costs
-- correctness, and costs it silently. There is no version of this where guessing
-- the narrower grain is worth it.
--
-- The origin pool is why the facility grain could never have been narrowed
-- further anyway: `PARTITION BY company_id, facility_id, origin_id` couples
-- every recipe in a facility sharing an origin (41 such pairs on prod, one
-- shared by 15 recipes), so those recipes cannot be recomputed one at a time.
--
-- Still changes NO read path.

begin;

-- Resolve the company from whatever the row carries, then dirty all of it.
create or replace function public.roast_plan_touch()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  j     jsonb;
  v_fac text;
  v_co  text;
begin
  foreach j in array array[
    case when tg_op <> 'DELETE' then to_jsonb(new) end,
    case when tg_op <> 'INSERT' then to_jsonb(old) end
  ]
  loop
    if j is null then continue; end if;

    v_co  := j ->> 'company_id';
    v_fac := j ->> 'facility_id';

    -- A row may carry a facility and no company (recipe_weekly_targets), so
    -- look the company up from the facility before giving up on it.
    if v_co is null and v_fac is not null then
      select f.company_id into v_co from public.facilities f where f.facility_id = v_fac;
    end if;

    if v_co is not null then
      perform public.roast_plan_mark_company_dirty(v_co, tg_table_name);
    elsif v_fac is not null then
      -- A facility with no company row to resolve: dirty it alone rather than
      -- dropping the change on the floor.
      perform public.roast_plan_mark_dirty(v_fac, tg_table_name);
    end if;
  end loop;
  return null;
end;
$function$;

-- Same correction for the one input with neither column: resolve the company
-- through the roast, not just the facility.
create or replace function public.roast_plan_touch_via_roast_log()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_co text;
begin
  for v_co in
    select distinct rl.company_id
      from public.roast_log rl
     where rl.roast_log_id in (
             (case when tg_op <> 'DELETE' then new.roast_log_id end),
             (case when tg_op <> 'INSERT' then old.roast_log_id end)
           )
       and rl.company_id is not null
  loop
    perform public.roast_plan_mark_company_dirty(v_co, 'roast_log_recipes');
  end loop;
  return null;
end;
$function$;

do $$
declare
  n_trig  int;
  n_dirty int;
  v_co    text;
  v_fac   int;
begin
  select count(*) into n_trig
    from pg_trigger
   where tgname like '%_roast_plan_dirty' and not tgisinternal;
  if n_trig <> 13 then
    raise exception 'expected 13 roast_plan invalidation triggers, found %', n_trig;
  end if;

  -- Prove the WIDER grain, which is the whole point of this migration: a
  -- recipe_components write must dirty every facility of that company, not the
  -- one whose id happens to sit on the row.
  select r.company_id into v_co
    from public.recipe_components rc
    join public.roast_recipes r on r.recipe_id = rc.recipe_id
   where r.company_id is not null
   limit 1;

  if v_co is null then
    raise notice 'no recipe_components row to probe; grain assertion skipped';
  else
    select count(*) into v_fac from public.facilities where company_id = v_co;
    delete from public.roast_plan_dirty;

    update public.recipe_components set percentage = percentage
     where recipe_id in (select recipe_id from public.roast_recipes where company_id = v_co)
       and ctid = (select min(ctid) from public.recipe_components
                    where recipe_id in (select recipe_id from public.roast_recipes where company_id = v_co));

    select count(distinct facility_id) into n_dirty from public.roast_plan_dirty;
    if n_dirty <> v_fac then
      raise exception
        'a recipe_components write dirtied % facility(ies) of a company that has %; the grain is still too narrow',
        n_dirty, v_fac;
    end if;
    raise notice 'grain proven: one recipe_components write dirtied all % facility(ies) of the company', n_dirty;
    delete from public.roast_plan_dirty;
  end if;
end $$;

commit;
