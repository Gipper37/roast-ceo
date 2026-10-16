-- Changing a size's weight reaches the products on it.
--
-- `products.weight_lbs` is a CACHE of `size.weight`, filled by
-- `update_product_total_cogs`, a BEFORE trigger on **products**. So it is only
-- refreshed when a PRODUCT row is written. Editing the SIZE's weight wrote one
-- row and left every product on it holding the old number -- and weight_lbs is
-- what the coffee cost term, the COGS%, the gross profit and the shipping
-- weight are all computed from.
--
-- Not hypothetical. On prod today, 6 of Social Hour UK's products:
--
--   Brazil - 1KG - Wholesale                        weight_lbs 0.5
--   Golden Hour - Brazil - 1KG - Wholesale          weight_lbs 0.5
--   Golden Hour - El Salvador - 1KG - Wholesale     weight_lbs NULL
--   Golden Hour - Guatemala - 1KG - Wholesale       weight_lbs NULL
--   Golden Hour - Nicaragua - 1KG - Wholesale       weight_lbs NULL
--   Golden Hour - Peru Griselda - 1KG - Wholesale   weight_lbs NULL
--
-- against a `1KG` size that weighs 2.20462 lb. Their 1 kg wholesale bags are
-- costed and shipped as half-pound bags, or as nothing at all: a 4.4-fold
-- understatement of coffee cost on six live products.
--
-- THREE PARTS, and they have to land together.
--
-- 1. A case's weight is DERIVED, in a BEFORE trigger. `size.weight` on a case
--    is base weight x pack count and nothing kept it so: the arithmetic ran
--    once, in the browser, at creation. Now the column cannot hold anything
--    else, which also makes `updateSize`'s refusal belt-and-braces rather than
--    the only guard.
--
-- 2. A bag's weight change CASCADES: to the cases built on it, and then to the
--    products on all of them. One level only, by construction -- a case of a
--    case is refused -- so this cannot recurse, and a two-cycle in the data
--    cannot either, because neither row would be a bag.
--
-- 🔴 A THIRD PART WAS WRITTEN AND THEN REMOVED, and the reason is worth
-- keeping, because it was wrong in the one way that is hard to see: it was
-- wrong about WHEN A TRIGGER FIRES.
--
-- The draft added an early return to `build_product_name` so that an update
-- changing none of group_id, size or channel would not recompose the name. The
-- stated reason was that this cascade's touch would otherwise rename things:
-- `compile_product_name` title-cases the channel, the global channel rows are
-- stored lowercase, and `initcap('vip')` is "Vip" while Social Hour UK's 43
-- products are stored "- VIP".
--
-- The premise was false. Prod says:
--     CREATE TRIGGER trg_build_product_name BEFORE INSERT OR UPDATE
--       OF group_id, size, channel ON public.products
-- `updated_at` is not in that list, so the cascade's touch NEVER fired the
-- composer and nothing was ever at risk from it. The guard was unnecessary.
--
-- And it was harmful. `renameProductGroup` (products/actions.ts) propagates a
-- renamed product to its variants by writing `update products set group_id =
-- group_id` -- a self-assignment that fires the trigger precisely because
-- group_id IS in its column list, while leaving the value alone.
-- `merge_product_groups` does the same for the surviving name. The guard sees
-- group_id unchanged and returns early, so RENAMING A PRODUCT WOULD HAVE
-- STOPPED RENAMING ITS VARIANTS -- and product_name is what order pickers,
-- pack-run labels and QuickBooks line matching all read.
--
-- The casing issue is real and is recorded on the open list. It needs fixing
-- where it lives, not behind a guard that breaks a feature.
--
-- Functions patched from `pg_get_functiondef`, not retyped.

begin;

-- ── 1. A case's weight is derived ──────────────────────────────────────────
create or replace function public.derive_case_size_weight()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $$
declare
  v_base_weight numeric;
begin
  -- A bag is not derived from anything.
  if new.base_size_id is null or new.units_per_case is null then
    return new;
  end if;

  select weight into v_base_weight from public.size where size_id = new.base_size_id;

  -- A base with no weight on it yet leaves the case's weight alone rather than
  -- nulling it: `validateCase` already allows creating a case of a weightless
  -- size, and the honest answer there is "total weight unknown", which is what
  -- the UI says. Overwriting a figure somebody typed with NULL would be worse.
  if v_base_weight is null then
    return new;
  end if;

  -- NOT rounded. lib/products/caseSize rounds to 12 places because JS binary
  -- floats leave an artifact at the 16th; numeric here is exact, so rounding
  -- would introduce a disagreement rather than remove one. Prod's own
  -- "Case of 6" holds 3.00269601095803264944, which is 227g x 6 to the digit.
  new.weight := v_base_weight * new.units_per_case;
  return new;
end;
$$;

drop trigger if exists aab_derive_case_size_weight on public.size;
-- Named to sort before the audit triggers, which only stamp who and when, and
-- after nothing: the derived weight has to be in place before anything reads
-- NEW. Fires on the three columns the derivation depends on, so an ordinary
-- rename does not pay for it.
create trigger aab_derive_case_size_weight
  before insert or update of weight, units_per_case, base_size_id
  on public.size
  for each row execute function public.derive_case_size_weight();

-- ── 2. A weight change reaches the cases and the products ──────────────────
create or replace function public.cascade_size_weight()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  if new.weight is not distinct from old.weight then
    return null;
  end if;

  -- The cases built on this bag. Their own weight is derived, so this is the
  -- statement that re-derives it -- trigger 1 recomputes it from the new base
  -- weight, which is why the value sent here does not matter and is written as
  -- the derivation anyway for anyone reading the statement.
  --
  -- Only a BAG cascades. A case has no cases (a case of a case is refused by
  -- validateCase and by the table's own rules), so this is one level deep by
  -- construction and no cycle in the data can make it recurse.
  if old.base_size_id is null then
    update public.size c
       set weight = new.weight * c.units_per_case
     where c.base_size_id = new.size_id
       and c.units_per_case is not null
       and c.weight is distinct from new.weight * c.units_per_case;
  end if;

  -- And the products. Touched rather than computed here, because the cache is
  -- filled by `update_product_total_cogs` on products and that function is the
  -- one definition of the whole cost chain: weight_lbs, the coffee term, the
  -- consumable term, total_unit_cogs, cogs_pct, gross_profit_per_unit. Copying
  -- any part of it into this trigger is how the two drift.
  --
  -- `updated_at` is what is written because every other column here is derived
  -- from something; `handle_updated_record` would stamp it anyway.
  --
  -- 🔴 ACTIVE ONLY, and that is not an optimisation.
  -- `update_product_total_cogs` opens with
  --     IF COALESCE(NEW.is_active,true)=false AND COALESCE(OLD.is_active,true)=false
  --        THEN RETURN NEW;
  -- placed ABOVE `NEW.weight_lbs := v_weight`. So an archived variant's cached
  -- weight CANNOT be refreshed by a touch -- and must not be. Its numbers are
  -- deliberately frozen at the moment it was archived, which is what the UI
  -- reads (`isArchived ? last_active_unit_cogs : total_unit_cogs`). Touching
  -- them would be a write that changes nothing and pretends otherwise.
  update public.products p
     set updated_at = now()
   where coalesce(p.is_active, true)
     and (p.size = new.size_id
      or p.size in (select c.size_id from public.size c where c.base_size_id = new.size_id));

  return null;
end;
$$;

drop trigger if exists zza_cascade_size_weight on public.size;
-- AFTER: it writes other rows, and it must not see a weight the derivation
-- above has not settled yet.
create trigger zza_cascade_size_weight
  after update of weight on public.size
  for each row execute function public.cascade_size_weight();

-- ── The stale rows ─────────────────────────────────────────────────────────
--
-- 🔴 AND THERE ARE NONE, which is the correction this migration needed.
--
-- The header above says six products on prod cache the wrong weight. They do.
-- Every one of them is ARCHIVED (`is_active = f`, checked: 26e88e4d,
-- uk-be678eca, 34de1e7c, a50f94c5, 336d204f, uk-1d6700ae), and an archived
-- variant's cached numbers are frozen BY DESIGN -- see the note on the cascade
-- above. So they are not stale, they are historical, and touching them would
-- do nothing: the trigger returns before the assignment.
--
-- The first draft of this file touched them anyway and then asserted the
-- disagreement was gone, so its own verify raised and rolled the whole
-- migration back -- taking 15, 16 and 17 with it, since db push stops at the
-- first failure. A repair that cannot work, guarded by a check that proves it
-- cannot, is worse than no repair.
--
-- Zero ACTIVE products disagree with their size today, so there is nothing to
-- repair at all. The statement is kept, scoped to active rows, because it is
-- the right thing to run on a database where one does.
update public.products p
   set updated_at = now()
  from public.size s
 where s.size_id = p.size
   and coalesce(p.is_active, true)
   and p.weight_lbs is distinct from s.weight;

do $verify$
DECLARE
  v_stale   int;
  v_drifted int;
  v_bag     text;
  v_case    text;
  v_before  numeric;
  v_after   numeric;
  v_name    text;
  v_pid     text;
BEGIN
  -- Every ACTIVE product's cached weight agrees with its size.
  --
  -- 🔴 ACTIVE, and the first draft of this block said every product. All six
  -- disagreeing rows on prod are archived, whose weight the trigger refuses to
  -- refresh on purpose, so the unqualified count raised and rolled the whole
  -- migration back -- taking 15, 16 and 17 with it. A verify that asserts
  -- something the design forbids is not a check, it is a stop.
  select count(*) into v_stale
    from public.products p join public.size s on s.size_id = p.size
   where coalesce(p.is_active, true)
     and p.weight_lbs is distinct from s.weight;
  if v_stale > 0 then
    raise exception '% ACTIVE products still disagree with their size''s weight', v_stale;
  end if;

  -- Every case's weight agrees with its base.
  select count(*) into v_drifted
    from public.size c join public.size b on b.size_id = c.base_size_id
   where c.units_per_case is not null and b.weight is not null
     and c.weight is distinct from b.weight * c.units_per_case;
  if v_drifted > 0 then
    raise exception '% case sizes disagree with their base', v_drifted;
  end if;

  -- 🔴 And the cascade WORKS, exercised on real rows rather than asserted.
  -- A bag whose weight moves must carry its case and both their products with
  -- it. Done on a size this tenant owns, then put back.
  -- 🔴 PICKED DETERMINISTICALLY, AND ON AN ACTIVE PRODUCT.
  -- The draft used three unordered `limit 1` selects with no is_active filter.
  -- Prod has a bag (size_5d679e8b96bb2286) with four cases, two of which carry
  -- exactly one product each and ZERO active ones -- so a different plan would
  -- have landed the probe on a case whose only variant is archived and raised
  -- "the product on the case kept a stale weight" for the archived reason
  -- rather than a real failure. An ORDER BY makes the choice repeatable; the
  -- is_active filter makes it the right one.
  select s.size_id, c.size_id, p.product_id, p.product_name
    into v_bag, v_case, v_pid, v_name
    from public.size s
    join public.size c on c.base_size_id = s.size_id and c.units_per_case is not null
    join public.products p on p.size = c.size_id and coalesce(p.is_active, true)
   where s.weight is not null
   order by s.size_id, c.size_id, p.product_id
   limit 1;

  if v_bag is null then
    raise notice 'no bag with a case and an active product on it here, skipping the cascade check';
  else
    select weight into v_before from public.size where size_id = v_bag;

    update public.size set weight = v_before * 2 where size_id = v_bag;

    select weight into v_after from public.size where size_id = v_case;
    if v_after is distinct from (select weight from public.size where size_id = v_bag)
                               * (select units_per_case from public.size where size_id = v_case) then
      raise exception 'the case weight did not follow its base: case %, base %',
        v_after, v_before * 2;
    end if;
    if v_pid is not null then
      if (select weight_lbs from public.products where product_id = v_pid) is distinct from v_after then
        raise exception 'the product on the case kept a stale weight: % against %',
          (select weight_lbs from public.products where product_id = v_pid), v_after;
      end if;
      -- And the name did not churn. 🔴 This assertion is now VACUOUS and is
      -- kept deliberately: `trg_build_product_name` fires on UPDATE OF
      -- group_id, size, channel, and the cascade writes only `updated_at`, so
      -- the composer was never reachable from here. The draft read this
      -- passing as evidence that its guard was needed; it was evidence of
      -- nothing. Left in place as a tripwire in case the trigger's column list
      -- ever widens.
      if (select product_name from public.products where product_id = v_pid) is distinct from v_name then
        raise exception 'touching a product renamed it: % became %',
          v_name, (select product_name from public.products where product_id = v_pid);
      end if;
    end if;

    update public.size set weight = v_before where size_id = v_bag;
    if (select weight from public.size where size_id = v_bag) is distinct from v_before then
      raise exception 'the rehearsal did not put the weight back';
    end if;
  end if;

  -- 🔴 build_product_name must NOT have gained the guard this file's draft
  -- added. It would stop `renameProductGroup`'s `set group_id = group_id`
  -- touch from recomposing a variant's name, which is the only mechanism
  -- propagating a product rename. Asserted so a revert of the revert fails.
  if (select prosrc from pg_proc where oid = 'public.build_product_name'::regproc)
     like '%NEW.group_id             IS NOT DISTINCT FROM OLD.group_id%' then
    raise exception 'build_product_name carries the early-return guard; it breaks renameProductGroup';
  end if;
  if (select prosrc from pg_proc where oid = 'public.build_product_name'::regproc)
     not like '%compile_product_name%' then
    raise exception 'build_product_name lost its composer call';
  end if;

  raise notice 'a size''s weight now reaches the products on it';
END;
$verify$;

commit;
