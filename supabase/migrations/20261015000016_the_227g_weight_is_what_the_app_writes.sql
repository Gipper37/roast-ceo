-- 227 g is stored as the app's own conversion, so re-typing it changes nothing.
--
-- `size.weight` for Social Hour UK's `uk-227g` holds 0.50044933515967210824,
-- which is 227 / 453.59237 -- the TRUE gram-to-pound factor. The app's
-- converter does not produce that number:
--
--   lib/units.ts:  LBS_TO_KG = 0.453592
--                  toDbLbs(0.227, 'kg') = 0.227 * (1 / 0.453592)
--                                       = 0.5004497433817175
--
-- 20261004000006 was told to use the true factor. That was my instruction and
-- it was wrong, and the note has been waiting in the open list since, marked
-- "apply when the case workflow lands". It has landed.
--
-- 🔴 THE POINT IS NOT THE WEIGHT, IT IS IDEMPOTENCE. The difference is
-- 4.08e-7 lb, which is 0.185 mg -- below any scale in any roastery and below
-- every cost and shipping figure it feeds. What matters is that a UK roaster
-- who opens the size and re-types 227 in the grams box tomorrow writes
-- 0.5004497433817175 and the row MOVES. From 20261015000014 that is no longer
-- a quiet one-row drift: the weight cascades to `uk-case6`, whose weight is
-- derived, and then touches the products on the two sizes to refresh their
-- cached weight and cost chain. There are 95 of them, 61 active and 34
-- archived; only the active ones can be refreshed, because an archived
-- variant's numbers are frozen on purpose. A no-op edit that triggers a
-- cascade is worth one migration to prevent.
--
-- WHY THE LITERAL. The note says to compute it from the same constant rather
-- than hardcode it, and that is right in TypeScript. In SQL it is not
-- available: Postgres numeric is exact decimal and would give
-- 0.227 / 0.453592 to as many digits as it is asked for, while what has to be
-- stored is the shortest decimal that round-trips the IEEE double the app
-- actually sends -- `JSON.stringify(0.227 * (1 / 0.453592))` is exactly
-- "0.5004497433817175", 16 digits, no more. A longer or shorter expansion
-- would not equal what the app writes, which is the entire objective. So the
-- literal IS the app's output, and the derivation is recorded above it.
--
-- `uk-case6` is deliberately NOT written here. Its weight is derived by
-- `derive_case_size_weight` (20261015000014), and the whole point of that
-- trigger is that the case follows its base. Setting it by hand would prove
-- nothing and would hide it if the trigger were ever dropped.
--
-- Display stays on 453.59237: showing "227.0 g" needs the true factor, and
-- that is a different job from storage. See the open list's note.

begin;

do $pre$
DECLARE
  v_before numeric;
BEGIN
  select weight into v_before from public.size where size_id = 'uk-227g';
  if v_before is null then
    raise notice 'uk-227g is not on this database, so there is nothing to correct';
  else
    raise notice 'uk-227g: % -> 0.5004497433817175', v_before;
  end if;
END;
$pre$;

update public.size
   set weight = 0.5004497433817175
 where size_id = 'uk-227g'
   and weight is distinct from 0.5004497433817175;

do $verify$
DECLARE
  v_base  numeric;
  v_case  numeric;
  v_stale int;
BEGIN
  select weight into v_base from public.size where size_id = 'uk-227g';
  if v_base is null then
    raise notice 'nothing to verify on this database';
    return;
  end if;

  if v_base is distinct from 0.5004497433817175 then
    raise exception 'uk-227g is %, not the value the app writes', v_base;
  end if;

  -- 🔴 And the cascade did its job, which is the real assertion here: this is
  -- the first time 20261015000014 has been exercised on live data.
  select weight into v_case from public.size where size_id = 'uk-case6';
  if v_case is not null then
    if v_case is distinct from v_base * 6 then
      raise exception 'uk-case6 is % but six 227g bags are %', v_case, v_base * 6;
    end if;
  end if;

  -- Every ACTIVE product on either size now caches the new weight.
  --
  -- 🔴 ACTIVE, and the first draft said every product. `uk-227g` carries 74
  -- products (47 active, 27 archived) and `uk-case6` carries 21 (14 active, 7
  -- archived) -- 95 in all, 34 of them archived. An archived variant's cached
  -- weight is frozen on purpose: `update_product_total_cogs` returns before
  -- the assignment for a row that is inactive and was already inactive, which
  -- is what keeps its last-active COGS readable. So the unqualified count
  -- would have found 34 and raised, rolling this migration back and 17 with
  -- it. See the same correction in 20261015000014.
  select count(*) into v_stale
    from public.products p
    join public.size s on s.size_id = p.size
   where (s.size_id = 'uk-227g' or s.base_size_id = 'uk-227g')
     and coalesce(p.is_active, true)
     and p.weight_lbs is distinct from s.weight;
  if v_stale > 0 then
    raise exception '% ACTIVE products on 227g or its case still cache the old weight', v_stale;
  end if;

  raise notice '227g is now what the app writes; its case and % active product(s) followed (% archived keep their frozen weight)',
    (select count(*) from public.products p join public.size s on s.size_id = p.size
      where (s.size_id = 'uk-227g' or s.base_size_id = 'uk-227g') and coalesce(p.is_active, true)),
    (select count(*) from public.products p join public.size s on s.size_id = p.size
      where (s.size_id = 'uk-227g' or s.base_size_id = 'uk-227g') and not coalesce(p.is_active, true));
END;
$verify$;

commit;
