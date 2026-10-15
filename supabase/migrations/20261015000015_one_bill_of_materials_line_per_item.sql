-- One bill-of-materials line per item, per basis.
--
-- `product_consumables` had nothing stopping two rows for the same product and
-- the same consumable, and ten such pairs exist on prod. Every one is an exact
-- duplicate -- quantity 1, per_case false, twice -- so each doubles that
-- variant's packaging cost and doubles what it depletes:
--
--   demo-aloha-coffee-roasters  5 variants  x "5lbs Bag"
--   R7CbqHmA1j                  5 variants  x "5lbs Bag"
--
-- All ten sit on INACTIVE variants, which is why nobody has noticed: the COGS
-- trigger returns early for a variant that is inactive and was already
-- inactive. The depletion does NOT care -- `calculate_current_stock_consumables`
-- sums `order_details` for any product, active or not -- so every historical
-- order on these ten took two bags off the shelf for every one it packed.
--
-- THE KEY IS (product_id, consumable_id, per_case), and the third column is
-- there on purpose. Two lines for the same consumable at DIFFERENT bases is a
-- real bill of materials: one sticker on each bag and one more on the box is
-- a per-bag line and a per-case line for the same sticker, and
-- `product_consumables_effective` multiplies only the first. Two lines at the
-- same basis is never anything but an accident, because the answer to "it uses
-- two" is the quantity.
--
-- NOT facility_id. It is non-null on all 1,515 rows and no product has lines in
-- more than one facility, and including it would ALLOW a per-facility pair that
-- the COGS sum would double-count anyway: that sum filters on the CONSUMABLE's
-- facility (`ci.facility_id = NEW.facility_id`), not the line's.
--
-- WHICH ROW SURVIVES: the lexicographically first product_consumable_id. The
-- pairs are identical in every column that means anything, so there is nothing
-- to prefer -- what matters is that the choice is deterministic and written
-- down, not which of two identical rows it lands on. The deleted ids are in
-- this file so the delete can be read back.

begin;

-- The twenty rows, before: ten pairs, one survivor each.
create temp table _bom_dupes on commit drop as
select pc.product_consumable_id, pc.product_id, pc.consumable_id, pc.per_case,
       row_number() over (
         partition by pc.product_id, pc.consumable_id, pc.per_case
         order by pc.product_consumable_id
       ) as keep_rank
  from public.product_consumables pc;

do $pre$
DECLARE
  v_pairs int;
  v_extra int;
BEGIN
  select count(*) into v_pairs from (
    select 1 from _bom_dupes group by product_id, consumable_id, per_case having count(*) > 1) x;
  select count(*) into v_extra from _bom_dupes where keep_rank > 1;
  raise notice 'bill of materials: % duplicated keys, % rows to remove', v_pairs, v_extra;
  -- 🔴 A bound, not a count. Ten pairs were measured on prod on 2026-10-15, and
  -- staging and dev carry their own data, so an exact equality would fail there
  -- for no reason. What must never happen is this migration quietly deleting
  -- hundreds of rows because something else went wrong upstream.
  IF v_extra > 50 THEN
    raise exception 'refusing to remove % duplicate bill-of-materials rows; expected a handful', v_extra;
  END IF;
END;
$pre$;

delete from public.product_consumables pc
 using _bom_dupes d
 where d.product_consumable_id = pc.product_consumable_id
   and d.keep_rank > 1;

-- One line per item per basis, from here on. A UNIQUE INDEX rather than a
-- constraint so it can be created without rewriting the table, and so the
-- NULLs behave: product_id and consumable_id are both nullable, and NULLS NOT
-- DISTINCT means two rows that name nothing are also caught rather than
-- slipping through as "not equal".
create unique index if not exists uq_product_consumables_item_basis
  on public.product_consumables (product_id, consumable_id, per_case)
  nulls not distinct;

do $verify$
DECLARE
  v_left int;
  v_pid  text;
  v_cid  text;
  v_took boolean := false;
BEGIN
  select count(*) into v_left from (
    select 1 from public.product_consumables
     group by product_id, consumable_id, per_case having count(*) > 1) x;
  if v_left > 0 then
    raise exception '% duplicated bill-of-materials keys survived', v_left;
  end if;

  -- 🔴 And the index actually REFUSES, tried rather than assumed. An index that
  -- was created on the wrong columns would satisfy the count above and nothing
  -- else, which is the kind of verify block that passes while proving nothing.
  select product_id, consumable_id into v_pid, v_cid
    from public.product_consumables
   where product_id is not null and consumable_id is not null
   limit 1;

  if v_pid is null then
    raise notice 'no bill-of-materials rows here, skipping the refusal check';
  else
    BEGIN
      insert into public.product_consumables
        (product_consumable_id, product_id, consumable_id, quantity, per_case, company_id, facility_id)
      select 'zzverify-dupe-' || md5(random()::text), product_id, consumable_id,
             quantity, per_case, company_id, facility_id
        from public.product_consumables
       where product_id = v_pid and consumable_id = v_cid
       limit 1;
      v_took := true;
    EXCEPTION WHEN unique_violation THEN
      v_took := false;
    END;
    if v_took then
      raise exception 'a duplicate line was accepted, so the index is not on the right columns';
    end if;

    -- The OTHER basis must still be allowed, because that is the whole reason
    -- per_case is in the key. Inserted and removed.
    insert into public.product_consumables
      (product_consumable_id, product_id, consumable_id, quantity, per_case, company_id, facility_id)
    select 'zzverify-basis-' || md5(random()::text), product_id, consumable_id,
           quantity, not per_case, company_id, facility_id
      from public.product_consumables
     where product_id = v_pid and consumable_id = v_cid
     limit 1;
    delete from public.product_consumables where product_consumable_id like 'zzverify-basis-%';
    if exists (select 1 from public.product_consumables where product_consumable_id like 'zzverify-%') then
      raise exception 'the verify block left rows behind';
    end if;
  end if;

  raise notice 'one bill-of-materials line per item, per basis';
END;
$verify$;

commit;
