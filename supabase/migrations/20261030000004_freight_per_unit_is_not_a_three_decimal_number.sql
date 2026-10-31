-- Freight per unit is not a three-decimal number.
--
-- 🔴 REDUCED 2026-10-31 AFTER IT TIMED OUT ON PROD. This migration used to
-- carry a backfill as well. It now changes the FUNCTION ONLY; correcting the
-- history lives in `scripts/backfill-freight-per-unit.sql`, which commits in
-- batches. Why, because the reasoning is the point:
--
--   The backfill was a single no-op write to all 121 freight-carrying
--   shipments. Each one gives `shipping_cost_unit` a genuinely new (unrounded)
--   value, and `refresh_consumables_for_shipment` only skips when that column
--   is unchanged -- so every row fires the full cascade:
--   refresh_last_consumable_cost, refresh_consumable_stock, and
--   recost_orders_for_consumable_purchase per consumable line, against 39,986
--   order_details rows. Measured on prod by forcing one genuine rate change
--   and rolling back: 8,966ms for the worst shipment (31 consumable lines),
--   ~20ms for one with none -- about 285ms per consumable line. 277 lines are
--   in scope, so ~81s at best, and the real run passed the 120s
--   statement_timeout (57014) and rolled the whole release back.
--
--   Raising the timeout would only buy the other problem: ~2 minutes of write
--   locks on shipment_received, consumable_inventory and order_details inside
--   one transaction. That is the shape that has taken this app down before.
--   A migration must be quick and must not be the thing that re-costs an
--   entire order book.
--
-- So: this half is instant and stops the error at the source -- nothing stores
-- a rounded rate from here on. The $236.22 already misstated across 96
-- shipments is historical data, not schema, and it is corrected separately
-- where it can be batched, resumed and watched.
--
-- ---------------------------------------------------------------------------
-- WHY THE ROUND HAD TO GO (unchanged from the original):
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
--
-- See scripts/backfill-freight-per-unit.sql for the history correction.

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

commit;
