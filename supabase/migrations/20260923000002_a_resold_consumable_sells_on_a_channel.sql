-- A resold item is sold to somebody, on some channel.
--
-- Coffee variants are size x channel. A syrup has no size, so its only
-- variant dimension is the channel -- and the create path never set one.
-- All 97 of MCR's resale variants carry channel NULL, which meant the
-- Wholesale chip on the Products page could not reach a single one of them,
-- and there was no way to price the same bottle differently for a cafe than
-- for a walk-in.
--
-- Backfilled to Wholesale on the owner's instruction, and scoped to MCR on
-- purpose: wholesale is not a safe guess for a roaster who only sells
-- retail. A tenant that later resells something picks its channel in the
-- form, which is the half of this that ships with the app.
--
-- Names do not move. build_product_name returns early for a row with
-- source_consumable_id -- a resold item's name follows its consumable and is
-- kept in sync by propagate_consumable_name_to_products -- so this changes
-- the channel and nothing else. Archived rows are included so one that comes
-- back is not the only unchanneled item left.

begin;

do $$
declare
  v_wholesale text;
  v_n         int;
begin
  select channel_id into v_wholesale from public.channel where channel = 'wholesale';
  if v_wholesale is null then
    raise exception 'no wholesale channel on this database';
  end if;

  update public.products
     set channel = v_wholesale
   where company_id = '9ShiyDAXhV'          -- Maui Coffee Roasters
     and source_consumable_id is not null
     and channel is null;
  get diagnostics v_n = row_count;
  raise notice 'channelled % resold consumable variants to wholesale', v_n;

  -- Social Hour (R7CbqHmA1j, 752af3ed-4) is a separate roastery that shares
  -- nothing with MCR's catalogue. Prove this did not reach across.
  if exists (
    select 1 from public.products
    where company_id in ('R7CbqHmA1j', '752af3ed-4')
      and source_consumable_id is not null
      and channel is not null
  ) then
    raise exception 'a Social Hour resold variant was channelled; scope leaked';
  end if;

  if exists (
    select 1 from public.products
    where company_id = '9ShiyDAXhV'
      and source_consumable_id is not null
      and channel is null
  ) then
    raise exception 'MCR still has unchannelled resold variants';
  end if;
end $$;

commit;
