-- ============================================================================
-- Timestamp-based count anchor (Cropster/Artisan standard: UTC instants)
-- ============================================================================
-- Counts anchored on a DATE: a roast on the same day as the count — even one
-- BEFORE the count was entered — read as "after the count" and got deducted,
-- double-counting the morning's roasting if you counted mid-shift.
--
-- Fix: anchor on the exact UTC moment. roast_log already stores roast_date_utc
-- (a true UTC instant); coffee_lot_count gets a count_at timestamptz. The replay
-- deducts only roasts whose UTC time is strictly after the latest count moment,
-- so you can count at 2pm, keep roasting at 3pm, and only the 3pm+ roasts come
-- off the count. (roast_date stays facility-local for display; older roasts with
-- a null roast_date_utc fall back to roast_date converted via the facility tz.)
-- ============================================================================

ALTER TABLE public.coffee_lot_count
  ADD COLUMN IF NOT EXISTS count_at timestamptz NOT NULL DEFAULT now();

-- Backfill: ADD COLUMN DEFAULT now() stamped existing rows with migration time;
-- reset each to when its count row was actually written (created_at).
UPDATE public.coffee_lot_count
   SET count_at = COALESCE(created_at, (count_date::timestamp AT TIME ZONE 'UTC'));

CREATE INDEX IF NOT EXISTS idx_coffee_lot_count_at ON public.coffee_lot_count(origin_purchase_id, count_at);

CREATE OR REPLACE FUNCTION public.recompute_origin_lot_consumption(
    p_origin_id text,
    p_facility_id text
) RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_roast record;
    v_needed numeric;
    v_pref text;
    v_last_count_at timestamptz;
    v_tz text;
BEGIN
    IF p_origin_id IS NULL OR p_facility_id IS NULL THEN RETURN; END IF;

    SELECT COALESCE(NULLIF(time_zone, ''), 'UTC') INTO v_tz
      FROM public.facilities WHERE facility_id = p_facility_id;
    v_tz := COALESCE(v_tz, 'UTC');

    -- Latest count MOMENT (UTC) for this origin.
    SELECT MAX(clc.count_at) INTO v_last_count_at
      FROM public.coffee_lot_count clc
      JOIN public.coffee_inventory_purchased cip2 ON cip2.origin_purchase_id = clc.origin_purchase_id
     WHERE cip2.origin = p_origin_id AND cip2.facility_id = p_facility_id;

    -- 2a. Unavailable lots (un-received / voided shipment) → NULL.
    UPDATE public.coffee_inventory_purchased cip
       SET remaining_lbs = NULL
     WHERE cip.origin = p_origin_id AND cip.facility_id = p_facility_id
       AND cip.shipment_id IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM public.shipment_received sr
          WHERE sr.shipment_id = cip.shipment_id
            AND sr.date_received IS NOT NULL
            AND COALESCE(sr.voided, false) = false);

    -- 2b. Baseline: counted value at the latest count moment; lots received
    --     after the count → full amount; uncounted-at-count → 0; no count → receipts.
    UPDATE public.coffee_inventory_purchased cip
       SET remaining_lbs = CASE
            WHEN v_last_count_at IS NULL THEN cip.amount
            ELSE COALESCE(
              (SELECT clc.counted_remaining_lbs
                 FROM public.coffee_lot_count clc
                WHERE clc.origin_purchase_id = cip.origin_purchase_id
                  AND clc.count_at = v_last_count_at
                ORDER BY clc.created_at DESC LIMIT 1),
              CASE WHEN COALESCE(
                     (SELECT sr.date_received FROM public.shipment_received sr WHERE sr.shipment_id = cip.shipment_id),
                     cip.created_at::date) > v_last_count_at::date
                   THEN cip.amount ELSE 0 END
            )
           END
     WHERE cip.origin = p_origin_id AND cip.facility_id = p_facility_id
       AND cip.amount IS NOT NULL
       AND (
          cip.shipment_id IS NULL
          OR EXISTS (
            SELECT 1 FROM public.shipment_received sr
             WHERE sr.shipment_id = cip.shipment_id
               AND sr.date_received IS NOT NULL
               AND COALESCE(sr.voided, false) = false));

    -- 2c. Clear the ledger for this origin's lots.
    DELETE FROM public.roast_log_lot_consumption rlc
     USING public.coffee_inventory_purchased cip
     WHERE rlc.origin_purchase_id = cip.origin_purchase_id
       AND cip.origin = p_origin_id AND cip.facility_id = p_facility_id;

    -- 2d. Replay charged, non-import roasts whose UTC time is strictly after
    --     the latest count moment.
    FOR v_roast IN
        SELECT rl.roast_log_id, rl.charge_weight_lbs, rl.coffee_source_id,
               rl.recipe_id, rl.origin_id, rl.roast_date, rl.created_at,
               rr.roast_type,
               COALESCE(rl.roast_date_utc, (rl.roast_date AT TIME ZONE v_tz)) AS roast_utc
          FROM public.roast_log rl
          LEFT JOIN public.roast_recipes rr ON rr.recipe_id = rl.recipe_id
         WHERE rl.facility_id = p_facility_id
           AND rl."charged?" = true
           AND COALESCE(rl.charge_weight_lbs, 0) > 0
           AND rl.external_roast_id IS NULL
           AND rl.roast_date >= (rl.created_at::date - interval '1 day')
           AND (v_last_count_at IS NULL
                OR COALESCE(rl.roast_date_utc, (rl.roast_date AT TIME ZONE v_tz)) > v_last_count_at)
           AND (
              (rr.roast_type = 'Pre-Blend'
                 AND EXISTS (SELECT 1 FROM public.recipe_components rc
                              WHERE rc.recipe_id = rl.recipe_id
                                AND rc.coffee_item = p_origin_id
                                AND COALESCE(rc.percentage, 0) > 0))
              OR
              ((rr.roast_type IS NULL OR rr.roast_type <> 'Pre-Blend')
                 AND rl.origin_id = p_origin_id)
           )
         ORDER BY COALESCE(rl.roast_date_utc, (rl.roast_date AT TIME ZONE v_tz)) ASC, rl.created_at ASC
    LOOP
        IF v_roast.roast_type = 'Pre-Blend' THEN
            SELECT v_roast.charge_weight_lbs * COALESCE(rc.percentage, 0)
              INTO v_needed
              FROM public.recipe_components rc
             WHERE rc.recipe_id = v_roast.recipe_id AND rc.coffee_item = p_origin_id
             ORDER BY rc.percentage DESC LIMIT 1;
        ELSE
            v_needed := v_roast.charge_weight_lbs;
        END IF;
        IF COALESCE(v_needed, 0) <= 0 THEN CONTINUE; END IF;

        v_pref := NULL;
        IF v_roast.coffee_source_id IS NOT NULL THEN
            SELECT CASE WHEN cs.origin_id = p_origin_id THEN v_roast.coffee_source_id ELSE NULL END
              INTO v_pref FROM public.coffee_source cs
             WHERE cs.coffee_source_id = v_roast.coffee_source_id;
        END IF;

        PERFORM public._deduct_origin_fifo(
            v_roast.roast_log_id, p_origin_id, p_facility_id, v_needed, v_pref, v_roast.roast_date);
    END LOOP;

    PERFORM public.recalculate_origin_total_stock(p_origin_id, p_facility_id);
END;
$$;
