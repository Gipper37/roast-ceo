-- The QuickBooks item id says which coffee, so use it.
--
-- 20261001000001 repaired 44 imported lines by matching the QB line's
-- DESCRIPTION against the variant name. That was the wrong key. products
-- carries `qb_item_id`, the QuickBooks item the variant was imported from, on
-- 312 of MCR's 608 variants. Joining on it is exact where the description is a
-- guess, and it immediately found what the name match could not: the roaster
-- does have an "Organic French" product, it is simply not called "Organic
-- French Roast", and `Organic French - 5lbs - Wholesale` already carries
-- qb_item_id `blkr Org French Roast (5lb Organic French Roast)`, the id on
-- every one of those QuickBooks lines.
--
-- MEASURED on prod against the roaster's QB export. Pairing a QB line to a
-- STRATA line only where exactly one of each shares a (quantity, unit price)
-- on an invoice, then resolving the QB item id to a variant:
--   8,573 lines already point at the right variant
--     155 point at a different one
--     307 carry a QB item no STRATA variant claims
--
-- This applies the 45 where the import dropped a qualifier off the front of
-- the name, which is the same defect 20261001000001 fixed and the only shape
-- confident enough to apply without the roaster's eye:
--
--   30 lines  Espresso - 5lbs    -> Organic Espresso - 5lbs
--   12 lines  French Roast - 5lbs -> Organic French - 5lbs
--    3 lines  Espresso - 1lb     -> Organic Espresso - 1lb
--
-- 28 of the 30 were already moved by 20261001000001. This is written as the
-- END STATE rather than as a change, so applying it twice is a no-op.
--
-- 🔴 NOT APPLYING THE OTHER 110, deliberately. The qb_item_id is authoritative
-- about the QuickBooks ITEM, not about which STRATA variant the roaster wants
-- the sale against, and in places this catalogue is finer-grained than the
-- QuickBooks item list. Following the id blindly would repoint
-- `Vanilla Macnut - 5lbs`, `Hula Pie - 5lbs` and `Hawaiian Hazelnut - 5lbs`
-- all onto a single generic `Flavor - 5lbs`, destroying the distinction rather
-- than restoring it. Seven more (the Kona Blend lines) are contradictory
-- inside QuickBooks itself: the item is `blkhr Kona Blend Dark` while the line
-- description reads `5lb Kona Blend ****MEDIUM**** 10%  WB`. Those are the
-- roaster's to settle.
--
-- Weight is unchanged on all 45: every target carries the same weight_lbs as
-- the variant the line is leaving, so roasted demand does not move.
--
-- User triggers are disabled for the same two reasons as 20261001000001:
-- handle_order_detail_logic reprices on a product_id change, and some of these
-- sit on posted orders. The money is asserted byte-identical afterwards.

begin;

create temporary table _before on commit drop as
  select order_detail_id, product_id, quantity, roasted_weight,
         unit_price_at_sale, list_price_total, discount_amount, total_price
    from public.order_details;

create temporary table _fix (order_detail_id text primary key,
                             new_product_id  text not null,
                             new_roasted_weight numeric not null) on commit drop;

insert into _fix (order_detail_id, new_product_id, new_roasted_weight) values
  ('qbimp-od-f39d6355b81e7bd744c1','prod_dc99f80f71f62e27',15.0000),   -- inv 104439: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale
  ('qbimp-od-dd94560eff9acd29bf8d','prod_9748de2bc552bf53',20.0000),   -- inv 104644: French Roast - 5lbs - Wholesale -> Organic French - 5lbs - Wholesale
  ('qbimp-od-e1da3e0b2216701dd15d','prod_9748de2bc552bf53',15.0000),   -- inv 104485: French Roast - 5lbs - Wholesale -> Organic French - 5lbs - Wholesale
  ('qbimp-od-f6ac6ff26e893e141e90','prod_dc99f80f71f62e27',20.0000),   -- inv 104326: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale
  ('qbimp-od-a3c31b7e0d434acbc72c','prod_9748de2bc552bf53',10.0000),   -- inv 104370: French Roast - 5lbs - Wholesale -> Organic French - 5lbs - Wholesale
  ('qbimp-od-519d3b6bb9c6c32283dc','prod_dc99f80f71f62e27',50.0000),   -- inv 104435: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale
  ('qbimp-od-0f0147931f2e5eb51537','prod_9748de2bc552bf53',10.0000),   -- inv 104435: French Roast - 5lbs - Wholesale -> Organic French - 5lbs - Wholesale
  ('qbimp-od-d2844b163de14d5ac654','prod_dc99f80f71f62e27',25.0000),   -- inv 104566: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale
  ('qbimp-od-5245ad7366700e6342e5','prod_dc99f80f71f62e27',20.0000),   -- inv 104482: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale
  ('qbimp-od-cc02d5b7ec9caf16f513','prod_9748de2bc552bf53',25.0000),   -- inv 104420: French Roast - 5lbs - Wholesale -> Organic French - 5lbs - Wholesale
  ('qbimp-od-68b060b566d85b338fc7','prod_dc99f80f71f62e27',10.0000),   -- inv 104593: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale
  ('qbimp-od-8de3f8419b111be06814','prod_9748de2bc552bf53',30.0000),   -- inv 104690: French Roast - 5lbs - Wholesale -> Organic French - 5lbs - Wholesale
  ('qbimp-od-97c9175e04074fed2b6a','prod_dc99f80f71f62e27',10.0000),   -- inv 104548: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale
  ('qbimp-od-b05e85672be0cc30537e','prod_9748de2bc552bf53',25.0000),   -- inv 104349: French Roast - 5lbs - Wholesale -> Organic French - 5lbs - Wholesale
  ('qbimp-od-cfd833a0840c0931b0a7','prod_dc99f80f71f62e27',5.0000),   -- inv 104712: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale
  ('qbimp-od-bad7e9e67904adfe7e0b','prod_dc99f80f71f62e27',20.0000),   -- inv 104688: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale
  ('qbimp-od-060466e87ff8fe7ad92e','prod_dc99f80f71f62e27',25.0000),   -- inv 104524: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale
  ('qbimp-od-3d454bdcea3c2ab04c27','prod_9748de2bc552bf53',30.0000),   -- inv 104517: French Roast - 5lbs - Wholesale -> Organic French - 5lbs - Wholesale
  ('qbimp-od-c11807585c6b51a99d61','prod_dc99f80f71f62e27',20.0000),   -- inv 104461: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale
  ('qbimp-od-7b536c9a0e0d9a8be070','prod_dc99f80f71f62e27',20.0000),   -- inv 104528: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale
  ('qbimp-od-b25d89d33a1c3270245d','prod_dc99f80f71f62e27',25.0000),   -- inv 104527: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale
  ('qbimp-od-2501cc42608712c29d46','prod_dc99f80f71f62e27',5.0000),   -- inv 104373: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale
  ('qbimp-od-389ec96b9b77f04f5472','prod_dc99f80f71f62e27',10.0000),   -- inv 104625: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale
  ('qbimp-od-c9ddb4c48d6b3b80acff','prod_dc99f80f71f62e27',20.0000),   -- inv 104541: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale
  ('qbimp-od-748f57f0fec7501e1562','prod_9748de2bc552bf53',30.0000),   -- inv 104580: French Roast - 5lbs - Wholesale -> Organic French - 5lbs - Wholesale
  ('qbimp-od-305b061d543e59403603','prod_dc99f80f71f62e27',20.0000),   -- inv 104402: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale
  ('qbimp-od-53748689601c2b02aa1a','prod_a1851edad3473e8f',10.0000),   -- inv 104307: Espresso - 1lb - Wholesale -> Organic Espresso - 1lb - Wholesale
  ('qbimp-od-418ffca9c5cd7a7f2dcd','prod_dc99f80f71f62e27',15.0000),   -- inv 104710: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale
  ('qbimp-od-0d3614b84bf0b15d8fe0','prod_dc99f80f71f62e27',5.0000),   -- inv 104438: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale
  ('qbimp-od-4b687e5b4206ed08cef8','prod_dc99f80f71f62e27',10.0000),   -- inv 104374: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale
  ('qbimp-od-5d157e87796149f8386c','prod_dc99f80f71f62e27',10.0000),   -- inv 104309: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale
  ('qbimp-od-6c6b3d46c53c06877331','prod_9748de2bc552bf53',35.0000),   -- inv 104472: French Roast - 5lbs - Wholesale -> Organic French - 5lbs - Wholesale
  ('qbimp-od-38d77fea3fc0364b48b9','prod_dc99f80f71f62e27',15.0000),   -- inv 104365: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale
  ('qbimp-od-48ad5bd49801a06cc3e3','prod_dc99f80f71f62e27',15.0000),   -- inv 104713: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale
  ('qbimp-od-fbc4740f2b6c2f491167','prod_9748de2bc552bf53',30.0000),   -- inv 104348: French Roast - 5lbs - Wholesale -> Organic French - 5lbs - Wholesale
  ('qbimp-od-af1cf736af43fa5daa13','prod_dc99f80f71f62e27',10.0000),   -- inv 104631: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale
  ('qbimp-od-2353785c0760ba50da39','prod_dc99f80f71f62e27',20.0000),   -- inv 104403: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale
  ('qbimp-od-e3132af05f663c3d51c6','prod_a1851edad3473e8f',5.0000),   -- inv 104403: Espresso - 1lb - Wholesale -> Organic Espresso - 1lb - Wholesale
  ('qbimp-od-124b46ce28e9d168158e','prod_dc99f80f71f62e27',25.0000),   -- inv 104607: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale
  ('qbimp-od-27611f909d9dbffc7235','prod_dc99f80f71f62e27',25.0000),   -- inv 104677: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale
  ('qbimp-od-aba840e1350c1361c691','prod_a1851edad3473e8f',10.0000),   -- inv 104404: Espresso - 1lb - Wholesale -> Organic Espresso - 1lb - Wholesale
  ('qbimp-od-ff48929c82c78774e8d3','prod_dc99f80f71f62e27',15.0000),   -- inv 104479: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale
  ('qbimp-od-0be69abb9c9065362231','prod_dc99f80f71f62e27',15.0000),   -- inv 104437: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale
  ('qbimp-od-f5221e3916fa8431baec','prod_dc99f80f71f62e27',25.0000),   -- inv 104598: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale
  ('qbimp-od-64e83e043e7e9ba74ac4','prod_9748de2bc552bf53',15.0000)   -- inv 104598: French Roast - 5lbs - Wholesale -> Organic French - 5lbs - Wholesale
;

alter table public.order_details disable trigger user;

update public.order_details od
   set product_id     = f.new_product_id,
       roasted_weight = f.new_roasted_weight
  from _fix f
 where od.order_detail_id = f.order_detail_id
   and (od.product_id is distinct from f.new_product_id
        or round(coalesce(od.roasted_weight,0)::numeric,4) is distinct from round(f.new_roasted_weight,4));

alter table public.order_details enable trigger user;

do $verify$
declare v_bad int; v_matched int;
begin
  select count(*) into v_matched from _fix f join public.order_details od using (order_detail_id);
  if v_matched = 0 then
    raise notice 'none of these 45 lines exist here; nothing to verify';
    return;
  elsif v_matched <> 45 then
    raise exception 'only % of the 45 lines exist here; the id list has drifted', v_matched;
  end if;

  -- END STATE: every line sits on its intended variant and weight.
  select count(*) into v_bad
    from _fix f join public.order_details od using (order_detail_id)
   where od.product_id is distinct from f.new_product_id
      or round(coalesce(od.roasted_weight,0)::numeric,4) is distinct from round(f.new_roasted_weight,4);
  if v_bad > 0 then raise exception '% line(s) are not in the intended end state', v_bad; end if;

  -- 🔴 The money is byte-identical on every line in the table.
  select count(*) into v_bad
    from _before b join public.order_details a using (order_detail_id)
   where a.unit_price_at_sale is distinct from b.unit_price_at_sale
      or a.list_price_total   is distinct from b.list_price_total
      or a.discount_amount    is distinct from b.discount_amount
      or a.total_price        is distinct from b.total_price
      or a.quantity           is distinct from b.quantity;
  if v_bad > 0 then
    raise exception '% order line(s) had their money or quantity changed; this must change neither', v_bad;
  end if;

  -- Nothing outside the list moved.
  select count(*) into v_bad
    from _before b join public.order_details a using (order_detail_id)
   where (a.product_id is distinct from b.product_id
          or a.roasted_weight is distinct from b.roasted_weight)
     and not exists (select 1 from _fix f where f.order_detail_id = b.order_detail_id);
  if v_bad > 0 then raise exception '% line(s) outside the list changed', v_bad; end if;

  -- Each repaired line now sits on the variant QuickBooks names. Asserted
  -- against qb_item_id rather than against a price, because the price is what
  -- the first pass used and it is the weaker signal.
  select count(*) into v_bad
    from _fix f
    join public.order_details od using (order_detail_id)
    join public.products p on p.product_id = od.product_id
   where p.qb_item_id is null;
  if v_bad > 0 then
    raise exception '% repaired line(s) landed on a variant with no QuickBooks item id', v_bad;
  end if;

  select count(*) into v_bad from pg_trigger
   where tgrelid = 'public.order_details'::regclass and not tgisinternal and tgenabled = 'D';
  if v_bad > 0 then raise exception '% user trigger(s) left disabled on order_details', v_bad; end if;
end;
$verify$;

commit;
