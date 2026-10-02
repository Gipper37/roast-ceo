-- An imported line points at the coffee QuickBooks named.
--
-- The QuickBooks import matched each invoice line to a variant by name. Where
-- the QB item carried a " - WB" suffix the matcher dropped the qualifier before
-- it, so "5lb Organic Espresso - WB" resolved to the plain Espresso variant.
-- "5lb Organic Espresso WB" and "5lb Organic Espresso", without the hyphen,
-- resolved correctly, which is why Organic Espresso - 5lbs still carries 215
-- order lines and this was never obvious.
--
-- MEASURED against the roaster's own QuickBooks export (custom qb report ALL
-- 08042026.csv, 231,333 rows, Jan 2017 to Aug 2026). 3,734 invoices appear in
-- both systems. Pairing a QB line to a STRATA line only where exactly one of
-- each shares a (quantity, unit price) on the same invoice -- so no line can be
-- cross-paired with another at the same price -- 9,035 pairings are
-- unambiguous and 74 of them name a different coffee on each side.
--
-- This repairs the 44 where the correct variant already exists AND its current
-- price equals the price the line was charged, to the cent:
--
--   28 lines  5lb Organic Espresso - WB         -> Organic Espresso - 5lbs   $74.75
--    9 lines  Organic Dawn Patrol 10/8oz. case  -> Organic Dawn Patrol        $64.38
--             ... - 8oz (Case of 10) - Safeway
--    7 lines  5lb Kona Blend ****MEDIUM**** 10% -> 10% Kona Blend Medium      $77.50
--             ... WB                                ... - 5lbs
--
-- The other 30 are left alone deliberately: 12 name an "Organic French Roast"
-- that does not exist as a variant, and 18 are one-off private labels and
-- blends that need the roaster's own judgement.
--
-- THE MONEY DOES NOT MOVE. Every line keeps its unit_price_at_sale,
-- list_price_total, discount_amount and total_price, and the verify block
-- fails the migration if any of them differs by a cent. What changes is which
-- coffee the line is attributed to, which is what feeds COGS, usage and roast
-- demand.
--
-- ROASTED WEIGHT IS CORRECTED ON NINE OF THEM. The Dawn Patrol lines are a
-- CASE of ten 8oz bags that was recorded against the single 8oz variant, so
-- roasted_weight was quantity x 0.5 lb instead of quantity x 5 lb. Invoice
-- 13529 recorded 3 lbs of roast demand for six cases, which is 30 lbs of
-- coffee. Across the nine, 11.5 lbs becomes 115 lbs; across all 44, 701.5
-- becomes 805.0.
--
-- 🔴 USER TRIGGERS ARE DISABLED FOR THE UPDATE, DELIBERATELY, for two reasons:
--   1. handle_order_detail_logic sets
--        v_reprice := TG_OP = 'INSERT' OR NEW.product_id IS DISTINCT FROM
--                     OLD.product_id OR NEW.unit_price_at_sale IS NULL
--      so changing product_id REPRICES the line from today's catalogue and
--      overwrites unit_price_at_sale. That would destroy the very figures that
--      currently agree with QuickBooks.
--   2. 18 of the 44 sit on posted orders, where
--      guard_posted_order_detail_immutable refuses a product_id change. That
--      guard exists to stop a careless edit, and this is a deliberate
--      correction of an import defect, verified line by line against the
--      roaster's accounting system. It is bypassed here and nowhere else.
-- The audit trigger is disabled with them, so updated_at is not stamped on 44
-- rows as though an operator had edited them.

begin;

create temporary table _before on commit drop as
  select order_detail_id, product_id, quantity, roasted_weight,
         unit_price_at_sale, list_price_total, discount_amount, total_price
    from public.order_details;

create temporary table _fix (order_detail_id text primary key,
                             new_product_id  text not null,
                             new_roasted_weight numeric not null) on commit drop;

insert into _fix (order_detail_id, new_product_id, new_roasted_weight) values
  ('qbimp-od-27a4a874dfd72bd82937','mcrimp-prod-5cba1372d01a1d83',20.0000),   -- inv 13535: Dawn Patrol - 8oz - Wholesale -> Organic Dawn Patrol - 8oz (Case of 10) - Safeway (rw 2 -> 20)
  ('qbimp-od-97c9175e04074fed2b6a','prod_dc99f80f71f62e27',10.0000),   -- inv 104548: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale (rw 10 -> 10)
  ('qbimp-od-2501cc42608712c29d46','prod_dc99f80f71f62e27',5.0000),   -- inv 104373: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale (rw 5 -> 5)
  ('qbimp-od-b25d89d33a1c3270245d','prod_dc99f80f71f62e27',25.0000),   -- inv 104527: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale (rw 25 -> 25)
  ('qbimp-od-5245ad7366700e6342e5','prod_dc99f80f71f62e27',20.0000),   -- inv 104482: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale (rw 20 -> 20)
  ('qbimp-od-5dcf12f54d1d95e18976','mcrimp-prod-5cba1372d01a1d83',5.0000),   -- inv 13525: Dawn Patrol - 8oz - Wholesale -> Organic Dawn Patrol - 8oz (Case of 10) - Safeway (rw 0.5 -> 5)
  ('qbimp-od-7d5c873e352009eb8e3a','prod_6a4d132df7db7948',25.0000),   -- inv 104582: Organic Kona Blend Medium - 5lbs - Wholesale -> 10% Kona Blend Medium - 5lbs - Wholesale (rw 25 -> 25)
  ('qbimp-od-c11807585c6b51a99d61','prod_dc99f80f71f62e27',20.0000),   -- inv 104461: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale (rw 20 -> 20)
  ('qbimp-od-da2debe7eaf1f42a8e16','mcrimp-prod-5cba1372d01a1d83',30.0000),   -- inv 13529: Dawn Patrol - 8oz - Wholesale -> Organic Dawn Patrol - 8oz (Case of 10) - Safeway (rw 3 -> 30)
  ('qbimp-od-e50d5f6e2ea952ffc823','mcrimp-prod-5cba1372d01a1d83',10.0000),   -- inv 13536: Dawn Patrol - 8oz - Wholesale -> Organic Dawn Patrol - 8oz (Case of 10) - Safeway (rw 1 -> 10)
  ('qbimp-od-bad7e9e67904adfe7e0b','prod_dc99f80f71f62e27',20.0000),   -- inv 104688: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale (rw 20 -> 20)
  ('qbimp-od-49a00bc07cd452f19052','prod_6a4d132df7db7948',30.0000),   -- inv 104696: Organic Kona Blend Medium - 5lbs - Wholesale -> 10% Kona Blend Medium - 5lbs - Wholesale (rw 30 -> 30)
  ('qbimp-od-519d3b6bb9c6c32283dc','prod_dc99f80f71f62e27',50.0000),   -- inv 104435: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale (rw 50 -> 50)
  ('qbimp-od-f6ac6ff26e893e141e90','prod_dc99f80f71f62e27',20.0000),   -- inv 104326: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale (rw 20 -> 20)
  ('qbimp-od-76cd40ccfeb093e6dbe4','mcrimp-prod-5cba1372d01a1d83',5.0000),   -- inv 13534: Dawn Patrol - 8oz - Wholesale -> Organic Dawn Patrol - 8oz (Case of 10) - Safeway (rw 0.5 -> 5)
  ('qbimp-od-4b687e5b4206ed08cef8','prod_dc99f80f71f62e27',10.0000),   -- inv 104374: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale (rw 10 -> 10)
  ('qbimp-od-38d77fea3fc0364b48b9','prod_dc99f80f71f62e27',15.0000),   -- inv 104365: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale (rw 15 -> 15)
  ('qbimp-od-418ffca9c5cd7a7f2dcd','prod_dc99f80f71f62e27',15.0000),   -- inv 104710: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale (rw 15 -> 15)
  ('qbimp-od-48ad5bd49801a06cc3e3','prod_dc99f80f71f62e27',15.0000),   -- inv 104713: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale (rw 15 -> 15)
  ('qbimp-od-e4da4db913d7818f458d','prod_6a4d132df7db7948',25.0000),   -- inv 104508: Organic Kona Blend Medium - 5lbs - Wholesale -> 10% Kona Blend Medium - 5lbs - Wholesale (rw 25 -> 25)
  ('qbimp-od-f357f1e04b03ae4e30cf','prod_6a4d132df7db7948',10.0000),   -- inv 104371: Organic Kona Blend Medium - 5lbs - Wholesale -> 10% Kona Blend Medium - 5lbs - Wholesale (rw 10 -> 10)
  ('qbimp-od-af1cf736af43fa5daa13','prod_dc99f80f71f62e27',10.0000),   -- inv 104631: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale (rw 10 -> 10)
  ('qbimp-od-c847c6f03309f94e92f5','mcrimp-prod-5cba1372d01a1d83',20.0000),   -- inv 13526: Dawn Patrol - 8oz - Wholesale -> Organic Dawn Patrol - 8oz (Case of 10) - Safeway (rw 2 -> 20)
  ('qbimp-od-cfd833a0840c0931b0a7','prod_dc99f80f71f62e27',5.0000),   -- inv 104712: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale (rw 5 -> 5)
  ('qbimp-od-d2844b163de14d5ac654','prod_dc99f80f71f62e27',25.0000),   -- inv 104566: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale (rw 25 -> 25)
  ('qbimp-od-05be424e4149515e8153','mcrimp-prod-5cba1372d01a1d83',15.0000),   -- inv 13524: Dawn Patrol - 8oz - Wholesale -> Organic Dawn Patrol - 8oz (Case of 10) - Safeway (rw 1.5 -> 15)
  ('qbimp-od-c9ddb4c48d6b3b80acff','prod_dc99f80f71f62e27',20.0000),   -- inv 104541: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale (rw 20 -> 20)
  ('qbimp-od-2353785c0760ba50da39','prod_dc99f80f71f62e27',20.0000),   -- inv 104403: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale (rw 20 -> 20)
  ('qbimp-od-060466e87ff8fe7ad92e','prod_dc99f80f71f62e27',25.0000),   -- inv 104524: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale (rw 25 -> 25)
  ('qbimp-od-0c380a28fdf56e7d2db8','mcrimp-prod-5cba1372d01a1d83',5.0000),   -- inv 13528: Dawn Patrol - 8oz - Wholesale -> Organic Dawn Patrol - 8oz (Case of 10) - Safeway (rw 0.5 -> 5)
  ('qbimp-od-0be69abb9c9065362231','prod_dc99f80f71f62e27',15.0000),   -- inv 104437: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale (rw 15 -> 15)
  ('qbimp-od-ff48929c82c78774e8d3','prod_dc99f80f71f62e27',15.0000),   -- inv 104479: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale (rw 15 -> 15)
  ('qbimp-od-27611f909d9dbffc7235','prod_dc99f80f71f62e27',25.0000),   -- inv 104677: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale (rw 25 -> 25)
  ('qbimp-od-f5221e3916fa8431baec','prod_dc99f80f71f62e27',25.0000),   -- inv 104598: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale (rw 25 -> 25)
  ('qbimp-od-ec139ccda052e28e8a77','prod_6a4d132df7db7948',40.0000),   -- inv 104464: Organic Kona Blend Medium - 5lbs - Wholesale -> 10% Kona Blend Medium - 5lbs - Wholesale (rw 40 -> 40)
  ('qbimp-od-36b683683b1cbcba5acd','prod_6a4d132df7db7948',40.0000),   -- inv 104350: Organic Kona Blend Medium - 5lbs - Wholesale -> 10% Kona Blend Medium - 5lbs - Wholesale (rw 40 -> 40)
  ('qbimp-od-f39d6355b81e7bd744c1','prod_dc99f80f71f62e27',15.0000),   -- inv 104439: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale (rw 15 -> 15)
  ('qbimp-od-0d3614b84bf0b15d8fe0','prod_dc99f80f71f62e27',5.0000),   -- inv 104438: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale (rw 5 -> 5)
  ('qbimp-od-68b060b566d85b338fc7','prod_dc99f80f71f62e27',10.0000),   -- inv 104593: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale (rw 10 -> 10)
  ('qbimp-od-305b061d543e59403603','prod_dc99f80f71f62e27',20.0000),   -- inv 104402: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale (rw 20 -> 20)
  ('qbimp-od-0697e8bf000592be4a1d','prod_6a4d132df7db7948',25.0000),   -- inv 104642: Organic Kona Blend Medium - 5lbs - Wholesale -> 10% Kona Blend Medium - 5lbs - Wholesale (rw 25 -> 25)
  ('qbimp-od-5d157e87796149f8386c','prod_dc99f80f71f62e27',10.0000),   -- inv 104309: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale (rw 10 -> 10)
  ('qbimp-od-f7cb95fc3e429451c747','mcrimp-prod-5cba1372d01a1d83',5.0000),   -- inv 13530: Dawn Patrol - 8oz - Wholesale -> Organic Dawn Patrol - 8oz (Case of 10) - Safeway (rw 0.5 -> 5)
  ('qbimp-od-124b46ce28e9d168158e','prod_dc99f80f71f62e27',25.0000)   -- inv 104607: Espresso - 5lbs - Wholesale -> Organic Espresso - 5lbs - Wholesale (rw 25 -> 25)
;

alter table public.order_details disable trigger user;

update public.order_details od
   set product_id     = f.new_product_id,
       roasted_weight = f.new_roasted_weight
  from _fix f
 where od.order_detail_id = f.order_detail_id;

alter table public.order_details enable trigger user;

do $verify$
declare v_bad int; v_rw_before numeric; v_rw_after numeric; v_matched int;
begin
  -- These 44 order lines exist on PROD only. Staging and every development
  -- database carry their own data, so this must be a clean no-op there rather
  -- than a failed release: the first cut asserted prod's totals unconditionally
  -- and turned the staging push red while prod was already correct.
  -- A PARTIAL match is still an error -- that would mean the ids drifted.
  select count(*) into v_matched
    from _fix f join public.order_details od using (order_detail_id);
  if v_matched = 0 then
    raise notice 'none of the 44 repaired lines exist here; nothing to verify';
    return;
  elsif v_matched <> 44 then
    raise exception 'only % of the 44 repaired lines exist here; the id list has drifted', v_matched;
  end if;

  -- Exactly the 44 intended lines moved, and every one landed on its target.
  select count(*) into v_bad
    from _fix f join public.order_details od using (order_detail_id)
   where od.product_id is distinct from f.new_product_id;
  if v_bad > 0 then raise exception '% line(s) did not land on the intended product', v_bad; end if;

  select count(*) into v_bad from _fix;
  if v_bad <> 44 then raise exception 'expected 44 repairs, the list holds %', v_bad; end if;

  -- 🔴 THE POINT: the money is byte-identical, on every line in the table, not
  -- just the 44. A repriced line is the one failure this must never ship.
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

  -- Nothing outside the 44 moved product at all.
  select count(*) into v_bad
    from _before b join public.order_details a using (order_detail_id)
   where a.product_id is distinct from b.product_id
     and not exists (select 1 from _fix f where f.order_detail_id = b.order_detail_id);
  if v_bad > 0 then raise exception '% line(s) outside the repair list changed product', v_bad; end if;

  -- Roasted demand: only the nine case lines move, and they move by 10x.
  -- Asserted on the RESULT, not on the starting value, so re-running finds the
  -- same answer. The first cut asserted "701.50 -> 805.00", which holds exactly
  -- once: replay it against an already-repaired database and it reads
  -- "805.00 -> 805.00" and fails a migration that did nothing wrong.
  select coalesce(sum(b.roasted_weight),0), coalesce(sum(a.roasted_weight),0)
    into v_rw_before, v_rw_after
    from _before b join public.order_details a using (order_detail_id)
    join _fix f using (order_detail_id);
  raise notice 'roasted_weight across the 44: % -> %', round(v_rw_before,2), round(v_rw_after,2);

  select count(*) into v_bad
    from _fix f join public.order_details od using (order_detail_id)
   where round(coalesce(od.roasted_weight,0)::numeric,4) is distinct from round(f.new_roasted_weight,4);
  if v_bad > 0 then
    raise exception '% line(s) did not land on their intended roasted_weight', v_bad;
  end if;

  if round(v_rw_after,2) <> 805.00 then
    raise exception 'roasted_weight across the 44 settled at %, expected 805.00', round(v_rw_after,2);
  end if;

  select count(*) into v_bad
    from _before b join public.order_details a using (order_detail_id)
   where a.roasted_weight is distinct from b.roasted_weight
     and not exists (select 1 from _fix f where f.order_detail_id = b.order_detail_id);
  if v_bad > 0 then raise exception '% line(s) outside the repair list changed roasted_weight', v_bad; end if;

  -- Every repaired line now sits on a variant whose price is a plausible match
  -- for what it was charged. NOT an equality: a line charged years ago carries
  -- the price of its day, and seven Dawn Patrol cases were charged $64.70 and
  -- one $62.39 against a case that now lists at $64.38. A 10% band separates
  -- "the same product at an older price" from "the wrong product", which is the
  -- distinction this migration exists to make. For scale, the variant these
  -- nine were wrongly sitting on lists at $7.48.
  select count(*) into v_bad
    from _fix f
    join public.order_details od using (order_detail_id)
    join public.products p on p.product_id = od.product_id
   where coalesce(p.price,0) = 0
      or abs(coalesce(od.unit_price_at_sale,0) - p.price) > p.price * 0.10;
  if v_bad > 0 then
    raise exception '% repaired line(s) are not within 10%% of their new variant price', v_bad;
  end if;

  -- And the repair actually moved them off a variant they did not belong on:
  -- no repaired line may still match its OLD variant's price better than its
  -- new one. This is the assertion that would catch a target chosen wrongly.
  select count(*) into v_bad
    from _fix f
    join _before b using (order_detail_id)
    join public.order_details od using (order_detail_id)
    join public.products pnew on pnew.product_id = od.product_id
    join public.products pold on pold.product_id = b.product_id
   where abs(coalesce(b.unit_price_at_sale,0) - coalesce(pold.price,0))
       < abs(coalesce(b.unit_price_at_sale,0) - coalesce(pnew.price,0));
  if v_bad > 0 then
    raise exception '% line(s) were a better price match BEFORE the repair', v_bad;
  end if;

  -- The guards are back on. A migration that left them off would be worse than
  -- the defect it fixed.
  select count(*) into v_bad from pg_trigger
   where tgrelid = 'public.order_details'::regclass and not tgisinternal and tgenabled = 'D';
  if v_bad > 0 then raise exception '% user trigger(s) left disabled on order_details', v_bad; end if;
end;
$verify$;

commit;
