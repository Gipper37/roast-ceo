-- recompute_origin_lot_consumption re-seed: ignore counts dated BEFORE a lot's
-- receipt, and treat a lot received ON/AFTER the last group count as fresh stock.
--
-- BUG (operator report, MCR June-30 shipment): 6 lots ordered in March were
-- COUNTED at 0 lbs on 2026-06-12 while still en route, then RECEIVED 2026-06-30
-- with 6,600 / 3,040 / 5,280 … lbs. The re-seed used "this lot's latest count"
-- (the June-12 zero, a PRE-receipt count) and the fallback zeroed any lot
-- received on/before the group's last count date (2026-06-30). So ~27,800
-- received lbs were wiped to 0 → total_stock_lbs (and the in_stock cache) missed
-- them → the shipment never showed in on-hand.
--
-- FIX: (a) a lot's count only counts if it was taken ON/AFTER the lot's receipt
-- (a pre-receipt count can't be its truth); (b) the uncounted fallback uses
-- date_received >= last_count (was strictly >), so a lot received the same day as
-- the last count is fresh stock at its full amount, not 0. A re-order of the same
-- lot number is a separate purchase row, so its amount adds independently. Then
-- the FIFO replay deducts real roasts. Strictly more correct; only changes lots
-- that carry a pre-receipt count or were received on the last-count date.

CREATE OR REPLACE FUNCTION public.recompute_origin_lot_consumption(p_origin_id text, p_facility_id text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_roast record;
    v_needed numeric;
    v_pref text;
    v_force text;
    v_last_count_at timestamptz;
    v_tz text;
BEGIN
    IF p_origin_id IS NULL OR p_facility_id IS NULL THEN RETURN; END IF;

    SELECT COALESCE(NULLIF(time_zone, ''), 'UTC') INTO v_tz
      FROM public.facilities WHERE facility_id = p_facility_id;
    v_tz := COALESCE(v_tz, 'UTC');

    SELECT MAX(clc.count_at) INTO v_last_count_at
      FROM public.coffee_lot_count clc
      JOIN public.coffee_inventory_purchased cip2 ON cip2.origin_purchase_id = clc.origin_purchase_id
     WHERE cip2.origin = p_origin_id AND cip2.facility_id = p_facility_id;

    UPDATE public.coffee_inventory_purchased cip
       SET remaining_lbs = NULL
     WHERE cip.origin = p_origin_id AND cip.facility_id = p_facility_id
       AND cip.shipment_id IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM public.shipment_received sr
          WHERE sr.shipment_id = cip.shipment_id
            AND sr.date_received IS NOT NULL
            AND COALESCE(sr.voided, false) = false);

    UPDATE public.coffee_inventory_purchased cip
       SET remaining_lbs = CASE
            WHEN v_last_count_at IS NULL THEN cip.amount
            ELSE COALESCE(
              -- this lot's OWN latest count, but ONLY if taken on/after the lot's
              -- receipt (a pre-receipt count can't be the lot's truth).
              (SELECT clc.counted_remaining_lbs
                 FROM public.coffee_lot_count clc
                WHERE clc.origin_purchase_id = cip.origin_purchase_id
                  AND clc.count_at >= COALESCE(
                        (SELECT sr.date_received::timestamptz
                           FROM public.shipment_received sr WHERE sr.shipment_id = cip.shipment_id),
                        cip.created_at)
                ORDER BY clc.count_at DESC, clc.created_at DESC LIMIT 1),
              -- fallback: received ON/AFTER the group's last count → fresh stock
              -- (full amount); strictly earlier uncounted lots stay 0 (assumed
              -- captured by that comprehensive count).
              CASE WHEN COALESCE(
                     (SELECT sr.date_received FROM public.shipment_received sr WHERE sr.shipment_id = cip.shipment_id),
                     cip.created_at::date) >= v_last_count_at::date
                   THEN cip.amount ELSE 0 END
            )
           END
     WHERE cip.origin = p_origin_id AND cip.facility_id = p_facility_id
       AND cip.amount IS NOT NULL
       AND (cip.shipment_id IS NULL
          OR EXISTS (SELECT 1 FROM public.shipment_received sr
                      WHERE sr.shipment_id = cip.shipment_id
                        AND sr.date_received IS NOT NULL
                        AND COALESCE(sr.voided, false) = false));

    DELETE FROM public.roast_log_lot_consumption rlc
     USING public.coffee_inventory_purchased cip
     WHERE rlc.origin_purchase_id = cip.origin_purchase_id
       AND cip.origin = p_origin_id AND cip.facility_id = p_facility_id;

    FOR v_roast IN
        SELECT rl.roast_log_id, rl.charge_weight_lbs, rl.coffee_source_id,
               rl.recipe_id, rl.origin_id, rl.roast_date, rl.created_at,
               rl.borrow_origin_purchase_id, rr.roast_type,
               COALESCE(rl.roast_date_utc, (rl.roast_date AT TIME ZONE v_tz)) AS roast_utc
          FROM public.roast_log rl
          LEFT JOIN public.roast_recipes rr ON rr.recipe_id = rl.recipe_id
         WHERE rl.facility_id = p_facility_id
           AND rl."charged?" = true
           AND COALESCE(rl.charge_weight_lbs, 0) > 0
           AND (rl.external_roast_id IS NOT NULL
                OR rl.roast_date >= (rl.created_at::date - interval '1 day'))
           AND (v_last_count_at IS NULL
                OR COALESCE(rl.roast_date_utc, (rl.roast_date AT TIME ZONE v_tz)) > v_last_count_at)
           AND (
              (rl.borrow_origin_purchase_id IS NULL AND (
                  (rr.roast_type = 'Pre-Blend'
                     AND EXISTS (SELECT 1 FROM public.recipe_components rc
                                  WHERE rc.recipe_id = rl.recipe_id
                                    AND rc.coffee_item = p_origin_id
                                    AND COALESCE(rc.percentage, 0) > 0))
                  OR ((rr.roast_type IS NULL OR rr.roast_type <> 'Pre-Blend')
                        AND rl.origin_id = p_origin_id)))
              OR
              (rl.borrow_origin_purchase_id IS NOT NULL
                 AND EXISTS (SELECT 1 FROM public.coffee_inventory_purchased b
                              WHERE b.origin_purchase_id = rl.borrow_origin_purchase_id
                                AND b.origin = p_origin_id))
           )
         ORDER BY COALESCE(rl.roast_date_utc, (rl.roast_date AT TIME ZONE v_tz)) ASC, rl.created_at ASC
    LOOP
        v_force := NULL;
        IF v_roast.borrow_origin_purchase_id IS NOT NULL THEN
            v_needed := v_roast.charge_weight_lbs;
            v_force  := v_roast.borrow_origin_purchase_id;
            v_pref   := NULL;
        ELSIF v_roast.roast_type = 'Pre-Blend' THEN
            SELECT v_roast.charge_weight_lbs * COALESCE(rc.percentage, 0)
              INTO v_needed
              FROM public.recipe_components rc
             WHERE rc.recipe_id = v_roast.recipe_id AND rc.coffee_item = p_origin_id
             ORDER BY rc.percentage DESC LIMIT 1;
            v_pref := NULL;
            IF v_roast.coffee_source_id IS NOT NULL THEN
                SELECT CASE WHEN cs.origin_id = p_origin_id THEN v_roast.coffee_source_id ELSE NULL END
                  INTO v_pref FROM public.coffee_source cs WHERE cs.coffee_source_id = v_roast.coffee_source_id;
            END IF;
        ELSE
            v_needed := v_roast.charge_weight_lbs;
            v_pref := NULL;
            IF v_roast.coffee_source_id IS NOT NULL THEN
                SELECT CASE WHEN cs.origin_id = p_origin_id THEN v_roast.coffee_source_id ELSE NULL END
                  INTO v_pref FROM public.coffee_source cs WHERE cs.coffee_source_id = v_roast.coffee_source_id;
            END IF;
        END IF;
        IF COALESCE(v_needed, 0) <= 0 THEN CONTINUE; END IF;

        PERFORM public._deduct_origin_fifo(
            v_roast.roast_log_id, p_origin_id, p_facility_id, v_needed, v_pref, v_roast.roast_date, v_force);
    END LOOP;

    PERFORM public.recalculate_origin_total_stock(p_origin_id, p_facility_id);
END;
$function$;

-- Re-heal every origin holding a lot that was counted BEFORE its receipt (the
-- affected pattern) so their stock reflects the received amount now.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT DISTINCT cip.origin, cip.facility_id
      FROM public.coffee_inventory_purchased cip
      JOIN public.shipment_received sr ON sr.shipment_id = cip.shipment_id
     WHERE sr.date_received IS NOT NULL AND COALESCE(sr.voided, false) = false
       AND cip.origin IS NOT NULL AND cip.facility_id IS NOT NULL
       AND EXISTS (
         SELECT 1 FROM public.coffee_lot_count clc
          WHERE clc.origin_purchase_id = cip.origin_purchase_id
            AND clc.count_at < sr.date_received::timestamptz)
  LOOP
    PERFORM public.recompute_origin_lot_consumption(r.origin, r.facility_id);
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';
