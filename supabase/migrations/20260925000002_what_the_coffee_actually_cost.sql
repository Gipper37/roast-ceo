-- What the coffee ACTUALLY cost, beside what it would cost to buy today.
--
-- The recipe page has only ever shown a REPLACEMENT cost: each component's
-- latest purchase price, retention-adjusted. On MCR that number runs 20-40%
-- above what the last twelve real roasts actually cost:
--
--     Espresso Decaf   actual 5.28   page 7.41   +40.2%
--     Flavor           actual 4.68   page 5.90   +25.9%
--     Espresso         actual 4.80   page 5.97   +24.6%
--     French Roast     actual 5.03   page 6.06   +20.5%
--
-- Both numbers are right and they answer different questions. Pricing off the
-- replacement figure alone quietly assumes you already re-bought at today's
-- price. This function supplies the other half.
--
-- WHICH ROASTS MAY COUNT — the whole job is here, because the naive average is
-- badly wrong:
--   * A lot with no purchase cost is COALESCEd to 0 by the generated column
--     roast_log_lot_consumption.lot_cost, so the roast reports a cost of zero
--     rather than NULL. 45 MCR roasts and 22 UK roasts read exactly 0; another
--     126 UK roasts read under a dollar because only shipping was known. A
--     magnitude threshold cannot separate these from a genuinely cheap roast,
--     and one MCR roast is 50% unpriced yet reports a wholly believable
--     $19.50/lb. So the filter is CAUSAL: no ledger row may be missing its
--     green cost.
--   * The ledger does not always cover the charge. Where it covers only part,
--     the cost is divided by the whole roasted weight and comes out low. So the
--     consumed pounds must reconcile to the charge within 2%.
--
-- POUNDS-WEIGHTED, not a plain mean: a 5 lb sample roast and a 75 lb production
-- roast are not equal evidence about what a pound costs.
--
-- Twelve qualifying roasts rather than a fixed window, because a recipe roasted
-- weekly and one roasted twice a year both need an answer. The span comes back
-- with the number so the reader can see whether "last 12" means a fortnight or
-- half a year, and the excluded count comes back so the card can say what it
-- left out rather than quietly shrinking its own denominator.

begin;

create or replace function public.recipe_actual_cost_lb(p_recipe_id text)
returns table (
  cost_lb        numeric,
  roasts_used    integer,
  roasts_skipped integer,
  first_roast    timestamptz,
  last_roast     timestamptz
)
language sql
stable
security invoker   -- RLS on roast_log confines this to the caller's tenant
set search_path to public, pg_temp
as $function$
  with per_roast as (
    select rl.roast_log_id,
           rl.roast_date,
           sum(rlc.lot_cost)                                       as green_cost,
           coalesce(rl.measured_roasted_weight, rl.roasted_weight) as roasted_lbs,
           bool_or(rlc.green_cost_lb is null)                      as unpriced,
           abs(sum(rlc.lbs_consumed) - rl.charge_weight_lbs)
             / nullif(rl.charge_weight_lbs, 0)                     as coverage_gap
      from public.roast_log rl
      join public.roast_log_lot_consumption rlc
        on rlc.roast_log_id = rl.roast_log_id
     where rl.recipe_id = p_recipe_id
       and rl.charge_weight_lbs > 0
     group by rl.roast_log_id, rl.roast_date,
              rl.measured_roasted_weight, rl.roasted_weight, rl.charge_weight_lbs
  ), judged as (
    select *,
           (not unpriced and coalesce(coverage_gap, 1) <= 0.02
            and coalesce(roasted_lbs, 0) > 0 and green_cost > 0) as usable
      from per_roast
  ), kept as (
    select *, row_number() over (order by roast_date desc) as rn
      from judged where usable
  )
  select round(sum(k.green_cost) / nullif(sum(k.roasted_lbs), 0), 4)          as cost_lb,
         count(k.*)::int                                                      as roasts_used,
         (select count(*) from judged where not usable)::int                  as roasts_skipped,
         min(k.roast_date)                                                    as first_roast,
         max(k.roast_date)                                                    as last_roast
    from kept k
   where k.rn <= 12;
$function$;

comment on function public.recipe_actual_cost_lb(text) is
  'Pounds-weighted cost per roasted lb over the last 12 roasts whose lot ledger is fully priced and covers the charge within 2%. Security invoker: RLS scopes it to the caller.';

do $verify$
declare r record; v_bad int;
begin
  -- Invariants, not a tenant: the function must never return a cost that the
  -- poisoned rows would have produced, and never count a roast it skipped.
  select count(*) into v_bad
    from public.roast_recipes rr
   cross join lateral public.recipe_actual_cost_lb(rr.recipe_id) f
   where f.roasts_used > 0
     and (f.cost_lb is null or f.cost_lb <= 0 or f.roasts_used > 12);
  if v_bad > 0 then
    raise exception '% recipe(s) returned an impossible actual cost', v_bad;
  end if;

  -- A recipe with no qualifying roast must return no number rather than zero.
  select count(*) into v_bad
    from public.roast_recipes rr
   cross join lateral public.recipe_actual_cost_lb(rr.recipe_id) f
   where f.roasts_used = 0 and f.cost_lb is not null;
  if v_bad > 0 then
    raise exception '% recipe(s) invented a cost from no roasts', v_bad;
  end if;

  select count(*) into v_bad from public.roast_recipes rr
   cross join lateral public.recipe_actual_cost_lb(rr.recipe_id) f where f.roasts_used >= 3;
  raise notice 'actual cost available for % recipe(s) at n>=3', v_bad;
end $verify$;

commit;
