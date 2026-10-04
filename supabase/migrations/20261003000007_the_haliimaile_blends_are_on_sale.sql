-- The Haliimaile blends are on sale.
--
-- Two more of the 24 hidden COFFEE products, carried over from the review of
-- 20261003000002. That migration unhid 40 groups by the owner's rule, anything
-- ordered in the last 30 days. These two fall just outside it, last ordered
-- 2026-08-27, and he cleared them by name once he saw the list.
--
--   Haliimaile Blend        5lbs / wholesale  $66.50  24 order lines
--   Haliimaile Blend Decaf  5lbs / wholesale  $64.50  22 order lines
--
-- Both have a live, priced, active wholesale variant, so each has something to
-- sell the moment it is visible.
--
-- THE REST OF THE 24 ARE STAYING AS THEY ARE, and it is worth writing down why,
-- because it looked like a bug and is not. Eight of them have no sellable
-- variant at all:
--   100% Hawaiian Holiday Pack · Coffee · Colombia Geisha ·
--   Colombian Supremo Dark Decaf · Hazelnut · Organic French Vanilla ·
--   Pumpkin Spice · Red Catuai Washed Medium · Supremo Light Decaf
-- Every variant of every one of them is already is_active = false. They are
-- ARCHIVED, and they are archived correctly: product_groups has no is_active
-- column, so an archived product IS a product whose variants are all archived,
-- and archiving the last variant archives the product. The storefront drops
-- them because its products!inner join returns nothing for them. There was
-- nothing to archive.
--
-- The 127 hidden groups were not hidden by merges either -- only 8 of 135 are
-- merge tombstones. They were hidden by the QuickBooks importer,
-- qbImportActions.ts:1324, which marks every non-coffee auto-shadow group
-- is_visible = false by design.

begin;

create temporary table _before on commit drop as
  select group_id, is_visible from public.product_groups;

update public.product_groups
   set is_visible = true
 where group_id in (
   'fe92765c-d0db-56e2-82d9-dbe40b98a8dc',  -- Haliimaile Blend
   'a751ae90-e0f3-5fd0-81d9-d9e268adbc63'   -- Haliimaile Blend Decaf
 )
   and is_visible is distinct from true;

do $verify$
declare v_bad int; v_n int;
begin
  select count(*) into v_n from public.product_groups
   where group_id in ('fe92765c-d0db-56e2-82d9-dbe40b98a8dc','a751ae90-e0f3-5fd0-81d9-d9e268adbc63');
  if v_n = 0 then
    raise notice 'neither product exists here; nothing to do';
    return;
  elsif v_n <> 2 then
    raise exception 'expected 2 products, found %', v_n;
  end if;

  select count(*) into v_bad from public.product_groups
   where group_id in ('fe92765c-d0db-56e2-82d9-dbe40b98a8dc','a751ae90-e0f3-5fd0-81d9-d9e268adbc63')
     and is_visible is distinct from true;
  if v_bad > 0 then raise exception '% of the 2 are still hidden', v_bad; end if;

  -- Each still has something to sell, or unhiding shows a buyer an empty product.
  select count(*) into v_bad
    from (values ('fe92765c-d0db-56e2-82d9-dbe40b98a8dc'::uuid),
                 ('a751ae90-e0f3-5fd0-81d9-d9e268adbc63'::uuid)) t(gid)
   where not exists (
     select 1 from public.products p
      where p.group_id = t.gid and p.is_active
        and p.price is not null and p.merge_into_id is null);
  if v_bad > 0 then raise exception '% unhidden product(s) have no sellable variant', v_bad; end if;

  -- Nothing else moved.
  select count(*) into v_bad
    from _before b join public.product_groups g using (group_id)
   where g.is_visible is distinct from b.is_visible
     and g.group_id not in ('fe92765c-d0db-56e2-82d9-dbe40b98a8dc','a751ae90-e0f3-5fd0-81d9-d9e268adbc63');
  if v_bad > 0 then raise exception '% other product(s) changed visibility', v_bad; end if;
end;
$verify$;

commit;
