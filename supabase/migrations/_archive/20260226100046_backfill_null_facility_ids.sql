-- Migration 00046: Backfill NULL facility_id on shipment_received and roast_log
--
-- Pre-facility data (imported from Google Sheets) has facility_id = NULL.
-- AppSheet filters by facility, so these rows are invisible.
-- All data belongs to company R7CbqHmA1j → facility cc844abb.

-- ═══════════════════════════════════════════════════════════════
-- A. Backfill shipment_received (30 rows)
-- ═══════════════════════════════════════════════════════════════

UPDATE public.shipment_received
SET facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de'
WHERE facility_id IS NULL
  AND company_id = 'R7CbqHmA1j';

-- ═══════════════════════════════════════════════════════════════
-- B. Backfill roast_log (2 rows)
-- ═══════════════════════════════════════════════════════════════

UPDATE public.roast_log
SET facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de'
WHERE facility_id IS NULL
  AND company_id = 'R7CbqHmA1j';

-- ═══════════════════════════════════════════════════════════════
-- C. Recalculate coffee inventory (shipment inflows may change)
-- ═══════════════════════════════════════════════════════════════
-- Now that shipments have the correct facility_id, the facility-scoped
-- purchase queries in handle_manual_inventory_update() will find them.

SELECT set_config('app.from_history_trigger', 'true', true);

UPDATE public.coffee_inventory
SET last_inventory = last_inventory
WHERE facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de';

-- Also recalculate consumable inventory
UPDATE public.consumable_inventory
SET updated_at = NOW()
WHERE facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de';
