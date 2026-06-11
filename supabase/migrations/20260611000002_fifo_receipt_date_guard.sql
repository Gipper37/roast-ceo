-- ============================================================================
-- FIFO receipt-date guard: a roast can only consume lots received by then
-- ============================================================================
-- Bug: the replay's FIFO prefers the active source's lots first. When the
-- active source is the most-recently-received lot, EVERY historical roast for
-- that origin got attributed to it, draining the newest (e.g. 12,920 lb) lot to
-- zero before older lots were touched — and flagging it "out" on the first new
-- roast.
--
-- A roast physically cannot consume a lot that hadn't been received yet. So the
-- deductor now only considers lots whose receipt date is on/before the roast
-- date (quick-add lots use created_at). Historical roasts fall to the lots that
-- existed then; a freshly-received lot is only drawn down by roasts after it
-- arrived.
-- ============================================================================

CREATE OR REPLACE FUNCTION public._deduct_origin_fifo(
    p_roast_log_id text,
    p_origin_id text,
    p_facility_id text,
    p_lbs numeric,
    p_preferred_source text,
    p_roast_date timestamp without time zone
) RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_lot record;
    v_alloc_total numeric := 0;
    v_lbs_alloc numeric;
BEGIN
    IF COALESCE(p_lbs, 0) <= 0 THEN RETURN; END IF;
    FOR v_lot IN
        SELECT cip.origin_purchase_id, cip.remaining_lbs
          FROM public.coffee_inventory_purchased cip
          LEFT JOIN public.shipment_received sr ON sr.shipment_id = cip.shipment_id
         WHERE cip.origin = p_origin_id
           AND cip.facility_id = p_facility_id
           AND COALESCE(cip.remaining_lbs, 0) > 0
           -- Only lots that existed at roast time. p_roast_date NULL → no
           -- constraint (defensive; recompute always passes it).
           AND (p_roast_date IS NULL
                OR COALESCE(sr.date_received, cip.created_at::date) <= p_roast_date::date)
         ORDER BY
           CASE WHEN p_preferred_source IS NOT NULL
                     AND cip.coffee_source_id = p_preferred_source THEN 0 ELSE 1 END,
           COALESCE(sr.date_received, cip.created_at::date) ASC,
           cip.created_at ASC
    LOOP
        IF v_alloc_total >= p_lbs THEN EXIT; END IF;
        v_lbs_alloc := LEAST(v_lot.remaining_lbs, p_lbs - v_alloc_total);
        IF v_lbs_alloc <= 0 THEN CONTINUE; END IF;
        UPDATE public.coffee_inventory_purchased
           SET remaining_lbs = remaining_lbs - v_lbs_alloc
         WHERE origin_purchase_id = v_lot.origin_purchase_id;
        INSERT INTO public.roast_log_lot_consumption (roast_log_id, origin_purchase_id, lbs_consumed)
          VALUES (p_roast_log_id, v_lot.origin_purchase_id, v_lbs_alloc);
        v_alloc_total := v_alloc_total + v_lbs_alloc;
    END LOOP;
END;
$$;

-- Recompute now passes each roast's date to the deductor. (Body identical to
-- 20260610000007 except the _deduct_origin_fifo call carries v_roast.roast_date.)
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
    v_last_count date;
BEGIN
    IF p_origin_id IS NULL OR p_facility_id IS NULL THEN RETURN; END IF;

    SELECT MAX(clc.count_date) INTO v_last_count
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
            WHEN v_last_count IS NULL THEN cip.amount
            ELSE COALESCE(
              (SELECT clc.counted_remaining_lbs
                 FROM public.coffee_lot_count clc
                WHERE clc.origin_purchase_id = cip.origin_purchase_id
                  AND clc.count_date = v_last_count
                ORDER BY clc.created_at DESC LIMIT 1),
              CASE WHEN COALESCE(
                     (SELECT sr.date_received FROM public.shipment_received sr WHERE sr.shipment_id = cip.shipment_id),
                     cip.created_at::date) > v_last_count
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

    DELETE FROM public.roast_log_lot_consumption rlc
     USING public.coffee_inventory_purchased cip
     WHERE rlc.origin_purchase_id = cip.origin_purchase_id
       AND cip.origin = p_origin_id AND cip.facility_id = p_facility_id;

    FOR v_roast IN
        SELECT rl.roast_log_id, rl.charge_weight_lbs, rl.coffee_source_id,
               rl.recipe_id, rl.origin_id, rl.roast_date, rl.created_at,
               rr.roast_type
          FROM public.roast_log rl
          LEFT JOIN public.roast_recipes rr ON rr.recipe_id = rl.recipe_id
         WHERE rl.facility_id = p_facility_id
           AND rl."charged?" = true
           AND COALESCE(rl.charge_weight_lbs, 0) > 0
           AND rl.external_roast_id IS NULL
           AND rl.roast_date >= (rl.created_at::date - interval '1 day')
           AND (v_last_count IS NULL OR rl.roast_date > v_last_count)
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
         ORDER BY rl.roast_date ASC, rl.created_at ASC
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

        -- Preference is the roast's OWN recorded source only (what it actually
        -- used). We do NOT fall back to the current active_coffee_source_id —
        -- that's a charge-time/UI pointer and using it here would retroactively
        -- attribute past roasts to a lot that was only just made active. A roast
        -- with no recorded source falls to plain oldest-first FIFO.
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
