-- 20260426000001_kg_facility_cost_unit_correction.sql
--
-- One-time data correction for kg-display facilities. Until this migration's
-- companion app changes, the coffee shipment form labeled cost inputs as
-- "$/kg" for facilities with company_parameters.units = 'kg', but saved the
-- raw value into columns that the schema and all cost-recalc triggers treat
-- as "$/lb". Result: every cost_lb / target_cost_lb / shipping_cost_unit on
-- those facilities is stored at ~2.20462× the intended value, which inflates
-- coffee_inventory.latest_cost, recipe_components.component_cost, and
-- products.total_unit_cogs by the same factor.
--
-- Fix: divide the affected per-weight cost columns by KG_TO_LBS (2.20462)
-- so they correctly represent $/lb. Order matters — bump shipping first
-- so the AFTER UPDATE trigger on coffee_inventory_purchased.cost_lb (which
-- calls recalculate_inventory_cost) reads the already-corrected shipping
-- value when it rebuilds latest_cost.
--
-- Idempotency: if rerun, this would corrupt data further. The migrations
-- changelog and supabase_migrations.schema_migrations table both prevent
-- reruns. Do not run by hand.
--
-- shipment_received.shipping_cost (no _unit suffix) is a TOTAL across the
-- whole shipment, not per-lb — leave alone.
-- coffee_inventory.latest_cost / last_cost_lb / last_shipping_cost are all
-- recomputed by triggers when cost_lb / shipping_cost_unit change, so we
-- don't touch them directly.
-- coffee_inventory.fallback_cost is user-entered per-lb; if a kg facility
-- has any non-null values, treat them with the same fix.

BEGIN;

-- Skip audit machinery so the bulk update doesn't churn audit metadata.
SET LOCAL app.skip_audit = 'true';

WITH kg_facilities AS (
  SELECT facility_id
    FROM company_parameters
   WHERE parameter_id = 'units' AND value = 'kg'
)
UPDATE shipment_received sr
   SET shipping_cost_unit = shipping_cost_unit * 0.45359237
  FROM kg_facilities k
 WHERE sr.facility_id = k.facility_id
   AND sr.shipping_cost_unit IS NOT NULL;

WITH kg_facilities AS (
  SELECT facility_id
    FROM company_parameters
   WHERE parameter_id = 'units' AND value = 'kg'
)
UPDATE coffee_inventory_purchased cp
   SET cost_lb        = CASE WHEN cp.cost_lb        IS NOT NULL THEN cp.cost_lb        * 0.45359237 ELSE NULL END,
       target_cost_lb = CASE WHEN cp.target_cost_lb IS NOT NULL THEN cp.target_cost_lb * 0.45359237 ELSE NULL END
  FROM kg_facilities k
 WHERE cp.facility_id = k.facility_id
   AND (cp.cost_lb IS NOT NULL OR cp.target_cost_lb IS NOT NULL);

WITH kg_facilities AS (
  SELECT facility_id
    FROM company_parameters
   WHERE parameter_id = 'units' AND value = 'kg'
)
UPDATE coffee_inventory ci
   SET fallback_cost = ci.fallback_cost * 0.45359237
  FROM kg_facilities k
 WHERE ci.facility_id = k.facility_id
   AND ci.fallback_cost IS NOT NULL;

-- Belt-and-suspenders: re-run cost recalc for every kg-facility origin so
-- coffee_inventory.latest_cost is rebuilt from the now-correct cost_lb +
-- shipping_cost_unit + retention. The per-row triggers above should have
-- already done this, but a manual sweep guarantees no stale rows survive
-- (e.g. if a row had cost_lb NULL but a fallback_cost, the trigger wouldn't
-- have fired).
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT ci.origin_id, ci.facility_id
      FROM coffee_inventory ci
      JOIN company_parameters cp ON cp.facility_id = ci.facility_id
     WHERE cp.parameter_id = 'units' AND cp.value = 'kg'
  LOOP
    PERFORM public.recalculate_inventory_cost(r.origin_id, r.facility_id);
  END LOOP;
END $$;

COMMIT;
