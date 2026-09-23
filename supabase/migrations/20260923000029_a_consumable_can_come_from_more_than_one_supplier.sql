-- A consumable can come from more than one supplier.
--
-- consumable_inventory.supplier_id holds ONE supplier, stamped by whoever you
-- happened to buy the item from first (backfillDefaultConsumableSupplier uses
-- `.is('supplier_id', null)`, so the first order claims it permanently). The
-- ordering form then used that single value as a HARD FILTER on what you were
-- allowed to see, which is why ordering 8oz bags from a second supplier meant
-- the item simply was not in the list.
--
-- A measurement that looked like evidence and was not: 110 of MCR's 111
-- purchased consumables show exactly one supplier. That is not how they buy --
-- it is the only thing the column can hold. The data was measuring the
-- constraint.
--
-- So: a preferred supplier, plus the others who also sell it. This is the shape
-- coffee_source already uses for the same problem -- one origin_id plus
-- allowed_origin_ids text[], which the roast modal reads as
-- `primary OR allowed.includes(x)` to borrow a source from another group. Same
-- default '{}', same NOT NULL, so every read is an array and none is a null
-- check.
--
-- Deliberately NOT a join table. The cardinality is a handful of suppliers per
-- item, it is always read whole with the row, and a second table would need its
-- own RLS, its own tenant guard and its own cascade. The array is the pattern
-- this codebase already proved.
--
-- Nothing is backfilled INTO it. The list fills itself: ordering an item from a
-- supplier that is not on it offers to add them. A list nobody maintains by
-- hand is a list that stays true.

begin;

alter table public.consumable_inventory
  add column if not exists allowed_supplier_ids text[] not null default '{}';

comment on column public.consumable_inventory.allowed_supplier_ids is
  'Other suppliers this item can be bought from, beside supplier_id (the preferred one). Mirrors coffee_source.allowed_origin_ids. supplier_id is a DEFAULT and a sort order -- never a gate on what may be ordered.';

comment on column public.consumable_inventory.supplier_id is
  'The PREFERRED supplier: pre-selected when ordering and sorted first. Never a filter on what can be ordered -- see allowed_supplier_ids.';

do $$
declare v_type text; v_notnull boolean; v_default text;
begin
  select data_type, is_nullable = 'NO', column_default
    into v_type, v_notnull, v_default
    from information_schema.columns
   where table_schema = 'public' and table_name = 'consumable_inventory'
     and column_name = 'allowed_supplier_ids';

  if v_type is null then
    raise exception 'allowed_supplier_ids was not added';
  end if;
  if v_type <> 'ARRAY' or not v_notnull or v_default is distinct from '''{}''::text[]' then
    raise exception 'allowed_supplier_ids does not match coffee_source.allowed_origin_ids (type %, notnull %, default %)',
      v_type, v_notnull, v_default;
  end if;

  -- Every existing row reads as an empty array, never null: the whole point of
  -- the default is that no caller has to null-check it.
  if exists (select 1 from consumable_inventory where allowed_supplier_ids is null) then
    raise exception 'some rows have a null allowed_supplier_ids';
  end if;

  raise notice 'allowed_supplier_ids matches the coffee_source pattern on % row(s)',
    (select count(*) from consumable_inventory);
end $$;

commit;
