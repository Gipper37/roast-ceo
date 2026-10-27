-- Backfill the grind off non-coffee lines.
--
-- Owner, 2026-10-27: *"i thought we fixed that auto stamp on consumables and
-- backfilled the mistakes?"* Half right, and the half that was missed is this
-- one. The WRITE paths were fixed (lib/orders/coffeePrep.ts, 2026-10-25) and
-- they worked: production has written no stamped non-coffee line since
-- 2026-10-22, and 57 such lines on the 26th and 27th all came through clean.
--
-- The historical rows were never cleaned. 582 of them, written between
-- 2026-08-07 and 2026-10-22, still hold 'Whole Bean':
--
--     ptype_consumable   544
--     ptype_service       29
--     ptype_equipment      8
--     ptype_discount       1
--
-- They print. A bottle of Monin on a packing slip reading "Whole Bean" is
-- wrong in the packer's hand and wrong in the customer's box, and as of today
-- those lines reach three documents rather than one: the slip, the printed
-- invoice and the emailed PDF.
--
-- The render-time rule (coffeePrep.prepFor) suppresses them whatever the data
-- says, and that stays -- it has to, because it is what guards the future if a
-- write path is ever added without the check. But a display rule papering over
-- wrong data is not the same as right data, and anything reading the column
-- directly still sees 'Whole Bean'.
--
-- 🔴 SCOPED BY PRODUCT TYPE, NOT BY DATE. The window happens to be Aug-Oct,
-- but the thing that makes a row wrong is the product being unbaggable, not
-- when it was written. A date predicate would leave anything older untouched
-- for no reason and would need revising the moment another one turned up.
--
-- 🔴 NULL, NOT EMPTY STRING. 3,993 correct non-coffee lines already hold NULL;
-- writing '' would create a second way of saying "no grind" for the readers
-- that check `is null`.
--
-- Not reversible in the sense that the old values are not kept, and that is
-- deliberate: the old value was 'Whole Bean' on a product that cannot be
-- ground, which is not information worth preserving.

begin;

do $$
declare
  v_before int;
  v_after  int;
  v_coffee_before int;
  v_coffee_after  int;
begin
  select count(*) into v_before
    from public.order_details od
    join public.products p on p.product_id = od.product_id
   where p.product_type in ('ptype_consumable','ptype_equipment','ptype_service','ptype_discount')
     and od.coffee_prep is not null and btrim(od.coffee_prep) <> '';

  -- The coffee lines that must NOT move, counted before and after. This is the
  -- assertion that matters: the risk here is not failing to clear a syrup, it
  -- is clearing a real coffee line and having a packer bag the wrong thing.
  select count(*) into v_coffee_before
    from public.order_details od
    join public.products p on p.product_id = od.product_id
   where p.product_type not in ('ptype_consumable','ptype_equipment','ptype_service','ptype_discount')
     and od.coffee_prep is not null and btrim(od.coffee_prep) <> '';

  update public.order_details od
     set coffee_prep = null
    from public.products p
   where p.product_id = od.product_id
     and p.product_type in ('ptype_consumable','ptype_equipment','ptype_service','ptype_discount')
     and od.coffee_prep is not null
     and btrim(od.coffee_prep) <> '';

  select count(*) into v_after
    from public.order_details od
    join public.products p on p.product_id = od.product_id
   where p.product_type in ('ptype_consumable','ptype_equipment','ptype_service','ptype_discount')
     and od.coffee_prep is not null and btrim(od.coffee_prep) <> '';

  select count(*) into v_coffee_after
    from public.order_details od
    join public.products p on p.product_id = od.product_id
   where p.product_type not in ('ptype_consumable','ptype_equipment','ptype_service','ptype_discount')
     and od.coffee_prep is not null and btrim(od.coffee_prep) <> '';

  if v_after <> 0 then
    raise exception '% non-coffee line(s) still carry a grind', v_after;
  end if;
  if v_coffee_after <> v_coffee_before then
    raise exception 'COFFEE LINES WERE TOUCHED: % before, % after', v_coffee_before, v_coffee_after;
  end if;

  raise notice 'cleared the grind off % non-coffee line(s); % coffee line(s) untouched',
    v_before, v_coffee_after;
end $$;

commit;
