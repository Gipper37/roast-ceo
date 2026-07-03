-- Keep the cached in_stock_lbs / in_stock columns in sync with lot-truth on
-- every lot recompute.
--
-- BUG: recalculate_origin_total_stock() — the common tail of every lot recompute
-- (roast, RECEIVE, void, borrow) — wrote only total_stock_lbs (lot-truth). But
-- the inventory LIST and the run-out / days-of-supply projection read the CACHED
-- columns in_stock_lbs / in_stock, which nothing refreshed on receive. So marking
-- a shipment received (which runs this recompute) bumped total_stock_lbs up but
-- left in_stock_lbs stale: the received lbs dropped out of the "en-route"
-- contribution but never appeared in on-hand → net projected supply FELL → the
-- run-out dates jumped CLOSER. (Operator report, 2026-06-30 receive. Also the
-- general "inventory list under-shows stock" divergence — receiving just exposed
-- it.) Confirmed on prod: e.g. Maui Mokka in_stock_lbs=0 vs total_stock_lbs=100.
--
-- FIX: write in_stock_lbs = in_stock's lot total, and in_stock (bags) = total /
-- bag_size, in the same UPDATE. The nudge trigger (trg_coffee_nudge_recalc,
-- BEFORE UPDATE OF updated_at) recomputes par/restock/to_order but NEVER touches
-- in_stock_lbs/in_stock, and it is depth-guarded (no-op during the nested receive
-- recompute), so this write always sticks. remaining_lbs is the lot truth, so the
-- cache can no longer drift.

CREATE OR REPLACE FUNCTION public.recalculate_origin_total_stock(
  p_origin_id text,
  p_facility_id text
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_total numeric;
  v_bag_size numeric;
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

  -- Operative per-bag size for the bags conversion (same fallback the stock
  -- trigger uses).
  SELECT COALESCE(bag_size::numeric, 154)
    INTO v_bag_size
    FROM public.coffee_inventory
   WHERE origin_id = p_origin_id
     AND facility_id = p_facility_id;
  v_bag_size := COALESCE(v_bag_size, 154);

  UPDATE public.coffee_inventory
     SET total_stock_lbs = v_total,
         in_stock_lbs    = v_total,                       -- keep the read cache in sync
         in_stock        = v_total / NULLIF(v_bag_size, 0),
         updated_at      = now()
   WHERE origin_id   = p_origin_id
     AND facility_id = p_facility_id;
END;
$$;

-- One-time backfill: realign the cache to lot-truth for every origin whose cache
-- has already drifted (e.g. the June-30 receive that never landed on-hand). Uses
-- the canonical recompute so total/in_stock and par/to_order all reconcile.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT origin_id, facility_id
      FROM public.coffee_inventory
     WHERE total_stock_lbs IS NOT NULL
       AND ABS(COALESCE(in_stock_lbs, 0) - total_stock_lbs) > 0.5
  LOOP
    PERFORM public.recalculate_origin_total_stock(r.origin_id, r.facility_id);
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';
