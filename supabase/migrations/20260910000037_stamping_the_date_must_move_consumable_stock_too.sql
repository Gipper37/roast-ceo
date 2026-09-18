-- Marking a delivery received must move consumable STOCK, not only its cost.
--
-- Three triggers on shipment_received are AFTER UPDATE OF date_received —
-- trg_shipment_lot_recompute, trg_sync_bag_size_on_shipment_received and
-- trg_refresh_consumables_for_shipment. An INSERT fires none of them, so a
-- recorded delivery now writes its header with date_received NULL, inserts the
-- lines, and stamps the date in a second statement. That is what makes the
-- coffee land.
--
-- It does not make the consumables land. refresh_consumables_for_shipment()
-- loops the shipment's purchase rows and refreshes the CACHED COST and the
-- orders that consumed it — and nothing else. The cached stock figures on
-- consumable_inventory (in_stock / par / restock_level / to_order) are written
-- only by update_consumable_stock_purchased(), the line trigger on
-- consumable_inventory_purchased. That trigger did fire, when the lines went
-- in, but it recomputes through calculate_current_stock_consumables(), which
-- counts a purchase only
--
--     where sr.date_received > last_inventory_date and sr.date_received is not null
--
-- and at that moment the header is still undated. So the recount ran, saw the
-- new lines as not-yet-received, and left in_stock where it was. The frontend
-- papers over this today by re-touching the purchase rows after the stamp,
-- purely to make the line trigger fire a second time against a now-dated
-- header. This migration is what lets that workaround be deleted.
--
-- The same hole is open in receiveShipment, and has been all along: receiving
-- an existing shipment stamps date_received, which refreshes the cost — but if
-- the receiver edits no consumable cost, no line row is ever touched, so
-- nothing recomputes stock and in_stock stays stale until the next purchase or
-- the next count. Putting the recompute behind the DATE rather than behind a
-- line edit closes both paths at once.
--
-- Shape: the recompute block moves into one function that both callers invoke,
-- rather than a second copy living inside refresh_consumables_for_shipment().
-- The line-trigger path is unchanged — same three calculators, same update,
-- same columns, same NULL return.
--
-- Plain SECURITY INVOKER with no search_path, matching every other function in
-- this family and every reference inside it schema-qualified. Invoker is the
-- point, not an omission: the update runs as whoever wrote the row, so RLS
-- decides which consumable_inventory row it is allowed to move.
--
-- EXECUTE is NOT left at the default. The two callers are trigger functions,
-- which PostgREST will not expose; this helper returns numeric, so at the
-- default grant it would arrive as a new anon-reachable
-- POST /rest/v1/rpc/refresh_consumable_stock that performs an UPDATE. RLS and
-- SECURITY INVOKER would hold it — anon is not on consumable_inventory's ACL
-- and the tenant policy is granted to authenticated only — but a writable RPC
-- that nothing needs should not be on the public surface at all. This is the
-- save_shipment_lines lesson from 2026-08-04: a new signature arrives with
-- PUBLIC EXECUTE unless the migration that creates it says otherwise.

begin;

create or replace function public.refresh_consumable_stock(p_item_id text, p_facility_id text)
returns numeric
language plpgsql
as $$
declare
  v_current_stock  numeric;
  v_par            numeric;
  v_restock_level  numeric;
begin
  v_current_stock := public.calculate_current_stock_consumables(p_item_id, p_facility_id);
  v_par           := public.calculate_consumable_par(p_item_id, p_facility_id);
  v_restock_level := public.calculate_consumable_restock_level(p_item_id, p_facility_id);

  update public.consumable_inventory
  set
      in_stock      = v_current_stock,
      par           = v_par,
      restock_level = v_restock_level,
      to_order      = case
                          when v_current_stock <= v_restock_level
                          then greatest(0, v_par - v_current_stock)
                          else 0
                      end,
      updated_at    = now()
  where consumable_inventory_id = p_item_id
    and facility_id = p_facility_id;

  return v_current_stock;
end;
$$;

comment on function public.refresh_consumable_stock(text, text) is
  'Recompute the cached stock figures for one consumable at one facility: in_stock, par, restock_level and to_order. The definition the line trigger and the receipt trigger share; void_shipment_cascade still carries its own partial copy (in_stock only).';

revoke all on function public.refresh_consumable_stock(text, text) from public;
grant execute on function public.refresh_consumable_stock(text, text) to authenticated, service_role;

-- Same three calculators, same update, same NULL return as before; the block
-- itself now lives in one place instead of two.
create or replace function public.update_consumable_stock_purchased()
returns trigger
language plpgsql
as $$
declare
    v_target_id    text;
    v_facility_id  text;
begin
    v_target_id   := coalesce(new.consumable_inventory_item, old.consumable_inventory_item);
    v_facility_id := coalesce(new.facility_id, old.facility_id);

    perform public.refresh_consumable_stock(v_target_id, v_facility_id);

    return null;
end;
$$;

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

  -- Cached figures first, so anything reading them afterwards is current.
  -- Stock belongs here and not only on the line trigger: that trigger runs
  -- while the header is still undated, so its recount cannot see these rows.
  --
  -- Cost and stock are per ITEM, so a shipment carrying four lines of the same
  -- box recomputes it once, not four times. The order re-cost stays per LINE
  -- because that is what it keys on. Splitting the loops also means every cost
  -- is current before the first re-cost reads one.
  for r in
    select distinct consumable_inventory_item, facility_id
      from public.consumable_inventory_purchased
     where shipment_id = new.shipment_id
       and facility_id is not distinct from new.facility_id
  loop
    perform public.refresh_last_consumable_cost(r.consumable_inventory_item, r.facility_id);
    perform public.refresh_consumable_stock(r.consumable_inventory_item, r.facility_id);
  end loop;

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

comment on function public.refresh_consumables_for_shipment() is
  'Recompute a shipment''s consumable costs and stock, and re-cost the orders that consumed them. Runs when shipping_cost_unit moves (shipping edit or units correction) or when date_received appears (the delivery landed).';

commit;
