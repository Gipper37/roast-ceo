-- A shipping rate needs a floor, not just a ceiling.
--
-- Owner, live on prod: "where is the minimum shipping on the shop settings".
-- There is none. shop_config carries shipping_enabled, shipping_rate_per_lb,
-- shipping_rate_unit, free_shipping_threshold and shipping_product_id -- a
-- rate and a free-above CEILING, and no floor at all. MCR charges $1.50/lb,
-- so his own 0.13 lb test order was billed 19 cents of shipping. No carrier
-- moves a box for 19 cents; the roaster eats the difference on every small
-- order, which is exactly what a minimum exists to stop.
--
-- Dollars, like its two neighbours, so the settings screen and the checkout
-- keep comparing like with like (free_shipping_threshold is dollars too, and
-- the checkout already divides the cart by 100 to meet it).
--
-- NULL means no floor, which is today's behaviour for every tenant. The
-- column is nullable with no default on purpose: a default of 0 would be a
-- floor of zero, indistinguishable from "not set" in the UI, and would make
-- every existing roaster look as though someone had configured something.

alter table public.shop_config
  add column if not exists shipping_min_charge numeric;

comment on column public.shop_config.shipping_min_charge is
  'Lowest shipping charge, in dollars, applied when freight is charged at all. NULL = no floor. Ignored when the order ships free (free_shipping_threshold) or is a delivery/pickup, since those charge no freight to raise.';

-- A floor below zero is not a floor, and a roaster typing a negative into the
-- box would turn shipping into a discount.
alter table public.shop_config
  drop constraint if exists shop_config_shipping_min_charge_nonneg;
alter table public.shop_config
  add constraint shop_config_shipping_min_charge_nonneg
  check (shipping_min_charge is null or shipping_min_charge >= 0);

do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'shop_config'
      and column_name = 'shipping_min_charge'
  ) then
    raise exception 'shop_config.shipping_min_charge was not created';
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.shop_config'::regclass
      and conname = 'shop_config_shipping_min_charge_nonneg'
  ) then
    raise exception 'the non-negative check on shipping_min_charge is missing';
  end if;
end $$;
