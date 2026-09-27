-- The 2oz packets come off the 2oz roast.
--
-- MCR roasts Maui Blend at three levels from one green recipe (45% Fruit /
-- 45% Chocolate / 10% Maui H3): MB LT, MB DK and MB Med (2oz). LT and DK are a
-- SPLIT ROAST — 205 charged roasts each since 2026-05-05, never a day where the
-- counts differ, combined into one product — so it is correct that the Maui
-- Blend products point at MB DK and none at MB LT.
--
-- MB Med (2oz) is different. It is its own roast: 21 roasts all time, on days
-- with and without LT/DK, average charge 61.4 lb against LT/DK's flat 75. And
-- NO product points at it, so the roast plan has never been able to ask for it
-- while the roasters have gone on roasting it every month.
--
-- The four 2oz variants point at MB DK instead — the dark roast:
--
--     Maui Blend  2oz                             0.125 lb     7 order lines
--     Maui Blend  2oz case 40                       5.0 lb    96
--     Maui Blend  80-count 2oz case (labeled)      10.0 lb   128
--     Maui Blend  80-count 2oz case (no label)     10.0 lb     1
--
-- THIS IS A COPIED FACT, NOT A NAME MATCH. Compared over the period where both
-- histories exist (roast_log starts 2026-05-05; the order history is imported
-- and reaches back to 2025-06):
--
--     month     2oz ordered lb    MB Med roasted lb
--     2026-05        381                151
--     2026-06        215                197
--     2026-07        370                197
--     2026-08          5                320
--     2026-09        270                197
--     TOTAL        1,241              1,062     <- 86%
--
-- The two series track within 15% over five months while MB Med has no product
-- at all. (Compared over ALL time the figures are 5,145 vs 1,062, which looks
-- like a contradiction and is not: the orders reach back a year further than
-- the roasts do. That mismatch is why this is stated as an overlap comparison.)
--
-- Scope: the four ACTIVE variants. The one inactive 2oz row
-- (prod_6629d40b5b79b560) is left alone — it is not orderable, so repointing it
-- would change a retired record for no gain.
--
-- What this does NOT touch: order history. products.recipe_id is current state,
-- not a snapshot, and no issued invoice reprices from it.

begin;

update public.products p
   set recipe_id = 'rcp-mcr-mb-med-2oz'
 where p.recipe_id = 'rcp-mcr-mb-dk'
   and p.is_active
   and exists (
     select 1 from public.size s
      where s.size_id = p.size
        and s.size_name in ('2oz', '2oz case 40',
                            '80-count 2oz case (labeled)',
                            '80-count 2oz case (no label)'));

do $verify$
declare v_moved int; v_left int; v_orphan int;
begin
  select count(*) into v_moved from public.products
   where recipe_id = 'rcp-mcr-mb-med-2oz' and is_active;
  if v_moved = 0 then
    raise exception 'no active variant ended up on the 2oz roast';
  end if;

  -- Nothing 2oz may still be sitting on the dark roast.
  select count(*) into v_left
    from public.products p join public.size s on s.size_id = p.size
   where p.recipe_id = 'rcp-mcr-mb-dk' and p.is_active and s.size_name like '%2oz%';
  if v_left > 0 then
    raise exception '% active 2oz variant(s) are still on the dark roast', v_left;
  end if;

  -- THE INVARIANT this exists to establish, stated as a rule rather than as a
  -- tenant: no recipe that is actively roasted may have zero products pointing
  -- at it, because the roast plan can then never ask for it. Reported, not
  -- raised — MB LT is a legitimate exception (the other half of a split roast)
  -- and this migration is not the place to decide the rest.
  select count(*) into v_orphan
    from public.roast_recipes rr
   where exists (select 1 from public.roast_log rl
                  where rl.recipe_id = rr.recipe_id and rl."charged?"
                    and rl.roast_date >= current_date - 90)
     and not exists (select 1 from public.products p
                      where p.recipe_id = rr.recipe_id and p.is_active);
  raise notice '% active 2oz variant(s) now on the 2oz roast; % recipe(s) are still roasted with no active product pointing at them', v_moved, v_orphan;
end $verify$;

commit;
