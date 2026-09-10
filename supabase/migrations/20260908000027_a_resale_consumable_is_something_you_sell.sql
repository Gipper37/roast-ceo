-- A Resale consumable with no product cannot be sold.
--
-- STRATA models a buy-wholesale-then-resell consumable as TWO linked records:
-- consumable_inventory is the STOCK, and a product_group (which IS the product)
-- plus its products variant, tied back by products.source_consumable_id, is the
-- SELLABLE thing. Only a product can go on an invoice.
--
-- The QB importer mints both halves. Creating one by hand only ever wrote the
-- stock row — the second half was logged in July as "Add-a-resold-consumable
-- from Products UI" and never built. So an item tagged Resale sat in Inventory
-- and was invisible everywhere you would sell it, with nothing to toggle.
-- Owner, 2026-09-09: it "is not showing up as product in the products page.
-- which means i therefore can't toggle it on as sellable."
--
-- The UI half now mints the product on create. This is the catch-up for the
-- ones already stranded: 18 on Maui Coffee Roasters, the oldest from June.
--
-- Deliberately narrow. It only ADDS the missing halves — no consumable is
-- edited, no existing product is touched, and price is left to the price log.
-- Re-running it is a no-op.

begin;

do $$
declare
  r record;
  -- product_groups.group_id is a UUID; products.product_id is TEXT. Two id
  -- conventions in one insert, so they are typed separately rather than cast.
  v_group uuid;
  v_product text;
  n int := 0;
begin
  for r in
    select ci.consumable_inventory_id, ci.consumable_inventory_item,
           ci.company_id, ci.facility_id
      from public.consumable_inventory ci
     where ci.consumable_type = 'global_consumable_type_distribution'
       and coalesce(ci.is_active, true)
       and ci.company_id is not null
       and ci.consumable_inventory_item is not null
       and not exists (
         select 1 from public.products p
          where p.source_consumable_id = ci.consumable_inventory_id)
  loop
    v_group   := gen_random_uuid();
    v_product := gen_random_uuid()::text;

    -- The GROUP is the product; products_group_id_not_null is enforced on new
    -- writes, so it has to exist first.
    insert into public.product_groups (group_id, group_name, company_id, facility_id)
    values (v_group, r.consumable_inventory_item, r.company_id, r.facility_id);

    insert into public.products
      (product_id, group_id, product_name, product_type, source_consumable_id,
       company_id, facility_id, is_active, price)
    values
      (v_product, v_group, r.consumable_inventory_item, 'ptype_consumable',
       r.consumable_inventory_id, r.company_id, r.facility_id, true,
       -- The price LOG owns products.price. A backfill has no price to state
       -- and must not invent one: these land unpriced, which is visible and
       -- correct, rather than priced at zero, which is neither.
       null);

    n := n + 1;
  end loop;

  raise notice 'Gave % resale consumable(s) their sellable half.', n;
end
$$;

commit;
