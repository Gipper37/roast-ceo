-- A generic plan cannot fold an optional parameter.
--
-- observed_retention is the measured-yield tier of get_retention_factor. It
-- selected its rows with the optional-parameter idiom:
--
--     and (p_recipe_id   is null or rl.recipe_id   = p_recipe_id)
--     and (p_facility_id is null or rl.facility_id = p_facility_id)
--
-- That reads as "filter if given", and with the parameter known at plan time
-- the planner folds it away and uses idx_roast_log_recipe_date. The trouble is
-- the plan it gets is NOT always planned with the value known. Measured on
-- production, forcing each case:
--
--     plan_cache_mode = force_generic_plan, `p is null or col = p`
--         Seq Scan on roast_log   Buffers: shared hit=1519   8.07 ms
--     plan_cache_mode = force_generic_plan, `col = p`
--         Bitmap Index Scan on idx_roast_log_recipe_date
--                                 Buffers: shared hit=665    3.16 ms
--
-- A generic plan cannot know the parameter is non-null, so it cannot discard
-- the `is null` arm, so it cannot use the index and reads the whole table. This
-- function was `language sql` WITH `SET search_path`, and a SET clause blocks
-- inlining, so every call went through SPI as a cached plan -- and a cached SPI
-- plan switches to generic after five executions. So the first few calls of a
-- session were fast and every call after that scanned 15 MB:
--
--     the live function, 200 calls over real recipes      7.33 ms/call
--     the same shape, correlated so it cannot fold        7.00 ms/call
--     explicit equality, same correlation                 0.27 ms/call
--
-- 27x, and it is called from inside get_origin_roasted_cost_on_date's SUM --
-- once per roast row. It does not fire there today only because COALESCE
-- short-circuits and 0 of 18,904 roast_log rows have both
-- measured_roasted_weight and roasted_weight null. The first roast logged with
-- neither turns every origin-cost call into 7.33 ms x its roast rows.
--
-- The fix is to give each case its own statement, so the predicate a generic
-- plan sees is a plain equality. The four branches are the SAME expression,
-- the SAME 0.75-0.92 window and the SAME count(*) >= 10 threshold as before;
-- only the WHERE differs, and only by which equality is present. Nothing about
-- which number is returned changes -- asserted below over every recipe and
-- every facility in the data.

begin;

create or replace function public.observed_retention(
  p_recipe_id   text default null::text,
  p_facility_id text default null::text
)
returns numeric
language plpgsql
stable
set search_path to 'public', 'pg_temp'
as $function$
declare
  v numeric;
begin
  if p_recipe_id is not null and p_facility_id is not null then
    select round(avg(r), 4) into v
      from (
        select coalesce(
                 rl.measured_roasted_weight,
                 case when rl.external_roast_id is not null then rl.roasted_weight end
               ) / nullif(rl.charge_weight_lbs, 0) as r
          from public.roast_log rl
         where rl.charge_weight_lbs > 0
           and rl.recipe_id   = p_recipe_id
           and rl.facility_id = p_facility_id
      ) x
     where x.r between 0.75 and 0.92
    having count(*) >= 10;

  elsif p_recipe_id is not null then
    select round(avg(r), 4) into v
      from (
        select coalesce(
                 rl.measured_roasted_weight,
                 case when rl.external_roast_id is not null then rl.roasted_weight end
               ) / nullif(rl.charge_weight_lbs, 0) as r
          from public.roast_log rl
         where rl.charge_weight_lbs > 0
           and rl.recipe_id = p_recipe_id
      ) x
     where x.r between 0.75 and 0.92
    having count(*) >= 10;

  elsif p_facility_id is not null then
    select round(avg(r), 4) into v
      from (
        select coalesce(
                 rl.measured_roasted_weight,
                 case when rl.external_roast_id is not null then rl.roasted_weight end
               ) / nullif(rl.charge_weight_lbs, 0) as r
          from public.roast_log rl
         where rl.charge_weight_lbs > 0
           and rl.facility_id = p_facility_id
      ) x
     where x.r between 0.75 and 0.92
    having count(*) >= 10;

  else
    select round(avg(r), 4) into v
      from (
        select coalesce(
                 rl.measured_roasted_weight,
                 case when rl.external_roast_id is not null then rl.roasted_weight end
               ) / nullif(rl.charge_weight_lbs, 0) as r
          from public.roast_log rl
         where rl.charge_weight_lbs > 0
      ) x
     where x.r between 0.75 and 0.92
    having count(*) >= 10;
  end if;

  return v;
end;
$function$;

comment on function public.observed_retention(text, text) is
  'Measured roast yield: mean roasted/charge over roasts inside the plausible '
  '0.75-0.92 window, NULL below 10 samples. One branch per argument '
  'combination on purpose -- the optional-parameter idiom cannot use '
  'idx_roast_log_recipe_date under a generic plan and scanned the whole table.';

-- Does the new body answer exactly as the old one did? Compared against the
-- OLD predicate form, inline, for every recipe and every facility present.
-- With no roast rows there is nothing to compare and this passes vacuously,
-- so it is safe on staging; on production it is 118 real keys.
do $$
declare
  v_bad integer;
begin
  select count(*) into v_bad
    from (
      select public.observed_retention(k.recipe_id, null) as a,
             (select round(avg(r), 4)
                from (
                  select coalesce(
                           rl.measured_roasted_weight,
                           case when rl.external_roast_id is not null then rl.roasted_weight end
                         ) / nullif(rl.charge_weight_lbs, 0) as r
                    from public.roast_log rl
                   where rl.charge_weight_lbs > 0
                     and (k.recipe_id is null or rl.recipe_id = k.recipe_id)
                ) x
               where x.r between 0.75 and 0.92
              having count(*) >= 10) as b
        from (select distinct recipe_id from public.roast_log where recipe_id is not null) k

      union all

      select public.observed_retention(null, k.facility_id),
             (select round(avg(r), 4)
                from (
                  select coalesce(
                           rl.measured_roasted_weight,
                           case when rl.external_roast_id is not null then rl.roasted_weight end
                         ) / nullif(rl.charge_weight_lbs, 0) as r
                    from public.roast_log rl
                   where rl.charge_weight_lbs > 0
                     and (k.facility_id is null or rl.facility_id = k.facility_id)
                ) x
               where x.r between 0.75 and 0.92
              having count(*) >= 10)
        from (select distinct facility_id from public.roast_log where facility_id is not null) k
    ) z
   where z.a is distinct from z.b;

  if v_bad > 0 then
    raise exception
      'observed_retention changed its answer for % recipe/facility keys', v_bad;
  end if;
end $$;

commit;
