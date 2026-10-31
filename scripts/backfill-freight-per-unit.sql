-- Correct ONE shipment's stored freight-per-unit rate. :sid is its shipment_id.
--
-- 🔴 ON_ERROR_STOP LIVES IN THE FILE, NOT IN THE CALLER. Without it psql
-- reports a failed UPDATE, carries on to `commit;` -- which in an aborted
-- transaction is a silent ROLLBACK -- and exits 0. That is exactly what
-- happened on the first prod run: a batch hit the statement timeout, rolled
-- back, and reported success. A caller that forgets a flag must not be able to
-- turn a failure into a no-op.
\set ON_ERROR_STOP on

begin;

-- Per ROW, not per batch. Most shipments cost ~nothing (the cascade's loops
-- iterate over their consumable lines, and most have none), but a few run
-- recost_orders_for_consumable_purchase -> get_product_cogs_on_date ->
-- get_origin_roasted_cost_on_date, which aggregates roast history and can
-- exceed a minute on its own. One row at a time means one slow shipment is
-- skippable instead of taking a whole batch down with it.
set local statement_timeout = :'rowtimeout';
-- Fail fast rather than queue behind a real user's transaction.
set local lock_timeout = '5s';

-- The write is a no-op update to shipping_cost on purpose:
-- trigger_update_shipping_unit_cost owns shipping_cost_unit and would overwrite
-- a direct write, so the trigger is made to re-derive the value itself. That is
-- also what keeps the cascade honest -- trg_refresh_consumables_for_shipment
-- re-derives last_cost_unit, consumable stock and order costs, and
-- trg_propagate_shipping_cost re-costs the coffee origins. Those are the
-- figures the rounding corrupted, so they have to move.
update public.shipment_received
   set shipping_cost = shipping_cost
 where shipment_id = :'sid';

commit;
