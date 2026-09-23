-- Four consumables existed twice, and receiving a shipment is what made them.
--
-- MCR's Add-item-to-shipment path inserts a new consumable_inventory row from
-- whatever name is typed. Type "8oz Gold Bag" against a shipment when an "8oz
-- Gold Bag" already exists and you get a second one, holding nothing but that
-- shipment. It happened four times, on 2026-08-08 and 2026-09-14, and was
-- only visible once somebody looked for repeated names.
--
-- The split matters because a duplicate halves a count. "8oz Gold Bag" read
-- 1,000 on one row and 1,000 on the other; neither number was the shelf.
--
-- WHICH ROW SURVIVES. The OLDER one, every time, because it is the one
-- carrying the history:
--
--   Guittard Caramel Sauce     old: 86 order lines, price 43.25, counted
--                              new: 0 lines, no price, 1 shipment
--   Guittard Chocolate Powder  old: 18 order lines, price 71.00, counted
--                              new: 0 lines, no price, 1 shipment
--   16oz / 8oz Gold Bag        old: counted 500 / 1,000 on 2026-08-13
--                              new: no count, 1 shipment each
--
-- The owner asked to keep the most recently created of the pair, on the
-- reasonable assumption that the newer row was the live one because it held
-- the shipment. It is the other way round: the shipment is the only thing the
-- new rows have, and a shipment can be repointed. Keeping the new rows would
-- have discarded 104 order lines and both prices. Nothing is lost this way --
-- the shipments move across and the survivors keep their counts and history.
--
-- The two duplicate PRODUCTS that came with the Guittard rows are deleted
-- outright, with their groups. Verified first: zero order_details, zero
-- pack_run, zero product_consumables, zero price log rows, zero Shopify
-- mappings, zero standing-order lines, zero VMI items, and each was the sole
-- member of its own group.
--
-- Scoped by explicit id, so this is a no-op on any database that does not
-- have these exact rows (staging does not).

begin;

create temporary table _dupes (keep_id text, drop_id text, label text) on commit drop;
insert into _dupes values
  ('cons_cd238b2a694b7335', '42143c9c-f7e5-4dc2-b35f-cd11d577b9ef', '16oz Gold Bag'),
  ('cons_a9517444a4dbfb44', 'f2ed36d7-ac9c-40cb-8ba6-4177663de291', '8oz Gold Bag'),
  ('cons_883485e32da56554', 'e5b0f7ab-1127-4d38-98c3-73371de2f1d0', 'Guittard Caramel Sauce'),
  ('cons_5e535fefe33deab8', 'aeaef821-ddf8-4f3d-b49d-8724b1b6c069', 'Guittard Chocolate Powder');

do $$
declare
  d           record;
  v_moved     int;
  v_total     int := 0;
  v_products  int := 0;
  v_rows      int := 0;
begin
  for d in select * from _dupes loop
    -- Nothing to do on a database that never had the duplicate.
    if not exists (select 1 from public.consumable_inventory
                   where consumable_inventory_id = d.drop_id) then
      continue;
    end if;
    -- Refuse to merge into a survivor that is not there: better to stop than
    -- to orphan a shipment.
    if not exists (select 1 from public.consumable_inventory
                   where consumable_inventory_id = d.keep_id) then
      raise exception 'survivor % missing for duplicate % (%)', d.keep_id, d.drop_id, d.label;
    end if;

    -- The shipment lines move. This FK is ON DELETE RESTRICT, so this has to
    -- happen before the delete or the delete simply fails.
    update public.consumable_inventory_purchased
       set consumable_inventory_item = d.keep_id
     where consumable_inventory_item = d.drop_id;
    get diagnostics v_moved = row_count;
    v_total := v_total + v_moved;

    -- BOM links: repoint any that exist, then drop a link that would now be a
    -- duplicate of one the survivor already has.
    update public.product_consumables pc
       set consumable_id = d.keep_id
     where pc.consumable_id = d.drop_id
       and not exists (
         select 1 from public.product_consumables x
         where x.product_id = pc.product_id and x.consumable_id = d.keep_id);
    delete from public.product_consumables where consumable_id = d.drop_id;

    -- The empty product facet the duplicate brought with it, and its group.
    -- Guarded on genuinely unused: if anything ever ordered it, leave it and
    -- let a human decide.
    delete from public.product_groups g
     where g.group_id in (
       select p.group_id from public.products p
       where p.source_consumable_id = d.drop_id
         and not exists (select 1 from public.order_details od where od.product_id = p.product_id)
     )
     and not exists (
       select 1 from public.products p2
       where p2.group_id = g.group_id
         and p2.source_consumable_id is distinct from d.drop_id);

    delete from public.products p
     where p.source_consumable_id = d.drop_id
       and not exists (select 1 from public.order_details od where od.product_id = p.product_id);
    get diagnostics v_rows = row_count;
    v_products := v_products + v_rows;

    -- Anything still pointing here (a product that HAS been ordered) keeps its
    -- history but must not dangle.
    update public.products set source_consumable_id = d.keep_id
     where source_consumable_id = d.drop_id;

    delete from public.consumable_inventory where consumable_inventory_id = d.drop_id;
    raise notice 'merged % -> % (% shipment lines)', d.label, d.keep_id, v_moved;
  end loop;

  raise notice 'moved % shipment lines, removed % duplicate products', v_total, v_products;
end $$;

-- Recompute the survivors now that they own the moved shipments.
set local lock_timeout = '2s';
update public.consumable_inventory ci
   set updated_at = now()
 where exists (select 1 from _dupes d where d.keep_id = ci.consumable_inventory_id);

do $$
declare
  v_left int;
begin
  select count(*) into v_left
  from public.consumable_inventory
  where consumable_inventory_id in (select drop_id from _dupes);
  if v_left > 0 then
    raise exception '% duplicate consumable rows survived the merge', v_left;
  end if;

  -- And no shipment line may be left pointing at a row that is gone.
  if exists (
    select 1 from public.consumable_inventory_purchased cip
    where cip.consumable_inventory_item in (select drop_id from _dupes)
  ) then
    raise exception 'a shipment line still points at a deleted consumable';
  end if;
end $$;

commit;
