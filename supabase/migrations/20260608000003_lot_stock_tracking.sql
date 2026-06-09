-- ============================================================
-- Phase 1: Per-lot coffee stock tracking (additive)
-- ============================================================
-- Moves stock truth from the group level (coffee_inventory) down to
-- the lot level (coffee_inventory_purchased). Each lot now carries its
-- own remaining_lbs that decrements as roasts consume from it (via
-- FIFO when coffee_source_id is set on roast_log, group-level fallback
-- when not).
--
-- This migration is ADDITIVE — no triggers changed, no UI changes
-- required. Existing read paths (calculate_current_stock_lbs, etc.)
-- continue to work unchanged. Phase 2 will wire up the deduction
-- triggers and the lot-aware picker UI; Phase 3 will deprecate the
-- group-level bag_size + inventory_count_bags caches.
--
-- Schema changes:
--   coffee_inventory_purchased.remaining_lbs numeric
--     Per-lot stock remaining. Backfilled by distributing each
--     origin's current_stock_lbs across its lots newest-first
--     (mathematically equivalent to FIFO replay).
--
--   coffee_inventory_purchased.entry_method text default 'shipment'
--     Distinguishes how this lot was recorded. 'shipment' is the
--     normal flow (invoice / shipment-received page). 'roast_quick_add'
--     marks lots created from the in-picker quick-receive affordance
--     so the eventual full-shipment processing can offer to reconcile
--     them. Other values reserved for future flows (e.g. 'manual').
--
--   coffee_inventory.total_stock_lbs numeric
--     Cached sum of remaining_lbs across all active lots for this
--     origin/facility. Drives the inventory-page rollup display
--     without forcing a per-render aggregate query.
--
--   roast_log_lot_consumption table
--     Per-roast audit trail of which lot(s) actually got drained. One
--     row per (roast_log, lot) pair. Cross-lot roasts (where a single
--     charge spans multiple lots due to FIFO) produce multiple rows.
--     RLS via the parent roast_log row's facility.
-- ============================================================

-- ── 1. Lot stock columns ─────────────────────────────────────────
ALTER TABLE public.coffee_inventory_purchased
  ADD COLUMN IF NOT EXISTS remaining_lbs numeric,
  ADD COLUMN IF NOT EXISTS entry_method  text NOT NULL DEFAULT 'shipment';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'coffee_inventory_purchased_entry_method_chk'
  ) THEN
    ALTER TABLE public.coffee_inventory_purchased
      ADD CONSTRAINT coffee_inventory_purchased_entry_method_chk
      CHECK (entry_method IN ('shipment', 'roast_quick_add', 'manual'));
  END IF;
END $$;

COMMENT ON COLUMN public.coffee_inventory_purchased.remaining_lbs IS
  'Per-lot stock remaining in lbs. NULL until Phase 1 backfill populates it; '
  'thereafter maintained by triggers (Phase 2).';

COMMENT ON COLUMN public.coffee_inventory_purchased.entry_method IS
  'How this lot row was created. shipment = invoice / shipment-received flow. '
  'roast_quick_add = inline quick-receive from the roast picker (no cost yet, '
  'pending reconciliation). manual = direct manual entry.';

-- ── 2. Group-level cached total ──────────────────────────────────
ALTER TABLE public.coffee_inventory
  ADD COLUMN IF NOT EXISTS total_stock_lbs numeric;

COMMENT ON COLUMN public.coffee_inventory.total_stock_lbs IS
  'Cached sum of remaining_lbs across all active lots for this (origin, '
  'facility). Display-only rollup. Maintained by Phase 2 triggers.';

-- ── 3. Roast-to-lot allocation audit trail ───────────────────────
CREATE TABLE IF NOT EXISTS public.roast_log_lot_consumption (
  id                  text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  roast_log_id        text NOT NULL REFERENCES public.roast_log(roast_log_id) ON DELETE CASCADE,
  origin_purchase_id  text NOT NULL REFERENCES public.coffee_inventory_purchased(origin_purchase_id) ON DELETE RESTRICT,
  lbs_consumed        numeric NOT NULL CHECK (lbs_consumed >= 0),
  created_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS roast_log_lot_consumption_roast_log_id_idx
  ON public.roast_log_lot_consumption (roast_log_id);

CREATE INDEX IF NOT EXISTS roast_log_lot_consumption_origin_purchase_id_idx
  ON public.roast_log_lot_consumption (origin_purchase_id);

ALTER TABLE public.roast_log_lot_consumption ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tenant_company_access ON public.roast_log_lot_consumption;
CREATE POLICY tenant_company_access ON public.roast_log_lot_consumption
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.roast_log rl
      WHERE rl.roast_log_id = roast_log_lot_consumption.roast_log_id
        AND rl.company_id IN (SELECT public.auth_company_ids())
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.roast_log rl
      WHERE rl.roast_log_id = roast_log_lot_consumption.roast_log_id
        AND rl.company_id IN (SELECT public.auth_company_ids())
    )
  );

COMMENT ON TABLE public.roast_log_lot_consumption IS
  'Audit trail of which lots a roast actually drained. One row per '
  '(roast_log, lot) pair. Cross-lot roasts produce multiple rows. '
  'Populated by Phase 2 deduction triggers.';

-- ── 4. Helper functions (read-only; no triggers depend on them yet)
-- lot_remaining_lbs(origin_purchase_id) — convenience read
CREATE OR REPLACE FUNCTION public.lot_remaining_lbs(p_origin_purchase_id text)
RETURNS numeric
LANGUAGE sql
STABLE
AS $$
  SELECT remaining_lbs
    FROM public.coffee_inventory_purchased
   WHERE origin_purchase_id = p_origin_purchase_id;
$$;

-- recalculate_origin_total_stock(origin, facility) — sums active lots
-- (entry_method != 'manual' OR all of them; we sum all non-null) and
-- writes coffee_inventory.total_stock_lbs. Called from Phase 2
-- triggers; safe to call manually anytime to refresh the cache.
CREATE OR REPLACE FUNCTION public.recalculate_origin_total_stock(
  p_origin_id text,
  p_facility_id text
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_total numeric;
BEGIN
  SELECT COALESCE(SUM(GREATEST(cip.remaining_lbs, 0)), 0)
    INTO v_total
    FROM public.coffee_inventory_purchased cip
    JOIN public.shipment_received sr ON sr.shipment_id = cip.shipment_id
   WHERE cip.origin = p_origin_id
     AND cip.facility_id = p_facility_id
     AND COALESCE(sr.voided, false) = false
     AND cip.remaining_lbs IS NOT NULL;

  -- Quick-add lots have no shipment_received row; include them too.
  SELECT v_total + COALESCE(SUM(GREATEST(cip.remaining_lbs, 0)), 0)
    INTO v_total
    FROM public.coffee_inventory_purchased cip
   WHERE cip.origin = p_origin_id
     AND cip.facility_id = p_facility_id
     AND cip.shipment_id IS NULL
     AND cip.remaining_lbs IS NOT NULL;

  UPDATE public.coffee_inventory
     SET total_stock_lbs = v_total,
         updated_at      = now()
   WHERE origin_id   = p_origin_id
     AND facility_id = p_facility_id;
END;
$$;

NOTIFY pgrst, 'reload schema';
