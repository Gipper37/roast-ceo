-- Finish the job: no label anywhere keeps a roll price.
--
-- 20260926000001 corrected the 31 labels that had a roll price in BOTH cost
-- columns and no purchase behind them. It deliberately left nine others alone,
-- which was the wrong call and the owner said so.
--
-- Those nine hold a correct per-label price in last_cost_unit AND a roll price
-- in fallback_unit_cost:
--
--   8oz Dawn Patrol Label                 0.28571   fallback 122.50
--   Mama's Organic Label                  0.163     fallback  85.00
--   16oz Nicky Beans Kona Label - Silver  0.167     fallback  85.00
--   8oz Hula Label - Black                0.18      fallback  85.00   (57 BOMs)
--   16oz Hula Label - Black               0.18      fallback  85.00   (74 BOMs)
--   Strip Kona Estate Light               0.0618    fallback  75.00
--   Strip Kona Estate Dark                0.0808    fallback  75.00
--   Oval Ground                           0.09414   fallback  70.00
--   Oval Wholebean                        0.09414   fallback  70.00
--
-- WHY I LEFT THEM, AND WHY THAT WAS WRONG. I reasoned that dividing by 1000
-- would be a guess — their implied roll sizes are 429 to 1214, not 1000 — and
-- that the fallback is never consulted for an item that has purchases. Both
-- facts are true and the conclusion was still wrong: a roll price sitting in a
-- per-unit column is wrong whether or not anything reads it today, and one
-- careless change to get_consumable_cost_on_date's precedence would make all
-- nine live at once. Two of them are in 57 and 74 bills of materials.
--
-- AND THE DIVISOR WAS NEVER NEEDED. Every one of these has a real purchase, so
-- the correct per-label price is already known and sitting in the next column.
-- Copying it is not a guess; dividing by 1000 would have been. That is the
-- distinction 20260908000011 got wrong in the other direction when it moved
-- these items from a real per-unit figure TO a case price.

begin;

create temporary table _fallback_fix on commit drop as
  select ci.consumable_inventory_id as id,
         ci.fallback_unit_cost      as old_fallback,
         ci.last_cost_unit          as true_unit_price
    from public.consumable_inventory ci
    join public.consumable_type ct on ct.consumable_type_id = ci.consumable_type
   where ct.consumable_type = 'Label (BOM)'
     and ci.fallback_unit_cost is not null
     and ci.last_cost_unit is not null
     and ci.last_cost_unit > 0
     and ci.fallback_unit_cost > ci.last_cost_unit * 10;   -- an order of magnitude apart is a unit mix-up, not a price change

update public.consumable_inventory ci
   set fallback_unit_cost = f.true_unit_price
  from _fallback_fix f
 where ci.consumable_inventory_id = f.id;

do $verify$
declare v_fixed int; v_left int; v_broke int;
begin
  select count(*) into v_fixed from _fallback_fix;

  -- No label may keep a fallback an order of magnitude above its own unit price.
  select count(*) into v_left
    from public.consumable_inventory ci
    join public.consumable_type ct on ct.consumable_type_id = ci.consumable_type
   where ct.consumable_type = 'Label (BOM)'
     and ci.fallback_unit_cost is not null and ci.last_cost_unit is not null
     and ci.last_cost_unit > 0
     and ci.fallback_unit_cost > ci.last_cost_unit * 10;
  if v_left > 0 then raise exception '% label(s) still hold a roll price in fallback', v_left; end if;

  -- And no label anywhere is priced like a roll in either column.
  select count(*) into v_broke
    from public.consumable_inventory ci
    join public.consumable_type ct on ct.consumable_type_id = ci.consumable_type
   where ct.consumable_type = 'Label (BOM)'
     and (ci.last_cost_unit >= 50 or ci.fallback_unit_cost >= 50);
  if v_broke > 0 then raise exception '% label(s) still priced above $50', v_broke; end if;

  raise notice '% label fallback(s) set to the purchased per-label price; no label priced like a roll anywhere', v_fixed;
end $verify$;

commit;
