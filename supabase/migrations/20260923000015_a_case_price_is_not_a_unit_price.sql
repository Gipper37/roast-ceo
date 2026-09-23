-- An import wrote case prices into a per-unit column.
--
-- consumable_inventory_purchased.cost_unit is what ONE unit cost. Two imported
-- shipments (2025-12-16 and 2026-03-04, both created_by = the company id,
-- which is the signature of a script rather than a person) carried
-- QuickBooks' CASE cost into it.
--
-- get_consumable_cost_on_date returns that figure as the unit cost, so every
-- resold-consumable sale priced from those receipts booked a COGS around ten
-- times what was actually paid. Monin Vanilla, which sells for $11.75, was
-- costed at $73.56 a bottle -- 2026-09-01, qty 10, booked at $735.60. The
-- margin report has been stating a loss on things sold at a profit.
--
-- The owner supplied the case sizes: "case is 12 for monin syrups. 4 for monin
-- sauces." Every affected row is Monin except one, and both families fall out
-- of the data cleanly:
--
--   $73.56 / 12 = $6.13   25 syrup lines
--   $71.51 / 12 = $5.96    3 sugar-free syrup lines
--   $32.09 /  4 = $8.02    5 sauce lines
--   $28.32 /  4 = $7.08    1 concentrate line
--
-- CAFIZA IS AN INFERENCE, and is marked as one. The owner did not know its
-- case size and asked me to look it up. Urnex ships the 566g/20oz jar in cases
-- of 6 or 12. $77.60 divides to $12.93 or $6.47 a jar; a 20oz Cafiza retails
-- around $20-25, so $6.47 is not a wholesale price for one and $12.93 plainly
-- is. Taken as a case of 6.
--
-- It is the one row here not resting on something the owner stated outright,
-- so it is corrected in its own statement and named in the notice. If the
-- invoice says 12, the fix is one line.
--
-- QUANTITIES ARE CORRECTED TOO, on the owner's instruction, and the two moves
-- belong together: the import read one QuickBooks line as "35 at $73.56", so
-- the 35 were CASES and the price was a case price. Both halves are in the
-- same unit basis and both are wrong the same way.
--
-- The proof that this is right is that THE MONEY DOES NOT MOVE:
--
--   35 cases x $73.56  =  420 bottles x $6.13  =  $2,574.60
--
-- Total spend is identical before and after; only the unit basis changes. The
-- probe asserts exactly that, per line, and refuses the migration if a single
-- line's value shifts by a cent.
--
-- AND NO STOCK MOVES EITHER, which was checked before writing this rather than
-- hoped for. update_consumable_metrics only counts receipts dated on or after
-- an item's last physical count. 35 of the 36 lines were counted AFTER the
-- receipt, so those receipts already contribute nothing to on-hand. The 36th
-- (Cafiza) has no date_received at all, and a receipt with no date never
-- counts. Every one of these items is anchored by a count that supersedes it.
--
-- Updating cost_unit fires trg_propagate_consumable_purchase_cost_to_orders,
-- which recosts the affected order lines. That path already refuses to touch
-- anything at or before books_closed_through (MCR: 2026-04-30), canceled
-- orders, or legacy imports.

begin;

set local lock_timeout = '2s';

-- Snapshot every affected line's total value BEFORE the corrections, so the
-- probe below can prove not one cent moved.
create temporary table _spend_before on commit drop as
select cip.consumable_purchase_id,
       round(cip.amount * cip.cost_unit, 2) as value_before
from public.consumable_inventory_purchased cip
join public.consumable_inventory ci on ci.consumable_inventory_id = cip.consumable_inventory_item
where ci.company_id = '9ShiyDAXhV'
  and (cip.cost_unit in (73.56, 71.51, 32.09, 28.32)
       or (ci.consumable_inventory_item ilike 'Cafiza%' and cip.cost_unit = 77.60));


do $$
declare
  v_syrup int; v_sauce int; v_cafiza int; v_total int;
begin
  -- Syrups and sugar-free syrups: a case of 12.
  update public.consumable_inventory_purchased cip
     set cost_unit = round(cip.cost_unit / 12.0, 4),
         amount    = cip.amount * 12
    from public.consumable_inventory ci
   where ci.consumable_inventory_id = cip.consumable_inventory_item
     and ci.company_id = '9ShiyDAXhV'
     and cip.cost_unit in (73.56, 71.51);
  get diagnostics v_syrup = row_count;

  -- Sauces and the basil concentrate: a case of 4.
  update public.consumable_inventory_purchased cip
     set cost_unit = round(cip.cost_unit / 4.0, 4),
         amount    = cip.amount * 4
    from public.consumable_inventory ci
   where ci.consumable_inventory_id = cip.consumable_inventory_item
     and ci.company_id = '9ShiyDAXhV'
     and cip.cost_unit in (32.09, 28.32);
  get diagnostics v_sauce = row_count;

  -- Cafiza: a case of 6, inferred -- see the header.
  update public.consumable_inventory_purchased cip
     set cost_unit = round(cip.cost_unit / 6.0, 4),
         amount    = cip.amount * 6
    from public.consumable_inventory ci
   where ci.consumable_inventory_id = cip.consumable_inventory_item
     and ci.company_id = '9ShiyDAXhV'
     and ci.consumable_inventory_item ilike 'Cafiza%'
     and cip.cost_unit = 77.60;
  get diagnostics v_cafiza = row_count;

  v_total := v_syrup + v_sauce + v_cafiza;
  raise notice 'corrected % receipt lines: % syrup /12, % sauce /4, % Cafiza /6 (INFERRED)',
    v_total, v_syrup, v_sauce, v_cafiza;

  if v_total = 0 then
    raise notice 'nothing to correct on this database';
  end if;
end $$;

do $$
declare
  v_left int;
  v_worst numeric;
  v_moved int;
begin
  -- Nothing Monin may still look like a case price. Cafiza is expected to
  -- remain and is named so this probe does not quietly pass on a second
  -- unrelated problem.
  -- THE central check: a change of unit basis must not change the money.
  select count(*) into v_moved
  from _spend_before b
  join public.consumable_inventory_purchased cip
    on cip.consumable_purchase_id = b.consumable_purchase_id
  where abs(round(cip.amount * cip.cost_unit, 2) - b.value_before) > 0.01;
  if v_moved > 0 then
    raise exception '% receipt lines changed VALUE, not just unit basis', v_moved;
  end if;

  select count(*) into v_left
  from public.consumable_inventory_purchased cip
  join public.consumable_inventory ci on ci.consumable_inventory_id = cip.consumable_inventory_item
  where ci.company_id = '9ShiyDAXhV'
    and ci.fallback_unit_cost > 0
    and cip.cost_unit > ci.fallback_unit_cost * 3;
  if v_left > 0 then
    raise exception '% receipt lines still carry what looks like a case price', v_left;
  end if;

  -- And the cost a bottle is now carried at must be sane against its sale
  -- price. Monin Vanilla sells at 11.75; a unit cost above that would mean the
  -- division went the wrong way.
  select max(cip.cost_unit) into v_worst
  from public.consumable_inventory_purchased cip
  where cip.consumable_inventory_item = 'cons_0a22ec5e1241b32e';
  if v_worst is not null and v_worst > 11.75 then
    raise exception 'Monin Vanilla still costs %/bottle against an 11.75 sale price', v_worst;
  end if;
end $$;

commit;
