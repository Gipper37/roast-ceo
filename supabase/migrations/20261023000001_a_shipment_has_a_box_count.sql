-- A shipment has a box count.
--
-- Owner, 2026-10-22, from a day of shipping: *"A shipped Box count on tracking
-- number for an order."*
--
-- One tracking number covers a whole shipment, and a shipment is boxes. The
-- order already records the carrier and the tracking number -- the two
-- references that belong to somebody else -- and how many boxes went is the
-- third fact of the same kind: it is what the customer counts off the pallet
-- and what settles "we only got five".
--
-- Nullable, with no default. A null means nobody said, which is honestly
-- different from 1 and must not be printed as "1 box" on an invoice. Every
-- order placed before today is in that state and backfilling them to 1 would
-- invent a fact about shipments nobody counted.
--
-- The check is a sanity bound, not a business rule: zero boxes is not a
-- shipment, and a four-digit box count is a typo.

begin;

alter table public.orders
  add column if not exists box_count integer;

alter table public.orders
  drop constraint if exists orders_box_count_check;

alter table public.orders
  add constraint orders_box_count_check
  check (box_count is null or (box_count >= 1 and box_count <= 999));

comment on column public.orders.box_count is
  'How many boxes this order shipped in, recorded beside the carrier and tracking number. NULL means nobody counted, which is not the same as 1.';

-- 🔴 Asserts only what this file wrote, and exercises the constraint rather
-- than reading its text. The savepoint keeps a refusal from poisoning the
-- transaction; nothing is left behind either way.
do $$
declare
  v_order text;
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'orders' and column_name = 'box_count'
  ) then
    raise exception 'orders.box_count was not added';
  end if;

  select order_id into v_order from public.orders limit 1;
  if v_order is null then
    return;  -- a database with no orders is a fresh one; the column is still there
  end if;

  begin
    update public.orders set box_count = 0 where order_id = v_order;
    raise exception 'orders.box_count accepted 0, which is not a shipment';
  exception when check_violation then
    null;  -- correct
  end;
end $$;

commit;
