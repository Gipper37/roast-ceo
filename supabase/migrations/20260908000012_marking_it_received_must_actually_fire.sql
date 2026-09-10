-- The receipt trigger I added an hour ago returned early every time.
--
-- 20260908000011 pointed a new trigger — "the delivery just landed, recompute
-- its cost" — at propagate_shipping_to_consumable_orders(), reusing the
-- function rather than duplicating the loop. That function opens with:
--
--     if old.shipping_cost_unit is not distinct from new.shipping_cost_unit
--     then return null; end if;
--
-- which is exactly right for the trigger it was written for and exactly wrong
-- for this one: filling in date_received does not move shipping_cost_unit, so
-- the guard fired and the function did nothing. Caught by the migration's own
-- test — marking a delivery received left the consumable on its fallback cost
-- of 0.11 instead of the true landed 0.117.
--
-- One function, one guard that names both reasons it should run.

begin;

create or replace function public.refresh_consumables_for_shipment()
returns trigger
language plpgsql
as $$
declare
  r record;
begin
  -- Two things make a shipment's consumables worth recomputing: the per-unit
  -- shipping moved (a shipping edit, or a units correction re-deriving it), or
  -- the delivery finally landed and started counting at all.
  if old.shipping_cost_unit is not distinct from new.shipping_cost_unit
     and old.date_received is not distinct from new.date_received then
    return null;
  end if;

  for r in
    select consumable_purchase_id, consumable_inventory_item, facility_id
      from public.consumable_inventory_purchased
     where shipment_id = new.shipment_id
       and facility_id is not distinct from new.facility_id
  loop
    -- Cached figure first, so anything reading it afterwards is current.
    perform public.refresh_last_consumable_cost(r.consumable_inventory_item, r.facility_id);
    perform public.recost_orders_for_consumable_purchase(r.consumable_purchase_id);
  end loop;
  return null;
end;
$$;

comment on function public.refresh_consumables_for_shipment() is
  'Recompute a shipment''s consumable costs and re-cost the orders that consumed them. Runs when shipping_cost_unit moves (shipping edit or units correction) or when date_received appears (the delivery landed).';

-- Both reasons, one trigger.
drop trigger if exists trg_propagate_shipping_to_consumable_orders on public.shipment_received;
drop trigger if exists trg_refresh_consumable_cost_on_receipt      on public.shipment_received;
-- 🔴 And its OWN name. This file was applied to prod by hand on 2026-09-08 while
-- prod's ledger recorded nothing, so CI would replay it and hit
-- "trigger ... already exists" — aborting the release at migration 55 of 69,
-- AFTER 20260908000011 re-runs its fleet-wide backfill and BEFORE
-- 20260908000014 undoes the damage. Two of the four hand-applied cost
-- migrations dropped their own trigger first; this one did not.
drop trigger if exists trg_refresh_consumables_for_shipment on public.shipment_received;

create trigger trg_refresh_consumables_for_shipment
  after update of shipping_cost_unit, date_received on public.shipment_received
  for each row execute function public.refresh_consumables_for_shipment();

-- The old wrapper is now unreferenced. Kept rather than dropped: 20260908000010
-- created it, and dropping a function a shipped migration created makes that
-- migration unreplayable from scratch. It is inert — no trigger points at it.
comment on function public.propagate_shipping_to_consumable_orders() is
  'SUPERSEDED by refresh_consumables_for_shipment() in 20260908000012 — its shipping-only guard made it a no-op when a delivery was marked received. No trigger references it.';

commit;
