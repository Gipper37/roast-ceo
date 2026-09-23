-- Shipping weight must not leak into coffee weight.
--
-- 20260923000019 propagated a consumable's shipping weight onto its resale
-- variants' products.weight_lbs, on the reasoning that this is the column the
-- storefront already prices shipping from. That was wrong, and the owner
-- caught it before the trigger ever fired: "we wouldn't want it to pollute any
-- weight data associated with other data (crossing lines with coffee weights)
-- in the site though."
--
-- He is right. products.weight_lbs is not a shipping weight -- it is how much
-- COFFEE a product contains, and handle_order_detail_logic turns it into
-- roasted weight on every line:
--
--   NEW.roasted_weight := COALESCE(NEW.quantity, 0) * COALESCE(v_product_weight, 0);
--
-- which update_order_aggregates sums into orders.total_weight, and which
-- sixteen functions read as coffee -- roast_detail_by_blend, snapshot_roast_week,
-- value_roast_lot_consumption, create_bin_card among them. Give a bottle of
-- syrup a weight and it starts reporting roasted pounds: the orders list adds
-- them to the lbs beside every order, and roast reporting counts syrup as
-- coffee.
--
-- Nothing was polluted. All 105 consumables carry no weight, so the trigger
-- had nothing to propagate in the window between the two migrations.
--
-- The column stays -- shipping_weight_lbs on the consumable is the right place
-- for it and the UI writes it. Only the propagation goes. The storefront now
-- reads that column directly for a resold product instead of going through
-- products.weight_lbs, which keeps the two weights in separate boxes where
-- they belong.

begin;

drop trigger if exists trg_propagate_consumable_weight on public.consumable_inventory;
drop function if exists public.propagate_consumable_weight_to_products();

do $$
declare
  v_polluted int;
begin
  if exists (
    select 1 from pg_trigger
    where tgrelid='public.consumable_inventory'::regclass
      and tgname='trg_propagate_consumable_weight'
  ) then
    raise exception 'the weight propagation trigger is still attached';
  end if;

  -- And prove nothing got through while it existed. A resold variant with a
  -- weight would be reporting roasted pounds for a bottle.
  select count(*) into v_polluted
  from public.products
  where source_consumable_id is not null and coalesce(weight_lbs, 0) > 0;
  if v_polluted > 0 then
    raise warning '% resold variants carry a weight_lbs and are reporting roasted weight; clear them', v_polluted;
  else
    raise notice 'no resold variant carries a coffee weight';
  end if;
end $$;

commit;
