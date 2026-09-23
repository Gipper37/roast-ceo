-- When it was scheduled and when it actually went out are two facts.
--
-- orders.delivery_date is the SCHEDULE. The delivery day-view places stops by
-- it, DeliveryDateField calls it "Scheduled delivery" and offers an Override
-- for holiday pushes and skip-weeks, and the shape of the live data agrees:
-- of the 348 rows that carry one, 345 are AFTER order_date and none is
-- before, averaging +2.1 days. Every one belongs to Social Hour US.
--
-- Recording that a Saturday run was delivered on Saturday, while typing it up
-- on Monday, must not overwrite that. The owner, on seeing the first cut of
-- this: "it shouldn't edit that delivery date field." He is right -- a
-- back-date written into delivery_date destroys what was planned and can pull
-- the stop out of the day-view it was scheduled into.
--
-- So the day it actually went out gets its own column. Nullable, no default,
-- no backfill: NULL means nobody has recorded it, which is the truth for
-- every order in the database today. MCR has never marked an order Delivered
-- through the app at all -- all 3,799 of their Delivered orders came from the
-- QuickBooks importer, which stamps the status and no fulfilment date.
--
-- Deliberately a DATE and not a timestamptz. shipped_at is the timestamptz
-- already on this table and it is NULL on all 15,274 rows in every tenant; a
-- delivery is remembered as a day, and a time nobody recorded is a time
-- nobody should be asked to invent.
--
-- NOT a usage date. Consumable usage is attributed by orders.order_date in
-- all four blocks of update_consumable_metrics, and by order_details' own
-- copy of it for COGS -- 36 database functions read order_date and exactly
-- none reads a fulfilment date. This column records what happened; it does
-- not move stock.

begin;

alter table public.orders
  add column if not exists delivered_on date;

comment on column public.orders.delivered_on is
  'The day the order actually went out. NULL until somebody records it. Distinct from delivery_date, which is the SCHEDULE the day-view places stops by. Not read by any usage or COGS path -- those key on order_date.';

create index if not exists idx_orders_delivered_on
  on public.orders (facility_id, delivered_on)
  where delivered_on is not null;

do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='orders' and column_name='delivered_on'
  ) then
    raise exception 'delivered_on was not added';
  end if;

  -- It must not have landed in the posted-order immutability guard by
  -- accident: correcting the day a delivery happened is exactly the kind of
  -- late fix that has to stay possible after an invoice is posted.
  if position('delivered_on' in (
       select prosrc from pg_proc
       where oid = 'public.guard_posted_order_immutable()'::regprocedure)) > 0 then
    raise exception 'delivered_on must not be locked by guard_posted_order_immutable';
  end if;
end $$;

commit;
