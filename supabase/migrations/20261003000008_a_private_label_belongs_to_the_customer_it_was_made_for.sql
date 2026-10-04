-- A private label belongs to the customer it was made for.
--
-- Seven products named after a single customer are visible to every wholesale
-- account on MCR's storefront, with their prices. Nobody logging in today has
-- seen them -- all 363 tiered customers have zero shop logins -- but the shop is
-- enabled and the first buyer through the door sees the lot.
--
-- product_groups.exclusive_to_customer_ids is the tool for this and it is set on
-- ZERO of MCR's 318 products. The storefront already enforces it, allowlist
-- wins, hidden from guests entirely (app/(shop)/[slug]/page.tsx:346).
--
-- RESTRICTED HERE: the four where the order history says, without ambiguity,
-- who the product was made for.
--
--   Kraken Coffee ................ 504 lines, and ALL of them across the four
--                                  live Kraken stores. Allowlisted to all four.
--   Mama's Fish House Espresso ... 55 lines, Mamas Fish House only
--   Mama's Fish House Mokka ...... 4 lines, Mamas Fish House only
--   Nobu Blend Espresso .......... 15 lines, Nobu/Grand Wailea only
--
-- 🔴 KRAKEN IS THE CHAIN CASE, and it is why the owner asked for exclusive-to-
-- CHAIN rather than per customer. Listing four customer ids works because the
-- column is an array, but it is a list somebody has to remember to extend when
-- Kraken opens a fifth store -- and Kraken Coffee-Lahaina already exists,
-- inactive since the fire, and is deliberately NOT on this list. A chain
-- reference would say the thing once. Recorded on the open list; not built here.
--
-- NOT RESTRICTED, deliberately, because the data does not say who they belong to:
--   Costco Maui Blend .... bought by THREE customers: Costco Wholesale (44
--                          lines), Island Grocery Depot Kahului (9) and Helly
--                          Associates (4). Not exclusive to anyone.
--   Maui Blend Safeway ... zero order lines, ever.
--   Maui Resort Rentals .. zero order lines, ever. The customer of that name is
--     Maui Blend          MCR's 4th largest, so the product is probably theirs,
--                         but probably is not evidence.
-- Those three stay visible and stay the owner's call. Guessing wrong hides a
-- product from the customer who buys it, which is the same harm pointing the
-- other way.

begin;

create temporary table _before on commit drop as
  select group_id, exclusive_to_customer_ids from public.product_groups;

update public.product_groups
   set exclusive_to_customer_ids = array[
     'mcrimp-cust-d08432ef51c510',       -- Kraken Coffee-Kahului
     'mcrimp-cust-43e78e9da69842',       -- Kraken Coffee-Kihei
     'mcrimp-cust-7f6bc70d5c5d39',       -- Kraken Coffee-Kihei Marketplace
     'mcrimp-cust-0c2288a028b242'        -- Kraken Coffee - Wailea
   ]
 where group_id = '94528e0c-db4f-44b7-8406-97ec6658a683';

update public.product_groups
   set exclusive_to_customer_ids = array['mcrimp-cust-36614ff9280eed']   -- Mamas Fish House
 where group_id in ('bb4c8c13-c400-4d88-8144-b9fb3c93bff2',   -- Espresso
                    'f32a594d-9c81-4035-882e-e78fe6c4e133');  -- Mokka

update public.product_groups
   set exclusive_to_customer_ids = array['mcrimp-cust-ee139bb2686563']   -- Nobu/Grand Wailea
 where group_id = '8fe36eff-4341-4ba5-8d24-8dd83204b776';

do $verify$
declare v_bad int; v_n int;
begin
  select count(*) into v_n from public.product_groups
   where group_id in ('94528e0c-db4f-44b7-8406-97ec6658a683','bb4c8c13-c400-4d88-8144-b9fb3c93bff2',
                      'f32a594d-9c81-4035-882e-e78fe6c4e133','8fe36eff-4341-4ba5-8d24-8dd83204b776');
  if v_n = 0 then raise notice 'none of these four products exist here'; return;
  elsif v_n <> 4 then raise exception 'only % of the 4 products exist here', v_n; end if;

  -- All four are restricted to somebody.
  select count(*) into v_bad from public.product_groups
   where group_id in ('94528e0c-db4f-44b7-8406-97ec6658a683','bb4c8c13-c400-4d88-8144-b9fb3c93bff2',
                      'f32a594d-9c81-4035-882e-e78fe6c4e133','8fe36eff-4341-4ba5-8d24-8dd83204b776')
     and coalesce(array_length(exclusive_to_customer_ids, 1), 0) = 0;
  if v_bad > 0 then raise exception '% of the 4 are still visible to everyone', v_bad; end if;

  -- 🔴 EVERY customer named is a real customer OF THIS COMPANY. An id that does
  -- not resolve would hide the product from everyone including its owner,
  -- silently, because the allowlist wins and matches nobody.
  select count(*) into v_bad
    from public.product_groups g,
         lateral unnest(g.exclusive_to_customer_ids) AS cid
   where g.company_id = '9ShiyDAXhV'
     and not exists (select 1 from public.customers c
                      where c.customer_id = cid and c.company_id = g.company_id);
  if v_bad > 0 then
    raise exception '% allowlist entry(ies) name a customer that does not exist in this company', v_bad;
  end if;

  -- 🔴 And every customer who has ACTUALLY BOUGHT one of these four can still
  -- see it. This is the assertion that catches a wrong guess: restricting a
  -- product away from the people who buy it is the same harm as leaking it.
  select count(*) into v_bad
    from (select distinct g.group_id, o.customer_id
            from public.product_groups g
            join public.products p on p.group_id = g.group_id
            join public.order_details od on od.product_id = p.product_id
            join public.orders o on o.order_id = od.order_id
           where g.group_id in ('94528e0c-db4f-44b7-8406-97ec6658a683','bb4c8c13-c400-4d88-8144-b9fb3c93bff2',
                                'f32a594d-9c81-4035-882e-e78fe6c4e133','8fe36eff-4341-4ba5-8d24-8dd83204b776')
             and coalesce(o.order_status,'') <> 'Canceled') buyers
    join public.product_groups g using (group_id)
   where not (buyers.customer_id = any(g.exclusive_to_customer_ids));
  if v_bad > 0 then
    raise exception '% customer(s) who have bought one of these can no longer see it', v_bad;
  end if;

  -- Nothing else was restricted.
  select count(*) into v_bad
    from _before b join public.product_groups g using (group_id)
   where g.exclusive_to_customer_ids is distinct from b.exclusive_to_customer_ids
     and g.group_id not in ('94528e0c-db4f-44b7-8406-97ec6658a683','bb4c8c13-c400-4d88-8144-b9fb3c93bff2',
                            'f32a594d-9c81-4035-882e-e78fe6c4e133','8fe36eff-4341-4ba5-8d24-8dd83204b776');
  if v_bad > 0 then raise exception '% other product(s) had their allowlist changed', v_bad; end if;
end;
$verify$;

commit;
