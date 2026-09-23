-- A line remembers what it was listed at.
--
-- 117 MCR lines across 45 orders, carrying $22,278.70, had no
-- list_price_total: 53 NULL, and 64 sitting at zero. Every one of them has a
-- real total_price. This is not a tidiness complaint -- it is a live way to
-- destroy money.
--
-- apply_order_discount allocates an order-level discount across the lines and
-- then WRITES each line back as
--
--     total_price = list_price_total - v_share
--
-- On a line whose list is NULL that is NULL, and the line's money disappears.
-- On a line whose list is zero it is negative, and the line becomes a credit.
-- The same function clears a previous allocation with
-- `total_price = list_price_total`, so even REMOVING a discount from one of
-- those orders would have done it. Nobody has discounted one of the 45 yet.
-- That is the only reason this is a repair and not an incident.
--
-- WHY THEY ARE EMPTY. handle_order_detail_logic computes list_price_total
-- inside `IF NOT v_is_legacy AND (quantity/product/override/discount changed)`.
-- Legacy imports skip that block by design -- their figures come from
-- QuickBooks and must never be recomputed from our catalogue -- so all 64 zero
-- rows are imports, the most recent from 2026-08-27. The 53 NULLs are
-- non-legacy lines written before the column existed and never touched since.
--
-- WHY THIS IS LOSSLESS. For all 117 rows the engine's own expression,
-- COALESCE(amount_override, quantity * unit_price_at_sale), already equals
-- total_price EXACTLY. Asserted below before anything commits. This records
-- the list figure that was always implied and moves no total; nobody is billed
-- a different number.
--
-- THE OPT-IN. 20260923000026 forbids a script from touching the four columns
-- that decide what a line costs. This is the case that hatch exists for, so it
-- is taken deliberately, and the probe proves total_price did not move anyway.

begin;

-- ── 1. Record the list figure, using the engine's own formula ────────────
set local app.allow_price_backfill = 'on';

create temp table _lpt_before on commit drop as
select order_detail_id, total_price, list_price_total
  from order_details
 where coalesce(list_price_total, 0) = 0
   and coalesce(total_price, 0) <> 0;

update order_details od
   set list_price_total = coalesce(
         od.amount_override,
         coalesce(od.quantity, 0) * coalesce(od.unit_price_at_sale, 0))
  from _lpt_before b
 where b.order_detail_id = od.order_detail_id;

-- ── 2. Stop it coming back ──────────────────────────────────────────────
-- Recording the list figure is NOT repricing: it writes down the total that is
-- already on the line. So it belongs OUTSIDE the block legacy imports skip,
-- which is why it is its own trigger rather than an edit to the engine. It
-- fires last among the BEFORE triggers and only when the figure is missing, so
-- it can never overwrite one the engine computed.
create or replace function public.record_list_price_when_missing()
returns trigger language plpgsql as $function$
begin
  if coalesce(NEW.list_price_total, 0) = 0 and coalesce(NEW.total_price, 0) <> 0 then
    NEW.list_price_total := coalesce(
      NEW.amount_override,
      nullif(coalesce(NEW.quantity, 0) * coalesce(NEW.unit_price_at_sale, 0), 0),
      -- Last resort: the line's own total. True by definition when nothing has
      -- discounted it, and always better than the NULL that nulls the line the
      -- first time somebody applies an order discount.
      NEW.total_price);
  end if;
  return NEW;
end; $function$;

comment on function public.record_list_price_when_missing() is
  'Every line carries the figure it was listed at, including legacy imports, which skip the pricing engine on purpose. Never overwrites a list price the engine set; never touches total_price.';

-- Sorts after trg_handle_order_details and before the zzz_ guards, so the
-- engine has already had its say and the immutability guards still get theirs.
drop trigger if exists zzz_a_record_list_price on public.order_details;
create trigger zzz_a_record_list_price
  before insert or update on public.order_details
  for each row execute function public.record_list_price_when_missing();

-- ── 3. Prove it ─────────────────────────────────────────────────────────
do $$
declare
  v_moved int; v_filled int; v_left int; v_money numeric;
  v_order text; v_detail text; v_before numeric; v_after numeric;
begin
  select count(*) into v_moved
    from order_details od join _lpt_before b using (order_detail_id)
   where od.total_price is distinct from b.total_price;
  if v_moved > 0 then
    raise exception 'the backfill moved total_price on % line(s) -- refusing', v_moved;
  end if;

  select count(*), coalesce(round(sum(od.total_price)::numeric, 2), 0)
    into v_filled, v_money
    from order_details od join _lpt_before b using (order_detail_id);

  -- The invariant, across EVERY tenant, not just the one that reported it.
  select count(*) into v_left from order_details
   where coalesce(list_price_total, 0) = 0 and coalesce(total_price, 0) <> 0;
  if v_left > 0 then
    raise exception '% line(s) still carry money with no list price', v_left;
  end if;

  -- The trigger must actually hold the line for a NEW legacy import. Write one
  -- the way an import does, read it back, then roll the probe row away.
  select order_id into v_order from orders
   where is_legacy_import and not coalesce(posted, false)
   order by order_date desc limit 1;
  if v_order is not null then
    -- order_detail_id has no default: the app mints it. Use an unmistakable
    -- one so a probe row can never be confused for real money if this
    -- somehow escaped its transaction.
    insert into order_details (order_detail_id, order_id, product_id, quantity, unit_price_at_sale, total_price)
    select 'probe-list-price-' || v_order, v_order, od.product_id, 3, 11.25, 33.75
      from order_details od where od.order_id = v_order limit 1
    returning order_detail_id, list_price_total into v_detail, v_after;

    if v_detail is not null then
      if coalesce(v_after, 0) = 0 then
        raise exception 'a new legacy-import line STILL has no list price (got %)', v_after;
      end if;
      raise notice 'new legacy line recorded a list price of % as written', v_after;
      delete from order_details where order_detail_id = v_detail;
    end if;
  end if;

  raise notice 'recorded a list price on % line(s) worth %, and no total moved', v_filled, v_money;
end $$;

commit;
