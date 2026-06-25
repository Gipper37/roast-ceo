-- Fix recompute_origin_lot_consumption re-seed: restore each lot from ITS OWN
-- latest physical count, not the group-wide MAX(count_at).
--
-- BUG: the re-seed matched `clc.count_at = v_last_count_at` where v_last_count_at
-- is MAX(count_at) across ALL the group's lots. Lots counted at a different
-- microsecond (e.g. a source-count writes one row per lot, microseconds apart)
-- returned NULL from the count lookup and fell through to the received-date
-- fallback → 0. So a recompute (fired by any roast edit / re-attribution / count
-- on the group) silently zeroed every lot except the one counted last.
-- MCR Organic (3 lots counted 03:21/03:24/03:25 = 760/304/304) collapsed to 304.
--
-- FIX: key each lot's count restore on that lot's own latest count
-- (ORDER BY count_at DESC). The never-counted fallback keeps the group anchor.
-- Strictly more correct: a lot all-counted-together is unchanged; a lot counted
-- earlier than a sibling now keeps its own count instead of being zeroed.
-- Affects ALL recompute callers (lot-count trigger, roast edit/delete, re-attribution).
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
              -- ── FIX: this lot's OWN latest count (was: AND clc.count_at = v_last_count_at) ──
              (SELECT clc.counted_remaining_lbs
                 FROM public.coffee_lot_count clc
                WHERE clc.origin_purchase_id = cip.origin_purchase_id
                ORDER BY clc.count_at DESC, clc.created_at DESC LIMIT 1),
              CASE WHEN COALESCE(
                     (SELECT sr.date_received FROM public.shipment_received sr WHERE sr.shipment_id = cip.shipment_id),
                     cip.created_at::date) > v_last_count_at::date
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
