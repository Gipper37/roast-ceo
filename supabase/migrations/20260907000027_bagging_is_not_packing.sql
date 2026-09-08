-- Bagging is not packing, and most bagging goes to stock.
--
-- Owner, 2026-09-07: *"right now that pack tab is for packing the box for the
-- order. we prob need to add a different flow for this and differentiate the
-- two. also need to account for pack for backstock. most roasters pack but
-- don't always know where its going in the moment. whats the solve for that"*
--
-- He is right, and the first cut of the screen had it wrong: it asked a packer
-- who the coffee was for at the moment they bagged it, which is the one thing
-- they usually do not know. Two different acts:
--
--   BAGGING     production. Roasted coffee into retail bags. Mints the lot
--               code. Goes to STOCK — no customer, no order, no question.
--   PACKING     fulfilment. Putting an order in a box. Already exists.
--
-- So backstock is not an edge case to handle, it is the DEFAULT: a pack run
-- with no allocations IS backstock, and `pack_run_remaining` says how much of
-- each lot is still on the shelf.
--
-- ── The link, and why it is automatic ───────────────────────────────────────
-- Traceability needs the step from a lot to a customer, and asking a packer to
-- pick a lot code while they are filling a box is how that data ends up wrong or
-- absent. So when an order line is marked Packed, `allocate_line_from_stock()`
-- draws the bags from the OLDEST lot of that product that still has stock,
-- splitting across lots when the first runs out. Nobody types a lot code.
--
-- 🔴 It NEVER fails the pack. If nothing has been bagged, or stock is short, it
-- allocates what it can and returns what it could not — because blocking a
-- roastery from shipping an order over a food-safety record would be a worse
-- failure than an incomplete trace, and the recall report already reports
-- unaccounted bags honestly rather than hiding them.

begin;

-- ── What is still on the shelf, per lot ─────────────────────────────────────
create or replace view public.pack_run_remaining as
select pr.pack_run_id,
       pr.company_id,
       pr.lot_code,
       pr.product_id,
       pr.product_name_snapshot,
       pr.coffee_prep,
       pr.packed_on,
       pr.best_before,
       pr.location,
       pr.bags                                              as bags_packed,
       coalesce(a.allocated, 0)                             as bags_allocated,
       pr.bags - coalesce(a.allocated, 0)                   as bags_remaining
  from public.pack_run pr
  left join lateral (
    select sum(al.bags) as allocated
      from public.pack_run_allocation al
     where al.pack_run_id = pr.pack_run_id
  ) a on true
 where pr.voided_at is null;

comment on view public.pack_run_remaining is
  'Bags packed minus bags given out, per lot. A lot with everything remaining is backstock — which is the normal state of a bagging run, not an exception.';

grant select on public.pack_run_remaining to authenticated;

-- ── Draw an order line from stock, oldest lot first ─────────────────────────
create or replace function public.allocate_line_from_stock(p_order_detail_id text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_line     record;
  v_need     numeric;
  v_take     numeric;
  v_lot      record;
  v_used     jsonb := '[]'::jsonb;
begin
  select od.order_detail_id, od.product_id, od.quantity, od.company_id,
         coalesce(od.customer_id, o.customer_id) as customer_id
    into v_line
    from public.order_details od
    left join public.orders o on o.order_id = od.order_id
   where od.order_detail_id = p_order_detail_id
     and od.company_id in (select auth_company_ids());
  if v_line.order_detail_id is null then
    return jsonb_build_object('allocated', 0, 'short', 0, 'reason', 'no such line');
  end if;

  -- Already drawn (a re-pack, a double click): leave it alone rather than
  -- double-counting the same bags out of stock.
  if exists (select 1 from public.pack_run_allocation where order_detail_id = p_order_detail_id) then
    return jsonb_build_object('allocated', 0, 'short', 0, 'reason', 'already allocated');
  end if;

  v_need := coalesce(v_line.quantity, 0);
  if v_need <= 0 then
    return jsonb_build_object('allocated', 0, 'short', 0, 'reason', 'nothing to allocate');
  end if;

  -- Oldest first. FOR UPDATE on the pack_run rows so two packers working the
  -- same product cannot both draw the last bags of a lot.
  for v_lot in
    select r.pack_run_id, r.bags_remaining
      from public.pack_run_remaining r
      join public.pack_run pr on pr.pack_run_id = r.pack_run_id
     where r.company_id = v_line.company_id
       and r.product_id = v_line.product_id
       and r.bags_remaining > 0
     order by r.packed_on asc, r.lot_code asc
     for update of pr
  loop
    exit when v_need <= 0;
    v_take := least(v_lot.bags_remaining, v_need);
    insert into public.pack_run_allocation (pack_run_id, order_detail_id, customer_id, bags)
    values (v_lot.pack_run_id, p_order_detail_id, v_line.customer_id, v_take);
    v_used := v_used || jsonb_build_object('pack_run_id', v_lot.pack_run_id, 'bags', v_take);
    v_need := v_need - v_take;
  end loop;

  -- Short is REPORTED, never raised. Blocking a roastery from shipping over a
  -- traceability record would be a worse failure than an incomplete trace, and
  -- the recall report already surfaces unaccounted bags rather than hiding them.
  return jsonb_build_object(
    'allocated', coalesce(v_line.quantity, 0) - v_need,
    'short', v_need,
    'lots', v_used);
end;
$$;

comment on function public.allocate_line_from_stock is
  'Draws an order line''s bags from the oldest lot with stock, splitting across lots as needed. Never fails the pack: a shortfall is returned, not raised.';

-- ── Putting them back ───────────────────────────────────────────────────────
-- Un-packing a line has to return its bags to the shelf, or the stock figure
-- drifts down every time somebody corrects a mistake.
create or replace function public.release_line_allocation(p_order_detail_id text)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_count int;
begin
  delete from public.pack_run_allocation a
   using public.order_details od
   where a.order_detail_id = p_order_detail_id
     and od.order_detail_id = a.order_detail_id
     and od.company_id in (select auth_company_ids());
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.allocate_line_from_stock(text)  from public;
revoke all on function public.release_line_allocation(text)   from public;
grant execute on function public.allocate_line_from_stock(text) to authenticated;
grant execute on function public.release_line_allocation(text)  to authenticated;

commit;
