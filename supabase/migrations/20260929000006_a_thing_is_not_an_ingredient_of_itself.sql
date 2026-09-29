-- A thing is not an ingredient of itself.
--
-- There are two ways a consumable reaches a product, and they mean opposite
-- things:
--   BOM    product_consumables  -- this consumable is used INSIDE that product
--   RESALE products.source_consumable_id -- this consumable IS that product
--
-- One row in the entire database is both: product_consumable_id
-- 549169a5-758a-44a4-a9e7-2677d4883686, the product "12-Cup Coffee Filter"
-- (group "Filter - 12-Cup Coffee", wholesale, $27) linked as an ingredient of
-- the consumable it already IS. Created 2026-09-25 06:39:07 through the
-- consumable page's own "Link to Product" button, whose picker listed every
-- active product in the facility including that one.
--
-- WHY IT MATTERS. calculate_current_stock_consumables subtracts BOM usage and
-- resale usage as two independent terms, so a product that is both deducts the
-- same consumable TWICE per unit sold. It is latent rather than realised:
-- nothing has sold since that item's 2026-04-30 count anchor, so its calculated
-- stock is still 2.0. It becomes real on the next sale.
--
-- Costing is unaffected either way. update_product_total_cogs branches on
-- product type and, for a non-coffee product, sets the consumable cost term to
-- zero and takes unit_cost from source_consumable_id. The BOM is not read at
-- all, which is why the filter's total_unit_cogs is 20.62 -- the consumable's
-- own fallback cost, not double it.
--
-- The picker no longer offers a consumable its own product (stratos, this
-- release), so this deletes the one row that offer produced rather than a class
-- of them.

begin;

delete from public.product_consumables pc
 using public.products p
 where p.product_id = pc.product_id
   and p.source_consumable_id = pc.consumable_id;

do $verify$
declare v_bad int;
begin
  select count(*) into v_bad
    from public.product_consumables pc join public.products p on p.product_id = pc.product_id
   where p.source_consumable_id = pc.consumable_id;
  if v_bad > 0 then
    raise exception '% self-referential BOM row(s) remain', v_bad;
  end if;

  -- The filter is still sold and still linked to its stock the RESALE way. This
  -- removes a double count, not the product's ability to move inventory.
  if not exists (
    select 1 from public.products
     where product_id = 'c0565678-a2e7-42db-b494-ebacdcc52b72'
       and source_consumable_id = 'cons_11fad5de215c6c85') then
    -- Not an error: the row may legitimately have been merged or renamed since.
    raise notice 'the 12-Cup Coffee Filter resale link is not where it was; nothing else was touched';
  else
    raise notice 'the 12-Cup Coffee Filter keeps its resale link and loses the duplicate BOM path';
  end if;
end;
$verify$;

commit;
