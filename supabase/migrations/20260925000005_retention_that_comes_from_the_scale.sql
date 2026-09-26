-- Retention that comes from the scale, not from a number somebody typed once.
--
-- get_retention_factor resolved recipe override -> company parameter ->
-- standard parameter -> 0.82. Three of those four are guesses, and on MCR the
-- 0.82 default is wrong for nearly every recipe it is used for:
--
--     MB LT     0.8440 (n=197)     Flavor        0.8459 (n=57)
--     MB DK     0.8165 (n=178)     French Roast  0.8130 (n=21)
--     Espresso  0.8281 (n=79)      Lokelani      0.8363 (n=42)
--
-- Retention DIVIDES into cost, so a 0.024 error on MB LT is ~3% of its coffee
-- COGS, in the direction of thinking it costs more than it does.
--
-- 🔴 THE CIRCULARITY TRAP, which makes the naive version of this useless:
-- 98.3% of all roasted_weight values (17,830 of 18,144) are EXACTLY
-- charge x the resolved retention, because trg_stamp_roasted_weight computes
-- them that way. Averaging roasted_weight therefore returns the retention you
-- already had, and looks like it is working. Only two sources are honest:
--
--   measured_roasted_weight                         a real scale reading
--   roasted_weight WHERE external_roast_id IS NOT NULL   the importer's own
--                                                   drop weight, which the
--                                                   trigger explicitly keeps
--
-- On MCR that channel is 1,000 of 1,071 roasts — 585 measured, 415 imported.
--
-- 🔴 AND WHY THE LOOP STAYS OPEN: trg_stamp_roasted_weight does NOT call
-- get_retention_factor. It reads company_parameters and standard_parameters
-- directly. That duplication is what keeps the estimator out of its own input,
-- so it must NOT be "tidied up" into calling this resolver — doing that would
-- close the loop for real and the observed value would slowly eat itself.
--
-- Band [0.75, 0.92]: on MCR it admits 997 of 1,000 honest readings and rejects
-- 3. Minimum 10 readings before the measurement is trusted at all.

begin;

create or replace function public.observed_retention(
  p_recipe_id   text default null,
  p_facility_id text default null
)
returns numeric
language sql
stable
security invoker
set search_path to public, pg_temp
as $function$
  select round(avg(r), 4)
    from (
      select coalesce(
               rl.measured_roasted_weight,
               case when rl.external_roast_id is not null then rl.roasted_weight end
             ) / nullif(rl.charge_weight_lbs, 0) as r
        from public.roast_log rl
       where rl.charge_weight_lbs > 0
         and (p_recipe_id   is null or rl.recipe_id   = p_recipe_id)
         and (p_facility_id is null or rl.facility_id = p_facility_id)
    ) x
   where x.r between 0.75 and 0.92
  having count(*) >= 10;
$function$;

comment on function public.observed_retention(text, text) is
  'Measured retention from real drop weights only (measured_roasted_weight, or an imported roast_weight). NULL below 10 readings. Never reads a roasted_weight the retention trigger computed, or it would return its own input.';

CREATE OR REPLACE FUNCTION public.get_retention_factor(p_facility_id text, p_recipe_id text DEFAULT NULL::text)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_retention numeric;
BEGIN
  -- Tier 1: recipe-level override
  IF p_recipe_id IS NOT NULL THEN
    SELECT retention_factor INTO v_retention
    FROM roast_recipes
    WHERE recipe_id = p_recipe_id
      AND retention_factor IS NOT NULL
      AND retention_factor > 0
    LIMIT 1;
  END IF;

  -- Tier 1.5: what this recipe ACTUALLY yields, measured.
  -- Beats the company default because a measurement of THIS recipe outranks a
  -- number somebody typed for the whole roastery — but never beats tier 1,
  -- which is a person saying otherwise on purpose.
  IF v_retention IS NULL AND p_recipe_id IS NOT NULL THEN
    SELECT public.observed_retention(p_recipe_id, NULL) INTO v_retention;
  END IF;

  -- Tier 2: facility/company parameter
  IF v_retention IS NULL OR v_retention = 0 THEN
    SELECT value_number INTO v_retention
    FROM company_parameters
    WHERE parameter_id = '1de271df'
      AND facility_id = p_facility_id
    LIMIT 1;
  END IF;

  -- Tier 2.5: what this FACILITY actually yields, pooled across recipes.
  -- Below the company parameter on purpose: an explicit general setting beats
  -- a general measurement, while a specific measurement (1.5) beats both.
  IF v_retention IS NULL OR v_retention = 0 THEN
    SELECT public.observed_retention(NULL, p_facility_id) INTO v_retention;
  END IF;

  -- Tier 3: standard parameters
  IF v_retention IS NULL OR v_retention = 0 THEN
    SELECT amount INTO v_retention
    FROM standard_parameters
    WHERE parameters_id = '1de271df'
    LIMIT 1;
  END IF;

  -- Tier 4: hardcoded default
  IF v_retention IS NULL OR v_retention = 0 THEN
    v_retention := 0.82;
  END IF;

  RETURN v_retention;
END;
$function$;


do $verify$
declare v_obs numeric; v_n int; v_bad int;
begin
  -- 1. It must refuse to answer on thin evidence.
  if public.observed_retention('a-recipe-that-does-not-exist', null) is not null then
    raise exception 'observed_retention invented a number from no roasts';
  end if;

  -- 2. Anything it does return must be inside the physical band.
  select count(*) into v_bad
    from public.roast_recipes rr
   where public.observed_retention(rr.recipe_id, null) not between 0.75 and 0.92;
  if v_bad > 0 then
    raise exception '% recipe(s) produced a retention outside the band', v_bad;
  end if;

  -- 3. 🔴 The anti-circularity invariant: the estimator must never be able to
  --    read a weight the retention trigger computed. If this ever fails,
  --    somebody has pointed trg_stamp_roasted_weight at get_retention_factor.
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'trg_stamp_roasted_weight'
       and pg_get_functiondef(p.oid) ilike '%get_retention_factor%')
  then
    raise exception 'trg_stamp_roasted_weight now calls get_retention_factor — the observed retention would feed itself';
  end if;

  select count(*) into v_n from public.roast_recipes rr
   where public.observed_retention(rr.recipe_id, null) is not null;
  raise notice 'retention measured for % recipe(s); the rest fall through to the typed defaults', v_n;
end $verify$;

commit;
