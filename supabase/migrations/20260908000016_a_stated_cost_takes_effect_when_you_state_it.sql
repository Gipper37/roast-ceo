-- Typing a unit cost has to change something.
--
-- The Cost Center's "items missing a cost" tab now writes fallback_unit_cost —
-- the column the owner confirmed is where a roaster STATES a cost. But nothing
-- derives from it on write: refresh_last_consumable_cost is only reachable from
-- triggers on consumable_inventory_purchased and shipment_received. So a
-- roaster would type a cost into an item that has never been delivered, the
-- stated column would take it, last_cost_unit would stay null, and the row
-- would still sit in the "missing a cost" list. Correct in the database and
-- broken on the screen.
--
-- No recursion risk: this fires on fallback_unit_cost specifically, and
-- refresh_last_consumable_cost writes last_cost_unit, which is not in the
-- trigger's column list.

begin;

create or replace function public.derive_cost_from_stated_fallback()
returns trigger
language plpgsql
as $$
begin
  if old.fallback_unit_cost is not distinct from new.fallback_unit_cost then
    return null;
  end if;
  perform public.refresh_last_consumable_cost(new.consumable_inventory_id, new.facility_id);
  return null;
end;
$$;

comment on function public.derive_cost_from_stated_fallback() is
  'A stated cost takes effect the moment it is stated. refresh_last_consumable_cost still prefers a received delivery, so this only fills in for items that have never had one.';

drop trigger if exists trg_derive_cost_from_stated_fallback on public.consumable_inventory;
create trigger trg_derive_cost_from_stated_fallback
  after update of fallback_unit_cost on public.consumable_inventory
  for each row execute function public.derive_cost_from_stated_fallback();

commit;
