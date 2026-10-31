-- One batch of the freight-per-unit history correction.
--
-- Called repeatedly by backfill-freight-per-unit.sh. Each invocation is its own
-- transaction and COMMITS, which is the whole point: the equivalent single
-- statement needs ~81s and holds write locks on shipment_received,
-- consumable_inventory and order_details for the duration, and it blew the 120s
-- statement_timeout when it shipped inside migration 20261030000004.
--
-- :batch is the number of shipments to correct in this transaction.
--
-- The write is a no-op update to shipping_cost on purpose:
-- trigger_update_shipping_unit_cost owns shipping_cost_unit and would overwrite
-- a direct write, so the trigger is made to re-derive the value itself. That is
-- also what keeps the cascade honest -- trg_refresh_consumables_for_shipment
-- re-derives last_cost_unit, consumable stock and order costs, and
-- trg_propagate_shipping_cost re-costs the coffee origins. Those are the
-- figures the rounding corrupted, so they have to move.
--
-- The selection predicate MIRRORS calculate_shipping_per_unit exactly, so it is
-- idempotent and resumable: a row stops matching the moment it is correct, and
-- re-running after a crash picks up precisely what is left. It does NOT use a
-- "within a cent" tolerance -- that left 2 prod rows wrong by less than a cent
-- but wrong.

begin;

set local statement_timeout = '120s';
-- Fail fast rather than queue behind a user's transaction: the shell retries.
set local lock_timeout = '5s';

update public.shipment_received
   set shipping_cost = shipping_cost
 where shipment_id in (
   select shipment_id
     from public.shipment_received
    where shipping_cost is not null
      and shipping_cost_unit is distinct from
          (case when shipment_total_weight_units > 0
                then shipping_cost / shipment_total_weight_units
                else 0 end)
    order by shipment_id
    limit :batch
 );

commit;
