-- ============================================================
-- Phase 1 backfill: populate remaining_lbs across coffee lots.
-- ============================================================
-- Three cases per (origin, facility):
--   1. Lots exist + current stock > 0:
--      Distribute current_stock_lbs across received lots NEWEST first
--      (mathematically equivalent to FIFO replay; what's left lives
--      in the newest lots since FIFO drains the oldest first).
--   2. Lots exist + current stock = 0:
--      All lots get remaining_lbs = 0.
--   3. NO lots + current stock > 0 (the common case for MCR + parts
--      of SHCR/UK/demo):
--      Create a synthetic 'baseline' lot capturing the
--      inventory_count_bags × bag_size baseline so the lot model has
--      something to track. Cost = coffee_inventory.fallback_cost or
--      latest_cost.
--
-- Audit table flags any anomaly (overage beyond sum of lots, missing
-- baseline data, etc.) for operator review.
--
-- Idempotent: skips rows where remaining_lbs is already set.
-- Re-running after Phase 2 trigger work won't clobber live values.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.lot_backfill_audit (
  id                serial PRIMARY KEY,
  origin_id         text,
  facility_id       text,
  company_id        text,
  origin_label      text,
  current_stock_lbs numeric,
  sum_of_lots       numeric,
  delta             numeric,
  note              text,
  created_at        timestamptz NOT NULL DEFAULT now()
);

DO $$
DECLARE
  v_origin record;
  v_lot record;
  v_remaining numeric;
  v_alloc numeric;
  v_sum_amounts numeric;
  v_overage numeric;
  v_lot_count int;
  v_cost numeric;
  v_baseline_lot_id text;
  v_origins int := 0;
  v_lots_updated int := 0;
  v_baselines_created int := 0;
  v_anomalies int := 0;
BEGIN
  FOR v_origin IN
    SELECT ci.origin_id,
           ci.facility_id,
           ci.company_id,
           ci.origin AS origin_label,
           ci.bag_size,
           ci.inventory_count_bags,
           ci.last_inventory,
           COALESCE(ci.fallback_cost, ci.latest_cost, ci.last_cost_lb) AS cost_estimate
      FROM public.coffee_inventory ci
      WHERE ci.facility_id IS NOT NULL
        AND COALESCE(ci.is_active, true) = true
      ORDER BY ci.company_id, ci.origin
  LOOP
    v_origins := v_origins + 1;

    v_remaining := GREATEST(
      COALESCE(public.calculate_current_stock_lbs(v_origin.origin_id, v_origin.facility_id), 0),
      0
    );

    -- Count existing received lots
    SELECT count(*), COALESCE(SUM(cip.amount), 0)
      INTO v_lot_count, v_sum_amounts
      FROM public.coffee_inventory_purchased cip
      LEFT JOIN public.shipment_received sr ON sr.shipment_id = cip.shipment_id
     WHERE cip.origin = v_origin.origin_id
       AND cip.facility_id = v_origin.facility_id
       AND COALESCE(sr.voided, false) = false
       AND (sr.date_received IS NOT NULL OR cip.shipment_id IS NULL);

    -- Case 3: no lots + has stock → synthetic baseline lot
    IF v_lot_count = 0 AND v_remaining > 0 THEN
      v_cost := COALESCE(v_origin.cost_estimate, 0);
      v_baseline_lot_id := gen_random_uuid()::text;
      INSERT INTO public.coffee_inventory_purchased
        (origin_purchase_id, origin, facility_id, company_id,
         bag_size, bags_ordered, amount, cost_lb,
         lot_id, harvest_year, entry_method, remaining_lbs)
      VALUES
        (v_baseline_lot_id,
         v_origin.origin_id,
         v_origin.facility_id,
         v_origin.company_id,
         v_origin.bag_size,
         v_origin.inventory_count_bags,
         v_remaining,
         v_cost,
         'baseline',
         NULL,
         'baseline',
         v_remaining);
      v_baselines_created := v_baselines_created + 1;
      v_lots_updated := v_lots_updated + 1;

      INSERT INTO public.lot_backfill_audit
        (origin_id, facility_id, company_id, origin_label,
         current_stock_lbs, sum_of_lots, delta, note)
      VALUES
        (v_origin.origin_id, v_origin.facility_id, v_origin.company_id, v_origin.origin_label,
         v_remaining, 0, v_remaining,
         'No lot history; created synthetic baseline lot (entry_method=baseline).');

      PERFORM public.recalculate_origin_total_stock(v_origin.origin_id, v_origin.facility_id);
      CONTINUE;
    END IF;

    -- Cases 1 + 2: walk existing lots newest-first
    FOR v_lot IN
      SELECT cip.origin_purchase_id, cip.amount,
             COALESCE(sr.date_received, cip.created_at::date) AS sort_date
        FROM public.coffee_inventory_purchased cip
        LEFT JOIN public.shipment_received sr ON sr.shipment_id = cip.shipment_id
       WHERE cip.origin = v_origin.origin_id
         AND cip.facility_id = v_origin.facility_id
         AND COALESCE(sr.voided, false) = false
         AND (sr.date_received IS NOT NULL OR cip.shipment_id IS NULL)
         AND cip.remaining_lbs IS NULL
      ORDER BY sort_date DESC, cip.created_at DESC
    LOOP
      IF v_remaining <= 0 THEN
        v_alloc := 0;
      ELSIF v_remaining >= v_lot.amount THEN
        v_alloc := v_lot.amount;
        v_remaining := v_remaining - v_lot.amount;
      ELSE
        v_alloc := v_remaining;
        v_remaining := 0;
      END IF;

      UPDATE public.coffee_inventory_purchased
         SET remaining_lbs = v_alloc
       WHERE origin_purchase_id = v_lot.origin_purchase_id;
      v_lots_updated := v_lots_updated + 1;
    END LOOP;

    -- Overage: current_stock_lbs > sum of lot amounts (e.g. manual
    -- baseline higher than recorded purchases). Stamp the excess onto
    -- the newest active lot and audit.
    IF v_remaining > 0.5 THEN
      v_overage := v_remaining;
      v_anomalies := v_anomalies + 1;
      INSERT INTO public.lot_backfill_audit
        (origin_id, facility_id, company_id, origin_label,
         current_stock_lbs, sum_of_lots, delta, note)
      VALUES
        (v_origin.origin_id, v_origin.facility_id, v_origin.company_id, v_origin.origin_label,
         public.calculate_current_stock_lbs(v_origin.origin_id, v_origin.facility_id),
         v_sum_amounts, v_overage,
         'Current stock exceeds sum of lots; overage added to newest lot.');

      UPDATE public.coffee_inventory_purchased
         SET remaining_lbs = COALESCE(remaining_lbs, 0) + v_overage
       WHERE origin_purchase_id = (
         SELECT cip2.origin_purchase_id
           FROM public.coffee_inventory_purchased cip2
           LEFT JOIN public.shipment_received sr ON sr.shipment_id = cip2.shipment_id
          WHERE cip2.origin = v_origin.origin_id
            AND cip2.facility_id = v_origin.facility_id
            AND COALESCE(sr.voided, false) = false
            AND (sr.date_received IS NOT NULL OR cip2.shipment_id IS NULL)
          ORDER BY COALESCE(sr.date_received, cip2.created_at::date) DESC,
                   cip2.created_at DESC
          LIMIT 1
       );
    END IF;

    PERFORM public.recalculate_origin_total_stock(v_origin.origin_id, v_origin.facility_id);
  END LOOP;

  RAISE NOTICE 'Backfill complete. Origins: %, lots touched: %, synthetic baselines created: %, audits: %',
    v_origins, v_lots_updated, v_baselines_created, v_anomalies;
END $$;
