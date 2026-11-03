-- A buyer chooses how the order reaches them.
--
-- The storefront checkout has never asked. It renders the address step
-- unconditionally -- CheckoutModal's own comment reads "Phase: addresses
-- (always first)" -- collects a shipping address from everybody, and adds a
-- shipping charge whenever shop_config.shipping_enabled is on, whatever the
-- buyer actually wanted. A customer collecting at the roastery types a
-- delivery address they do not need and may be charged freight on it.
--
-- 🔴 THIS IS NOT THE DELIVERY-ZONE MODEL, AND MUST NOT BE READ AS IT.
--
-- STRATA already carries a fulfilment concept: customers.sales_area names a
-- zone, sales_area.fulfillment_method is 'delivery' or 'shipping', and the
-- roaster sets it at /app/delivery. That is ROUTING -- which van, which day,
-- whose territory -- and it belongs to the roaster. On Maui Coffee Roasters
-- all seven zones are 'delivery' today, including the two named "Ship" (86
-- customers) and "Pick-Up" (17): the roaster expresses the method in the zone
-- NAME and has never touched the column.
--
-- What this migration adds is a different fact: what the BUYER asked for at
-- checkout, on one order. Owner, 2026-11-02: "buyer picks. this does not
-- cross over to delivery zones. at least not right now. this is just a buyer
-- checking out and choosing what they want."
--
-- So `sales_area.fulfillment_method` is deliberately LEFT ALONE -- its
-- two-value check constraint stays, no 'pickup' is added to it, and nothing
-- here reads or writes customers.sales_area. The delivery board keeps routing
-- off zones exactly as it does today. Wiring the two together is a later
-- decision and a later migration; making them one column now would mean a
-- buyer's checkout click silently re-routing a wholesale account's van.
--
-- ── WHAT IS ADDED ──────────────────────────────────────────────────────────
--
-- orders.fulfillment_method   what the buyer chose on this order.
--                             NULL on every row that exists today (4,324 on
--                             production), which is honest: nobody was asked.
--                             Readers must treat NULL as "not recorded", never
--                             as a default -- an order keyed in by the roaster
--                             has no buyer choice to record and keeps NULL.
--
-- shop_config.delivery_enabled  may this storefront offer local delivery?
-- shop_config.pickup_enabled    may it offer collection at the roastery?
--                             Both default FALSE, matching shipping_enabled,
--                             retail_enabled, vip_enabled and payments_enabled
--                             -- a storefront does not start offering a
--                             fulfilment method the roaster has not turned on,
--                             and offering local delivery to a buyer two
--                             islands away is worse than not offering it.
--
-- With fewer than two methods enabled the checkout shows no chooser at all and
-- behaves exactly as it does today; with one enabled it records that one.
-- Nothing about this migration changes a single existing row's behaviour.

begin;

alter table orders
  add column if not exists fulfillment_method text;

comment on column orders.fulfillment_method is
  'How the BUYER asked for this order at shop checkout: shipping | delivery | '
  'pickup. NULL means nobody was asked -- every order before 2026-11-02, and '
  'every order the roaster keys in. This is NOT sales_area.fulfillment_method, '
  'which is the roaster''s routing for a zone and is unaffected by it.';

-- Same shape as orders_payment_status_chk and orders_invoice_state_check: NULL
-- is allowed and means "not recorded", and the value set is closed so a typo
-- in a server action fails at the write rather than reaching a reader that has
-- never heard of it.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'orders'::regclass and conname = 'orders_fulfillment_method_check'
  ) then
    alter table orders
      add constraint orders_fulfillment_method_check
      check (
        fulfillment_method is null
        or fulfillment_method = any (array['shipping'::text, 'delivery'::text, 'pickup'::text])
      );
  end if;
end $$;

alter table shop_config
  add column if not exists delivery_enabled boolean not null default false,
  add column if not exists pickup_enabled   boolean not null default false;

comment on column shop_config.delivery_enabled is
  'Offer local delivery as a fulfilment choice at shop checkout. Independent '
  'of the delivery ZONES at /app/delivery, which route the roaster''s own van.';
comment on column shop_config.pickup_enabled is
  'Offer collection at the roastery as a fulfilment choice at shop checkout. '
  'A pickup order is asked for no shipping address and is never charged freight.';

-- Verify. Each of these can pass or raise on the same database, which is the
-- point: a block that can only ever raise takes the whole release down, and
-- one that can only ever pass proves nothing.
do $$
declare
  v_bad_value   int;
  v_cols        int;
  v_zone_check  text;
begin
  -- 1. The new column accepts the three values and refuses a fourth.
  select count(*) into v_bad_value
  from orders where fulfillment_method is not null
    and fulfillment_method not in ('shipping', 'delivery', 'pickup');
  if v_bad_value > 0 then
    raise exception 'orders.fulfillment_method holds % rows outside the allowed set', v_bad_value;
  end if;

  -- 2. Both storefront toggles landed, NOT NULL and defaulted false.
  select count(*) into v_cols
  from information_schema.columns
  where table_name = 'shop_config'
    and column_name in ('delivery_enabled', 'pickup_enabled')
    and is_nullable = 'NO' and column_default = 'false';
  if v_cols <> 2 then
    raise exception 'expected 2 NOT NULL default-false storefront toggles, found %', v_cols;
  end if;

  -- 3. 🔴 THE ZONE MODEL IS UNTOUCHED. If a later change ever widens this
  --    constraint, it should be a decision somebody made on purpose, not a
  --    side effect of this file.
  select pg_get_constraintdef(oid) into v_zone_check
  from pg_constraint where conname = 'sales_area_fulfillment_method_check';
  if v_zone_check is null or v_zone_check like '%pickup%' then
    raise exception 'sales_area.fulfillment_method was changed by this migration; it must not be';
  end if;
end $$;

commit;
