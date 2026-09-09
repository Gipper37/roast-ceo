-- A delivery that has not arrived does not get to set your cost.
--
-- Owner, 2026-09-08: *"no it shouldn't set cost until its received."*
--
-- He hit this as a product page reading $9.33 for a label whose true landed
-- cost is $0.117. Two separate faults stacked to produce that number.
--
-- ── FAULT 1: an unreceived delivery was pricing the item ─────────────────────
-- update_last_consumable_cost() picked the latest purchase with
--   order by sr.date_received desc nulls last, cp.created_at desc
-- and never required date_received to exist. When a consumable's ONLY purchase
-- is a delivery still in transit, `nulls last` has nothing to rank behind it and
-- the pending row wins. 14 consumables on prod are currently priced off a
-- delivery that has no received date.
--
-- The other cost path already had this right and has all along:
-- get_consumable_cost_on_date() joins `and sr.date_received is not null`, so it
-- IGNORES the same delivery and falls through to fallback_unit_cost. Two
-- functions, opposite rules, one of them wrong — which is why the product page
-- and order COGS could disagree about the same consumable on the same day.
--
-- ── FAULT 2: the cached cost was computed mid-flight ─────────────────────────
-- Triggers on consumable_inventory_purchased fire in ALPHABETICAL order:
--     trg_push_last_consumable_cost   <- computes cost_unit + shipping_cost_unit
--     update_shipment_on_consumable   <- recomputes shipping_cost_unit
-- 'p' sorts before 'u'. Correcting a delivery from 16 units to 4000 therefore
-- computed the cached cost against shipping/16 = 9.249 and only afterwards
-- moved shipping_cost_unit to shipping/4000 = 0.037. Nothing went back.
-- 0.08 + 9.249 = 9.329, which is exactly what prod stored.
--
-- Renaming the trigger to sort last would fix today's ordering and quietly
-- break the next time somebody adds a trigger. Instead the recompute is
-- extracted into a function that ANY caller can run, and the shipment-level
-- trigger added in 20260908000010 — which already fires whenever
-- shipping_cost_unit moves — calls it too. Whatever order the row triggers run
-- in, the last word is computed from settled numbers.
--
-- ── NOT CHANGED: shipment_received.status ───────────────────────────────────
-- Owner also said: *"it shouldn't be marked recieved by any other function than
-- the date filled in."* Re-verified on prod today, and that is already true of
-- everything that matters: NO function and NO view reads
-- shipment_received.status to decide arrival (record_lot_receipt only names it
-- in an INSERT column list). date_received is the sole arrival truth, in
-- shipmentStatus() and in every stock function. `status` is a PURCHASE
-- lifecycle label whose three values mean draft PO / sent PO / not-a-PO — and
-- the third one is merely NAMED 'received', which is why 157 rows carry it and
-- 10 of those have no date. Renaming that state is a real cleanup and a
-- separate decision; it is not what was costing him money, so it is not
-- smuggled in here.

begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. One implementation, callable from anywhere.
create or replace function public.refresh_last_consumable_cost(
  p_item_id     text,
  p_facility_id text
)
returns numeric
language plpgsql
as $$
declare
  v_latest_cost   numeric;
  v_fallback_cost numeric;
begin
  -- Landed cost of the most recent RECEIVED delivery. The date is the gate:
  -- coffee that has not landed cannot be what a bag costs today.
  select cp.cost_unit::numeric + coalesce(sr.shipping_cost_unit, 0)
    into v_latest_cost
    from public.consumable_inventory_purchased cp
    join public.shipment_received sr on sr.shipment_id = cp.shipment_id
   where cp.consumable_inventory_item = p_item_id
     and cp.facility_id               = p_facility_id
     and cp.cost_unit is not null
     and cp.cost_unit::text <> ''
     and cp.cost_unit::numeric > 0
     and coalesce(sr.voided, false) = false
     and sr.date_received is not null          -- 🔴 THE FIX
   order by sr.date_received desc, cp.created_at desc
   limit 1;

  if v_latest_cost is not null then
    update public.consumable_inventory
       set last_cost_unit = v_latest_cost, updated_at = now()
     where consumable_inventory_id = p_item_id and facility_id = p_facility_id;
    return v_latest_cost;
  end if;

  -- Nothing has ever been received. The roaster's own standing figure is the
  -- honest answer — and it is what get_consumable_cost_on_date already falls
  -- back to, so the two paths now agree here as well.
  select fallback_unit_cost into v_fallback_cost
    from public.consumable_inventory
   where consumable_inventory_id = p_item_id and facility_id = p_facility_id;

  if coalesce(v_fallback_cost, 0) > 0 then
    update public.consumable_inventory
       set last_cost_unit = v_fallback_cost, updated_at = now()
     where consumable_inventory_id = p_item_id and facility_id = p_facility_id;
    return v_fallback_cost;
  end if;

  return null;
end;
$$;

comment on function public.refresh_last_consumable_cost(text, text) is
  'Recompute consumable_inventory.last_cost_unit from the most recent RECEIVED delivery (unit price + per-unit shipping), falling back to fallback_unit_cost. Callable, so it can be re-run after shipping_cost_unit settles rather than depending on trigger firing order.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. The row trigger delegates.
create or replace function public.update_last_consumable_cost()
returns trigger
language plpgsql
as $$
begin
  perform public.refresh_last_consumable_cost(
    coalesce(new.consumable_inventory_item, old.consumable_inventory_item),
    coalesce(new.facility_id, old.facility_id));
  return null;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. And it runs again once the shipment's own numbers have settled.
--
-- This trigger already exists from 20260908000010 and fires on
-- shipping_cost_unit — which moves for BOTH a shipping edit and a units
-- correction. Re-running the cost refresh here is what makes the result
-- independent of trigger firing order.
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
    select consumable_purchase_id, consumable_inventory_item, facility_id
      from public.consumable_inventory_purchased
     where shipment_id = new.shipment_id
       and facility_id is not distinct from new.facility_id
  loop
    -- The cached figure first, so anything reading it afterwards is current.
    perform public.refresh_last_consumable_cost(r.consumable_inventory_item, r.facility_id);
    perform public.recost_orders_for_consumable_purchase(r.consumable_purchase_id);
  end loop;
  return null;
end;
$$;

-- A received date appearing is the moment a delivery starts counting.
drop trigger if exists trg_refresh_consumable_cost_on_receipt on public.shipment_received;
create trigger trg_refresh_consumable_cost_on_receipt
  after update of date_received on public.shipment_received
  for each row
  when (old.date_received is distinct from new.date_received)
  execute function public.propagate_shipping_to_consumable_orders();

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Backfill every consumable under the corrected rule.
do $$
declare r record; begin
  for r in select consumable_inventory_id, facility_id from public.consumable_inventory loop
    perform public.refresh_last_consumable_cost(r.consumable_inventory_id, r.facility_id);
  end loop;
end $$;

commit;
