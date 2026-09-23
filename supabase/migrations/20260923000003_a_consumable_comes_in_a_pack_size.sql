-- The pack size a consumable comes in.
--
-- MCR has been typing it into the name for months, because there was nowhere
-- else to put it: "Rishi Matcha 2.2lb", "English Breakfast 50ct", "Guittard
-- White Choc Sauce 125oz", "Monin 64oz Sauce Pump". A field people are
-- already hand-rolling into a text column is a field that exists.
--
-- Free text, and deliberately NOT a size_id. The size table is sized for
-- coffee: every row carries weight_lbs, which is what a bag weighs and what
-- the roast maths divides by. "750ml" and "50ct" have no weight in pounds and
-- would either pollute that table with nulls or invent numbers.
--
-- WHY THIS IS NOT A VARIANT DIMENSION. It was asked whether a consumable
-- should gain coffee's variant model, so one Gold Bag could hold 8oz, 12oz
-- and 1lb. It should not: stock is counted per physical item. Three bag sizes
-- are three boxes on the shelf with three counts, three landed costs and
-- three reorder points, and folding them into one row would split a single
-- count anchor across all three. MCR already models them the right way, as
-- separate consumables. A resold consumable's only variant dimension is the
-- channel it sells on.

begin;

alter table public.consumable_inventory
  add column if not exists unit_size text;

comment on column public.consumable_inventory.unit_size is
  'The pack this item comes in: 750ml, 64oz, 50ct. Free text, not a size_id -- see the migration header for why it is not the size table.';

do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'consumable_inventory'
      and column_name = 'unit_size'
  ) then
    raise exception 'unit_size was not added';
  end if;
end $$;

commit;
