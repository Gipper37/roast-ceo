-- Borrow, part 2/2 — make the consumption replay (recompute) borrow-aware.
--
-- Key insight: a single-origin/post-blend borrow's consumption is OWNED BY THE
-- BORROWED LOT'S HOME group, not the recipe origin. So recompute(home) naturally
-- rebuilds it, and recompute(recipe-origin) must ignore it. That's a targeted
-- filter change to the candidate-roast set — the re-seed + DELETE + the entire
-- non-borrow path are byte-for-byte unchanged, so normal roasts/origins are not
-- affected at all. See memory/project_lot_home_inventory.md.

CREATE OR REPLACE FUNCTION public.recompute_origin_lot_consumption(p_origin_id text, p_facility_id text)
RETURNS void LANGUAGE plpgsql AS $function$
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

    -- ── re-seed (UNCHANGED) ──
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
       AND (cip.shipment_id IS NULL
          OR EXISTS (SELECT 1 FROM public.shipment_received sr
                      WHERE sr.shipment_id = cip.shipment_id
                        AND sr.date_received IS NOT NULL
                        AND COALESCE(sr.voided, false) = false));

    -- ── clear this group's lots' ledger (UNCHANGED — a borrow row lives on the
    --    borrowed lot, which is this group's lot when recompute runs for the
    --    lender home, so it is correctly cleared here and rebuilt below) ──
    DELETE FROM public.roast_log_lot_consumption rlc
     USING public.coffee_inventory_purchased cip
     WHERE rlc.origin_purchase_id = cip.origin_purchase_id
       AND cip.origin = p_origin_id AND cip.facility_id = p_facility_id;

    -- ── re-derive: normal roasts that cite this group (NON-borrow), PLUS any
    --    roast that BORROWED a lot homed in this group. A borrow roast is owned
    --    here (lender home), never by its recipe origin. ──
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
              -- normal, non-borrow roasts citing this group
              (rl.borrow_origin_purchase_id IS NULL AND (
                  (rr.roast_type = 'Pre-Blend'
                     AND EXISTS (SELECT 1 FROM public.recipe_components rc
                                  WHERE rc.recipe_id = rl.recipe_id
                                    AND rc.coffee_item = p_origin_id
                                    AND COALESCE(rc.percentage, 0) > 0))
                  OR ((rr.roast_type IS NULL OR rr.roast_type <> 'Pre-Blend')
                        AND rl.origin_id = p_origin_id)))
              OR
              -- borrow roasts whose borrowed lot is homed in this group
              (rl.borrow_origin_purchase_id IS NOT NULL
                 AND EXISTS (SELECT 1 FROM public.coffee_inventory_purchased b
                              WHERE b.origin_purchase_id = rl.borrow_origin_purchase_id
                                AND b.origin = p_origin_id))
           )
         ORDER BY COALESCE(rl.roast_date_utc, (rl.roast_date AT TIME ZONE v_tz)) ASC, rl.created_at ASC
    LOOP
        v_force := NULL;
        IF v_roast.borrow_origin_purchase_id IS NOT NULL THEN
            -- borrow: full charge consumed from the forced (borrowed) lot
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

-- ── Dispatch trigger: on edit/delete/uncharge of a roast, also replay the BORROW
--    LENDER's home group (its lots carry the borrow consumption). Fresh-charge
--    still routes through deduct_one_roast, which already handles the borrow.
--    Also start watching borrow_origin_purchase_id so re-pointing a borrow fires. ──
CREATE OR REPLACE FUNCTION public.roast_log_lot_recompute()
RETURNS trigger LANGUAGE plpgsql AS $function$
DECLARE
    o text;
    v_lender text;
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW."charged?" = true THEN
            PERFORM public.deduct_one_roast(NEW.roast_log_id);
        END IF;
        RETURN NULL;
    END IF;

    IF TG_OP = 'DELETE' THEN
        IF OLD."charged?" = true AND OLD.facility_id IS NOT NULL THEN
            FOREACH o IN ARRAY public._roast_affected_origins(OLD.recipe_id, OLD.origin_id) LOOP
                PERFORM public.recompute_origin_lot_consumption(o, OLD.facility_id);
            END LOOP;
            IF OLD.borrow_origin_purchase_id IS NOT NULL THEN
                SELECT origin INTO v_lender FROM public.coffee_inventory_purchased
                 WHERE origin_purchase_id = OLD.borrow_origin_purchase_id;
                IF v_lender IS NOT NULL THEN
                    PERFORM public.recompute_origin_lot_consumption(v_lender, OLD.facility_id);
                END IF;
            END IF;
        END IF;
        RETURN NULL;
    END IF;

    -- UPDATE: fresh charge (false→true) → fast incremental deduct.
    IF COALESCE(OLD."charged?", false) = false AND NEW."charged?" = true THEN
        PERFORM public.deduct_one_roast(NEW.roast_log_id);
        RETURN NULL;
    END IF;

    -- Retroactive change to a charged roast (or un-charge) → full replay.
    IF (COALESCE(OLD."charged?", false) = true AND COALESCE(NEW."charged?", false) = false)
       OR (NEW."charged?" = true AND (
              NEW.charge_weight_lbs IS DISTINCT FROM OLD.charge_weight_lbs OR
              NEW.charge_weight     IS DISTINCT FROM OLD.charge_weight OR
              NEW.origin_id         IS DISTINCT FROM OLD.origin_id OR
              NEW.recipe_id         IS DISTINCT FROM OLD.recipe_id OR
              NEW.coffee_source_id  IS DISTINCT FROM OLD.coffee_source_id OR
              NEW.borrow_origin_purchase_id IS DISTINCT FROM OLD.borrow_origin_purchase_id))
    THEN
        IF NEW.facility_id IS NOT NULL THEN
            FOREACH o IN ARRAY public._roast_affected_origins(NEW.recipe_id, NEW.origin_id) LOOP
                PERFORM public.recompute_origin_lot_consumption(o, NEW.facility_id);
            END LOOP;
            IF NEW.borrow_origin_purchase_id IS NOT NULL THEN
                SELECT origin INTO v_lender FROM public.coffee_inventory_purchased
                 WHERE origin_purchase_id = NEW.borrow_origin_purchase_id;
                IF v_lender IS NOT NULL THEN
                    PERFORM public.recompute_origin_lot_consumption(v_lender, NEW.facility_id);
                END IF;
            END IF;
        END IF;
        IF OLD.facility_id IS NOT NULL THEN
            FOREACH o IN ARRAY public._roast_affected_origins(OLD.recipe_id, OLD.origin_id) LOOP
                PERFORM public.recompute_origin_lot_consumption(o, OLD.facility_id);
            END LOOP;
            -- OLD lender (covers re-pointing the borrow to a different lot/group)
            IF OLD.borrow_origin_purchase_id IS NOT NULL
               AND OLD.borrow_origin_purchase_id IS DISTINCT FROM NEW.borrow_origin_purchase_id THEN
                SELECT origin INTO v_lender FROM public.coffee_inventory_purchased
                 WHERE origin_purchase_id = OLD.borrow_origin_purchase_id;
                IF v_lender IS NOT NULL THEN
                    PERFORM public.recompute_origin_lot_consumption(v_lender, OLD.facility_id);
                END IF;
            END IF;
        END IF;
    END IF;
    RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS trg_lot_consumption_recompute ON public.roast_log;
CREATE TRIGGER trg_lot_consumption_recompute
  AFTER INSERT OR DELETE OR UPDATE OF "charged?", charge_weight_lbs, charge_weight,
        origin_id, recipe_id, coffee_source_id, borrow_origin_purchase_id
  ON public.roast_log FOR EACH ROW EXECUTE FUNCTION roast_log_lot_recompute();
