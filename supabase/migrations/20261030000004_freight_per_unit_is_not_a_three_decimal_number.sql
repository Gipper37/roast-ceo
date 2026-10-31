-- Freight per unit is not a three-decimal number.
--
-- calculate_shipping_per_unit() has always stored
--
--     shipping_cost_unit = ROUND(NEW.shipping_cost / v_total_weight, 3)
--
-- and that column is not a display figure. refresh_last_consumable_cost() adds
-- it straight to cost_unit to produce consumable_inventory.last_cost_unit, and
-- recalculate_inventory_cost() does the equivalent on the coffee side, so the
-- rounding lands in stock valuation and COGS.
--
-- A consumable unit costs fractions of a cent, and three decimals is coarser
-- than the number. Maui Coffee Roasters' 2026-10-20 label shipment:
--
--     $150.98 / 4,000 units = $0.0377450  ->  stored $0.038
--     $0.038 x 4,000        = $152.00     ->  $1.02 of freight that nobody paid
--
-- Across production today that is $236.22 of freight misstated over 191
-- shipments in 4 companies, in both directions -- some over, some under. The
-- error grows as the unit gets cheaper, and it does not degrade gracefully: a
-- true freight share of $0.0004/unit rounds to $0.000 and the freight term
-- disappears from the cost entirely.
--
-- The owner found it from the other end, as two screens that would not agree:
-- the shipment page divides live and the consumable page reads this column.
--
-- Nothing is rounded here instead. A rate is stored at whatever precision the
-- division has, and the three decimals the UI needs are a formatting decision
-- made in the UI (lib/locale.ts fmtUnitCurrency). Picking a scale in the
-- database is guessing which numbers deserve precision before you have seen
-- them.
--
-- The backfill is a no-op write to shipping_cost, not a direct write to
-- shipping_cost_unit. trigger_update_shipping_unit_cost is AFTER INSERT OR
-- UPDATE with NO column list, so it fires on any update to the row and would
-- have overwritten a direct backfill with ROUND(...) again. Replacing the
-- function first and then touching the row makes the trigger itself write the
-- exact value, which is also what keeps the cascade honest:
-- trg_refresh_consumables_for_shipment fires on the resulting
-- shipping_cost_unit change and re-derives last_cost_unit, stock and order
-- costs; trg_propagate_shipping_cost re-costs the coffee origins. Those are
-- the figures that were wrong, so they have to move.
--
-- What deliberately does NOT fire: trg_shipment_lot_recompute,
-- trg_shipment_release_here_first, trg_sync_bag_size_on_shipment_received and
-- trg_void_shipment_cascade are all scoped to date_received / voided, which
-- this does not touch. The expensive lot work stays asleep. Expected scope:
-- 121 rows, 277 consumable lines, 164 items, 37 coffee origins.
--
-- NOT fixed here, and still open: v_total_weight below is
-- SUM(coffee pounds) + SUM(consumable units), so on a shipment carrying both,
-- freight is divided by a quantity of nothing. That needs an allocation rule
-- and a decision, not a precision fix, and it is a separate change.

begin;

-- Body taken verbatim from the live definition; the ONLY edit is dropping the
-- ROUND. Retyping a function body is how the rest of it quietly changes.
CREATE OR REPLACE FUNCTION public.calculate_shipping_per_unit()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_total_weight NUMERIC;
BEGIN
    -- 1. Anti-Recursion: Stop if we are already inside this trigger
    IF pg_trigger_depth() > 1 THEN RETURN NEW; END IF;

    -- 2. Calculate the TRUE Total Weight (Coffee LBS + Consumable UNITS)
    v_total_weight := (
        SELECT COALESCE(SUM(amount), 0)
        FROM coffee_inventory_purchased
        WHERE shipment_id = NEW.shipment_id
          AND facility_id = NEW.facility_id
    ) + (
        SELECT COALESCE(SUM(amount), 0)
        FROM consumable_inventory_purchased
        WHERE shipment_id = NEW.shipment_id
          AND facility_id = NEW.facility_id
    );

    -- 3. Update BOTH the Total Weight and the Cost Per Unit
    UPDATE shipment_received
    SET shipping_cost_unit = CASE
            WHEN v_total_weight > 0 THEN NEW.shipping_cost / v_total_weight
            ELSE 0
        END,
        shipment_total_weight_units = v_total_weight
    WHERE shipment_id = NEW.shipment_id
      AND facility_id = NEW.facility_id;

    RETURN NEW;
END;
$function$;

comment on function public.calculate_shipping_per_unit() is
  'Derives shipment_received.shipping_cost_unit and shipment_total_weight_units. '
  'Stores the rate UNROUNDED on purpose: it feeds last_cost_unit and COGS, a '
  'consumable unit costs fractions of a cent, and rounding here once misstated '
  '$236.22 of freight across production. Round for display, never in the column. '
  'Known defect, unrelated to precision: v_total_weight sums coffee POUNDS and '
  'consumable UNITS, so a mixed shipment divides freight by a quantity of nothing.';

-- Re-derive every stored rate. A no-op write to shipping_cost, because the
-- trigger above owns shipping_cost_unit and would overwrite a direct write.
update public.shipment_received
   set shipping_cost = shipping_cost
 where shipping_cost is not null;

-- Every shipment that has a freight bill and a quantity to divide it by must
-- now multiply back to within a cent of what was actually paid. Before this
-- migration 119 rows failed that; if any still does, the backfill did not take
-- and the cascade behind it ran on wrong numbers, so refuse the release.
do $$
declare
  v_bad integer;
begin
  select count(*)
    into v_bad
    from public.shipment_received
   where shipping_cost is not null
     and shipment_total_weight_units > 0
     and abs(shipping_cost_unit * shipment_total_weight_units - shipping_cost) > 0.01;

  if v_bad > 0 then
    raise exception
      'freight per unit still misstated on % shipment(s) after the backfill', v_bad;
  end if;
end $$;

commit;
