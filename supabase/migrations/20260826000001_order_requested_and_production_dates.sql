-- Two dates an order has always had in the operator's head and nowhere on the row.
--
-- WHY NOT delivery_date. orders.delivery_date already exists, and it is the day
-- the order IS GOING OUT — stamped at create or at mark-delivered, and read by
-- the Delivery page and the "out today" badge. That is OUR plan and then our
-- record of what happened. It cannot also carry the customer's constraint,
-- because the two legitimately differ: a café asks for it by Friday and we run
-- it Wednesday. Overloading one column would mean either losing the promise or
-- lying about the schedule.
--
--   requested_delivery_date  what the CUSTOMER asked for — deliver by this day.
--                            A commitment. Drives "are we late", and belongs on
--                            the invoice because it is part of the agreement.
--
--   production_date          the day WE plan to roast it. Internal. Upstream of
--                            delivery_date, and the field a roast plan should
--                            eventually schedule from — today nothing does, and
--                            roast_date on the log only records what already
--                            happened.
--
-- Both nullable, both unset on every existing row. Nothing computes from them
-- yet: this migration only gives the two facts somewhere true to live. Reading
-- them into the roast queue or a late-order signal is a separate, deliberate
-- step — a date that silently starts driving production is worse than no date.
--
-- No backfill. Guessing a requested date for 3,806 historical orders would
-- invent a customer promise that was never made.

begin;

alter table public.orders
  add column if not exists requested_delivery_date date,
  add column if not exists production_date date;

comment on column public.orders.requested_delivery_date is
  'Deliver-by date the CUSTOMER asked for. Distinct from delivery_date, which is when we scheduled or actually delivered it.';
comment on column public.orders.production_date is
  'Day we plan to put this order into production (roast it). Internal; upstream of delivery_date.';

-- The open-orders board and any "late" view filter on these, and both are
-- company-scoped reads. Partial: the columns are null on every historical row
-- and will stay null on most, so indexing the nulls would be dead weight.
create index if not exists orders_requested_delivery_date_idx
  on public.orders (company_id, requested_delivery_date)
  where requested_delivery_date is not null;

create index if not exists orders_production_date_idx
  on public.orders (company_id, production_date)
  where production_date is not null;

commit;

notify pgrst, 'reload schema';
