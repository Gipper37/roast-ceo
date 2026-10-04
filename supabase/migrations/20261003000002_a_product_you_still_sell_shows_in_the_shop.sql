-- A product you still sell shows in the shop.
--
-- 82 MCR product_groups carry is_visible = false while still holding active,
-- priced wholesale variants, and app/(shop)/[slug]/page.tsx:289 filters
-- `g.is_visible !== false`, so none of them can appear on the storefront. They
-- are not obscure: Monin Vanilla has 503 order lines, Monin Macnut 382, Monin
-- Caramel 271. A wholesale buyer logging in today would see 84 coffee products
-- and 26 consumables, with most of the syrup, sauce and tea line missing.
--
-- is_visible = false is what a MERGE sets to retire a losing group. These rows
-- look like they were caught by that rather than hidden deliberately, but
-- "looks like" is not a reason to republish 87 variants.
--
-- 🔴 THE OWNER'S RULE, 2026-10-03: "idk know if their stale but if they've been
-- ordered in the last month you can unhide them for sure." So that is the whole
-- test, and only that: a group somebody ordered from in the last 30 days is a
-- group the roaster still sells. 40 of the 82 qualify. The other 42 stay hidden
-- and stay his to decide.
--
-- THE 40 ARE LISTED BY ID, not selected by a date predicate. `order_date >=
-- current_date - 30` evaluated at write time on 2026-10-03 and evaluated again
-- whenever this runs on staging are two different sets, and a migration that
-- picks different rows depending on when it runs is not a migration. The rule
-- that produced the list is recorded above; the list it produced is below.

begin;

create temporary table _unhide (group_id uuid primary key) on commit drop;
insert into _unhide (group_id) values
  ('23ddf9d9-93f4-5d6e-9508-1a9ac4a82cf7'),   -- Beans World Blend, 1 lines, last 2026-09-29
  ('48810bf1-07ab-5ea0-8daa-65f2329592f5'),   -- Cafiza 566g Jar, 1 lines, last 2026-09-09
  ('a01a0230-40bf-5094-9d31-9a9717d138db'),   -- Chamomile Citrus Tea 50ct, 2 lines, last 2026-09-22
  ('66ca58d7-400e-5b48-8f14-5b88b5296476'),   -- Earl Grey - Decaf 50ct, 1 lines, last 2026-09-15
  ('beb75e44-8768-5489-b590-e82ab1554f0c'),   -- Earl Grey 50ct, 1 lines, last 2026-09-22
  ('a3b41771-5cc5-5dd2-b762-625e3c5101fb'),   -- English Breakfast 50ct, 2 lines, last 2026-09-22
  ('70c2609e-e861-5a8d-b194-31aad64c5070'),   -- Ginger Citrus Tea, 2 lines, last 2026-09-22
  ('26a723f5-8153-59a6-b768-13fadf3659d2'),   -- Green Tea Tropical 50ct, 2 lines, last 2026-09-22
  ('4956706f-6d6a-57b4-959f-1b2cb2a29646'),   -- Guittard Caramel Sauce, 6 lines, last 2026-09-22
  ('05591eff-f470-50df-ac88-8100992c5d76'),   -- Guittard Chocolate Sauce, 5 lines, last 2026-09-29
  ('2fd43d9d-6cd7-5f45-9919-686131948d5c'),   -- Guittard White Chocolate Sauce, 1 lines, last 2026-09-17
  ('2e15c301-0c1a-527a-b7c6-3583449c4635'),   -- Haleakala, 2 lines, last 2026-09-16
  ('91ec4be2-be5a-5b97-94c3-9c5d6dad30cc'),   -- Hibiscus Tea 50/1oz, 1 lines, last 2026-09-28
  ('768fa158-e107-5f16-8150-84df95a4e923'),   -- Jasmin Green Tea 50ct, 2 lines, last 2026-09-22
  ('4dffa8bf-9702-502f-9d95-6abddf1d7340'),   -- Lavender, 4 lines, last 2026-09-21
  ('9003e0c4-69d7-5a2f-b1ca-f6d34e7a7c1c'),   -- Marco's Blend Decaf, 4 lines, last 2026-09-21
  ('aa1ddd50-a5cb-51d2-bf44-bd964b3bb923'),   -- Maui Cat Medium, 1 lines, last 2026-09-23
  ('da9bd478-2765-5ee2-a0cd-4e5b3d9d1216'),   -- Monin Caramel, 6 lines, last 2026-09-18
  ('ff7a2cae-242e-54c6-adaf-f69617d007eb'),   -- Monin Coconut, 19 lines, last 2026-09-29
  ('8824ebdd-6f3e-54de-bd0f-4d9b79dac705'),   -- Monin Frosted Mint, 1 lines, last 2026-09-10
  ('94cdca3a-398b-5f31-9357-748df56fd9c7'),   -- Monin Hazelnut, 6 lines, last 2026-09-21
  ('a4c9c792-605e-58fb-991f-ac28d8925f10'),   -- Monin Irish Cream, 13 lines, last 2026-09-21
  ('11c89691-6289-517b-8e0a-a460aaadd7a2'),   -- Monin Lavendar, 4 lines, last 2026-09-23
  ('320bc28a-a3d9-5071-bc89-90d275e2bca0'),   -- Monin Macnut, 24 lines, last 2026-09-29
  ('f1433dfc-42ba-5879-a98d-d430fbaa377d'),   -- Monin Peach, 2 lines, last 2026-09-21
  ('c1f35919-fcc9-5e64-9594-9421d9114b00'),   -- Monin Raspeberry, 3 lines, last 2026-09-18
  ('db06ca20-dfc0-5c49-b30d-6f94db4f7b65'),   -- Monin SF Caramel, 2 lines, last 2026-09-21
  ('ac70dd9d-441d-5180-813f-544371a64cb4'),   -- Monin SF Hazelnut, 2 lines, last 2026-09-18
  ('be0bbfbf-5c03-5062-9829-d322a195abec'),   -- Monin SF Vanilla, 10 lines, last 2026-09-21
  ('30c0c67f-0bed-51d3-a1ca-fddef38c7e15'),   -- Monin Strawberry, 3 lines, last 2026-09-14
  ('6c7741af-988b-5eee-8f83-3f2d4c22f59a'),   -- Monin Toffee Nut, 1 lines, last 2026-09-16
  ('8b6bbce1-e6f0-5fa7-80de-38eee4449713'),   -- Monin Vanilla, 30 lines, last 2026-09-29
  ('704a7b0e-035d-57d4-b338-d48a0709589a'),   -- Monin Watermelon, 3 lines, last 2026-09-15
  ('777c596b-ab61-54c4-9d50-8d36eb16ac05'),   -- Moroccan Mint Tea 50ct, 2 lines, last 2026-09-22
  ('88ae2627-5d84-5f68-8bbc-db50acae33bd'),   -- Organic Chocolate Macnut, 1 lines, last 2026-09-21
  ('65b2f976-cd1d-574f-a0bb-0367bc71889a'),   -- Organic Coconut, 1 lines, last 2026-09-23
  ('c3b558f1-c489-52d3-b676-5874b800537a'),   -- Organic Hazelnut, 1 lines, last 2026-09-28
  ('ff258c99-4b24-5529-a4dc-9933c2eba06d'),   -- Spice Chai 50ct, 2 lines, last 2026-09-22
  ('fb75ccf9-6822-55ac-ba26-74abf59f2e43'),   -- Wailea Beach Resort Blend, 4 lines, last 2026-09-24
  ('ba390404-dc7d-5edd-8362-68dd4d46692c')   -- Whole Foods Kona - Case, 1 lines, last 2026-09-14
;

create temporary table _before on commit drop as
  select group_id, is_visible from public.product_groups;

update public.product_groups g
   set is_visible = true
  from _unhide u
 where g.group_id = u.group_id
   and g.is_visible is distinct from true;

do $verify$
declare v_bad int; v_n int;
begin
  select count(*) into v_n from _unhide u join public.product_groups g using (group_id);
  if v_n = 0 then
    raise notice 'none of these 40 products exist here; nothing to do';
    return;
  elsif v_n <> 40 then
    raise exception 'only % of the 40 products exist here; the list has drifted', v_n;
  end if;

  -- All 40 are now visible.
  select count(*) into v_bad
    from _unhide u join public.product_groups g using (group_id)
   where g.is_visible is distinct from true;
  if v_bad > 0 then raise exception '% of the 40 are still hidden', v_bad; end if;

  -- 🔴 And NOTHING else moved. This must not republish a product the roaster
  -- retired, which is the whole risk of touching is_visible in bulk.
  select count(*) into v_bad
    from _before b join public.product_groups g using (group_id)
   where g.is_visible is distinct from b.is_visible
     and not exists (select 1 from _unhide u where u.group_id = b.group_id);
  if v_bad > 0 then
    raise exception '% product(s) outside the list changed visibility', v_bad;
  end if;

  -- Every one of them still has something to sell, or unhiding it shows a
  -- buyer an empty product.
  select count(*) into v_bad
    from _unhide u
   where not exists (
     select 1 from public.products p
      where p.group_id = u.group_id and coalesce(p.is_active,true)
        and p.price is not null and p.merge_into_id is null);
  if v_bad > 0 then
    raise exception '% unhidden product(s) have no sellable variant', v_bad;
  end if;
end;
$verify$;

commit;
