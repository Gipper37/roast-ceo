-- Ten live order lines are one edit away from collapsing.
--
-- order_details.amount_override is a LINE TOTAL. handle_order_detail_logic is
-- explicit about it:
--
--   -- An override is a LINE total; per-unit it is override/qty.
--   NEW.list_price_total := NEW.amount_override
--   NEW.unit_price_at_sale := NEW.amount_override / NEW.quantity
--
-- Ten lines across six live MCR orders hold a UNIT price there instead. They
-- were all written in one batch at 2026-08-31 20:15:34, and the rows already
-- contradict themselves -- list_price_total is the override while total_price
-- is the override times the quantity:
--
--   detail    qty  amount_override  list_price_total  total_price
--   4d57fe2e   16            61.75             61.75       988.00
--
-- The displayed totals are RIGHT today, because total_price was written
-- correctly and nothing has re-triggered since. But the trigger fires on any
-- write that touches a line -- a quantity edit, a line discount, an order
-- discount, a price-log change -- and it would rebuild total_price FROM the
-- override:
--
--   order 3943  $1,295.75 -> $92.41
--   order 3950  $  448.50 -> $149.50
--   order 3951  $  267.50 -> $133.75
--   order 3954  $  373.75 -> $74.75
--   order 3957  $  448.50 -> $74.75
--   order 3963  $  212.25 -> $14.15
--   ---------------------------------
--   $3,046.25 -> $539.31, so $2,506.94 disappears from six live invoices
--
-- All six are Open and unposted, so they have not been billed yet -- which is
-- exactly why this is worth fixing now rather than after somebody edits one.
--
-- THE FIX is to make the override say what it means: the line total, which is
-- the figure already in total_price. Setting it there is self-consistent --
-- the trigger then recomputes list_price_total = 988.00, unit_price_at_sale =
-- 988.00/16 = 61.75, total_price = 988.00 -- so the numbers hold still under
-- the next edit instead of falling over.
--
-- The probe proves exactly that: not one line's total_price may move.

begin;

set local lock_timeout = '2s';

create temporary table _override_before on commit drop as
select od.order_detail_id,
       od.total_price as total_before,
       od.quantity,
       od.amount_override as override_before
from public.order_details od
join public.orders o on o.order_id = od.order_id
where od.amount_override is not null
  and coalesce(od.quantity, 0) > 1
  -- The override multiplied by the quantity reproduces the line total, which
  -- is the fingerprint of a per-unit figure in a line-total column.
  and abs(od.amount_override * od.quantity - od.total_price) < 0.01
  and abs(od.amount_override - od.total_price) > 0.01
  and not coalesce(o.posted, false)
  and o.order_status <> 'Canceled';

do $$
declare
  v_n int;
begin
  update public.order_details od
     set amount_override = b.total_before
    from _override_before b
   where od.order_detail_id = b.order_detail_id;
  get diagnostics v_n = row_count;
  raise notice 'rewrote % overrides from a unit price to the line total', v_n;
end $$;

do $$
declare
  v_moved int;
  v_left  int;
begin
  -- Nothing may have changed VALUE. The whole point is that these orders bill
  -- exactly what they billed before, and keep doing so after the next edit.
  select count(*) into v_moved
  from _override_before b
  join public.order_details od on od.order_detail_id = b.order_detail_id
  where abs(coalesce(od.total_price,0) - b.total_before) > 0.01;
  if v_moved > 0 then
    raise exception '% lines changed value; the override rewrite was not neutral', v_moved;
  end if;

  -- And the fingerprint must be gone, or something was missed.
  select count(*) into v_left
  from public.order_details od
  join public.orders o on o.order_id = od.order_id
  where od.amount_override is not null
    and coalesce(od.quantity,0) > 1
    and abs(od.amount_override * od.quantity - od.total_price) < 0.01
    and abs(od.amount_override - od.total_price) > 0.01
    and not coalesce(o.posted, false)
    and o.order_status <> 'Canceled';
  if v_left > 0 then
    raise exception '% lines still hold a unit price in amount_override', v_left;
  end if;
end $$;

commit;
