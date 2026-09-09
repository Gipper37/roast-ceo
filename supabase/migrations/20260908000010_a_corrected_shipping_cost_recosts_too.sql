-- Correcting units or shipping on a consumable delivery now re-costs the same
-- orders that correcting the unit price already did.
--
-- Owner, 2026-09-08, after being shown that a cost edit backfills COGS and a
-- units edit does not: *"yes"* — make all three behave the same.
--
-- ── WHY ONE TRIGGER COVERS BOTH ─────────────────────────────────────────────
-- Consumable COGS is LANDED cost. get_consumable_cost_on_date returns
--     cp.cost_unit + coalesce(sr.shipping_cost_unit, 0)
-- so there are exactly two inputs, and the second one absorbs both of the
-- edits that were being missed:
--
--   change the units   -> calculate_shipment_totals_for() re-derives
--                         shipment_total_weight_units AND shipping_cost_unit
--                         (shipping / total units)
--   change the shipping -> calculate_shipping_per_unit() re-derives the same
--                         shipping_cost_unit
--
-- Both land on shipment_received.shipping_cost_unit, so watching that ONE
-- column catches both. Adding `amount` to the cost trigger would have been the
-- obvious move and the wrong one: amount does not appear in the COGS formula,
-- and a units change with no shipping cost on the delivery genuinely does not
-- move COGS at all.
--
-- ── WHAT WAS THERE ──────────────────────────────────────────────────────────
-- trg_propagate_shipping_cost already fires on shipping_cost_unit — and only
-- loops coffee_inventory_purchased, calling recalculate_inventory_cost per
-- origin. Consumables were simply never in it, so the landed cost moved for
-- every FUTURE lookup while order_details.unit_cost_at_sale stayed on the old
-- number for the orders that had already consumed it.
--
-- ── THE GUARDS ARE NOT NEGOTIABLE ───────────────────────────────────────────
-- This reuses propagate_consumable_purchase_to_orders' logic verbatim rather
-- than reimplementing it, so the four things that keep a re-cost safe stay
-- true: it only touches orders inside the window this price was in effect
-- (this receipt until the next receipt of the same consumable at the same
-- facility), it never crosses companies.books_closed_through, it never
-- re-costs is_legacy_import orders (the QuickBooks history), and it skips
-- canceled orders.

begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. The re-cost, lifted out of the trigger so two callers can share it.
create or replace function public.recost_orders_for_consumable_purchase(
  p_consumable_purchase_id text
)
returns int
language plpgsql
as $$
declare
  v_row        record;
  v_this_date  date;
  v_next_date  date;
  v_new_cost   numeric;
  v_rec        record;
  v_touched    int := 0;
begin
  select cp.consumable_purchase_id, cp.consumable_inventory_item, cp.facility_id,
         cp.cost_unit, cp.shipment_id
    into v_row
    from public.consumable_inventory_purchased cp
   where cp.consumable_purchase_id = p_consumable_purchase_id;
  if v_row.consumable_purchase_id is null then return 0; end if;

  -- A line with no price of its own contributes nothing to look up.
  if coalesce(v_row.cost_unit, 0) = 0 then return 0; end if;

  select sr.date_received into v_this_date
    from public.shipment_received sr
   where sr.shipment_id = v_row.shipment_id
     and coalesce(sr.voided, false) = false
   limit 1;
  -- Never received means it was never the price of record for anything.
  if v_this_date is null then return 0; end if;

  select sr.date_received into v_next_date
    from public.consumable_inventory_purchased cp
    join public.shipment_received sr on sr.shipment_id = cp.shipment_id
   where cp.consumable_inventory_item = v_row.consumable_inventory_item
     and cp.facility_id               = v_row.facility_id
     and sr.date_received            is not null
     and sr.date_received             > v_this_date
     and cp.consumable_purchase_id   <> v_row.consumable_purchase_id
     and coalesce(sr.voided, false) = false
   order by sr.date_received asc
   limit 1;

  for v_rec in
    select distinct od.order_detail_id, od.product_id, od.facility_id,
                    od.order_date, od.quantity
      from public.order_details od
      join public.orders o on o.order_id = od.order_id
      join public.product_consumables pc
           on pc.product_id = od.product_id and pc.facility_id = od.facility_id
      join public.companies cmp on cmp.company_id = od.company_id
     where o.order_status  <> 'Canceled'
       and od.order_date   >= v_this_date
       and (v_next_date is null or od.order_date < v_next_date)
       and od.order_date    > coalesce(cmp.books_closed_through, '-infinity'::date)
       and coalesce(o.is_legacy_import, false) = false
       and pc.consumable_id = v_row.consumable_inventory_item
       and coalesce(od.quantity, 0) > 0
  loop
    v_new_cost := public.get_product_cogs_on_date(v_rec.product_id, v_rec.facility_id, v_rec.order_date);
    if v_new_cost is not null and v_new_cost > 0 then
      update public.order_details
         set unit_cost_at_sale = v_new_cost * v_rec.quantity, updated_at = now()
       where order_detail_id = v_rec.order_detail_id
         and unit_cost_at_sale is distinct from (v_new_cost * v_rec.quantity);
      if found then v_touched := v_touched + 1; end if;
    end if;
  end loop;

  return v_touched;
end;
$$;

comment on function public.recost_orders_for_consumable_purchase(text) is
  'Re-cost order_details that consumed this consumable while this purchase was the price of record. Bounded by the next receipt of the same consumable at the same facility; never crosses books_closed_through, never touches legacy imports or canceled orders.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. The existing per-line trigger now delegates, so there is one implementation.
create or replace function public.propagate_consumable_purchase_to_orders()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'UPDATE' and old.cost_unit is not distinct from new.cost_unit then
    return null;
  end if;
  perform public.recost_orders_for_consumable_purchase(new.consumable_purchase_id);
  return null;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. NEW: shipping-per-unit moved, so the landed cost moved.
--
-- Fires for a shipping-cost edit AND for a units correction, because both are
-- written to this column by calculate_shipping_per_unit /
-- calculate_shipment_totals_for respectively.
create or replace function public.propagate_shipping_to_consumable_orders()
returns trigger
language plpgsql
as $$
declare
  r record;
begin
  if old.shipping_cost_unit is not distinct from new.shipping_cost_unit then
    return null;
  end if;
  for r in
    select consumable_purchase_id
      from public.consumable_inventory_purchased
     where shipment_id = new.shipment_id
       and facility_id is not distinct from new.facility_id
  loop
    perform public.recost_orders_for_consumable_purchase(r.consumable_purchase_id);
  end loop;
  return null;
end;
$$;

drop trigger if exists trg_propagate_shipping_to_consumable_orders on public.shipment_received;
create trigger trg_propagate_shipping_to_consumable_orders
  after update of shipping_cost_unit on public.shipment_received
  for each row execute function public.propagate_shipping_to_consumable_orders();

comment on function public.propagate_shipping_to_consumable_orders() is
  'A shipping-cost or units correction changes shipping_cost_unit, which is half of a consumable''s landed cost. Re-costs the affected orders the same way a unit-price change already did. trg_propagate_shipping_cost covers the coffee side and only the coffee side.';

commit;
