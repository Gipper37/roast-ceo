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
-- 3. `build_product_name` stops recomposing a name nothing changed about.
--    This is a PREREQUISITE, not a bonus: the cascade refreshes products by
--    touching them, and that trigger fired on every update. It is not
--    idempotent, because `compile_product_name` title-cases the channel --
--    `initcap` over the global channel rows, which are stored lowercase, is
--    what makes `wholesale` read "Wholesale", and it makes `vip` read "Vip".
--    Social Hour UK's 43 VIP products are stored "- VIP", so touching them
--    renamed them, and `product_name` is the string QuickBooks matches an
--    invoice line on. Measured on prod: 43 of 992 group-derived products would
--    have been renamed by a write that changed nothing about their name.
--
-- 🔴 WHAT THIS DELIBERATELY DOES NOT DO: fix the casing. "Vip" is still what a
-- product gets if its channel genuinely changes. Normalising the four global
-- channel rows to display case and dropping `initcap` would fix it and would
-- rename 9 live products on prod (4 UK "Vip" to "VIP", and 5 Social Hour
-- "100G"/"2LBS" to the "100g"/"2lbs" their own size rows say). That is a
-- decision about whose text wins and it renames rows a customer has seen on an
-- invoice, so it is written down rather than taken.
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
  update public.products p
     set updated_at = now()
   where p.size = new.size_id
      or p.size in (select c.size_id from public.size c where c.base_size_id = new.size_id);

  return null;
end;
$$;

drop trigger if exists zza_cascade_size_weight on public.size;
-- AFTER: it writes other rows, and it must not see a weight the derivation
-- above has not settled yet.
create trigger zza_cascade_size_weight
  after update of weight on public.size
  for each row execute function public.cascade_size_weight();

CREATE OR REPLACE FUNCTION public.build_product_name()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_name text;
BEGIN
  -- 🔴 NOTHING TO RECOMPOSE MEANS NOTHING TO WRITE.
  --
  -- The composed name is group - size - channel, and this fired on EVERY
  -- update, so any unrelated write recomposed it. That is not idempotent,
  -- because the composer title-cases the channel: `initcap` over the global
  -- channel rows, which are stored lowercase, is what turns `wholesale` into
  -- "Wholesale" -- and `vip` into "Vip". Social Hour UK's 43 VIP products are
  -- stored as "- VIP", so ANY touch of those rows renamed them, and
  -- `product_name` is the string QuickBooks matches an invoice line on.
  --
  -- Measured on prod before this change: 43 of 992 group-derived products
  -- would be renamed by a write that changed nothing about their name.
  --
  -- So the guard is the honest statement of the dependency: recompose on
  -- INSERT, and on UPDATE only when one of the three parts actually moved.
  -- A cost refresh, a weight refresh, an is_active toggle or a price write no
  -- longer touches the name.
  --
  -- This does NOT fix the casing itself -- "Vip" is still what a product gets
  -- if its channel or size really does change. That is a separate decision
  -- about whose text wins, the roaster's or ours, and it renames live rows.
  IF TG_OP = 'UPDATE'
     AND NEW.group_id             IS NOT DISTINCT FROM OLD.group_id
     AND NEW.size                 IS NOT DISTINCT FROM OLD.size
     AND NEW.channel              IS NOT DISTINCT FROM OLD.channel
     AND NEW.source_consumable_id IS NOT DISTINCT FROM OLD.source_consumable_id
     AND NEW.product_name         IS NOT DISTINCT FROM OLD.product_name THEN
    RETURN NEW;
  END IF;

  v_name := public.compile_product_name(NEW.group_id, NEW.size, NEW.channel, NEW.source_consumable_id);
  -- Null means this row's name is not group-derived (a resold consumable, or
  -- no group): leave the stored name alone, as this function always has.
  IF v_name IS NULL THEN
    RETURN NEW;
  END IF;
  NEW.product_name := v_name;
  RETURN NEW;
END;
$function$;

-- ── The six stale rows ─────────────────────────────────────────────────────
-- Touch them so `update_product_total_cogs` re-reads the size and refills the
-- cache. Scoped to rows that actually disagree, so this is a repair rather
-- than a 948-row rewrite, and it cannot rename anything now that
-- build_product_name leaves an unchanged name alone.
update public.products p
   set updated_at = now()
  from public.size s
 where s.size_id = p.size
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
  -- Every product's cached weight now agrees with its size.
  select count(*) into v_stale
    from public.products p join public.size s on s.size_id = p.size
   where p.weight_lbs is distinct from s.weight;
  if v_stale > 0 then
    raise exception '% products still disagree with their size''s weight', v_stale;
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
  select s.size_id into v_bag
    from public.size s
    join public.size c on c.base_size_id = s.size_id and c.units_per_case is not null
   where s.weight is not null
   limit 1;

  if v_bag is null then
    raise notice 'no bag with a case built on it here, skipping the cascade check';
  else
    select c.size_id into v_case from public.size c where c.base_size_id = v_bag limit 1;
    select weight into v_before from public.size where size_id = v_bag;
    select p.product_id, p.product_name into v_pid, v_name
      from public.products p where p.size = v_case limit 1;

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
      -- And the name did NOT churn, which is the whole reason part 3 is here.
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

  -- build_product_name kept the rest of its body.
  if (select prosrc from pg_proc where oid = 'public.build_product_name'::regproc)
     not like '%compile_product_name%' then
    raise exception 'build_product_name lost its composer call';
  end if;

  raise notice 'a size''s weight now reaches the products on it';
END;
$verify$;

commit;
