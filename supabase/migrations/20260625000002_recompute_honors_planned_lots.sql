-- Teach the lot-consumption replay + its dispatch trigger to honor per-component
-- planned_lots, so editing a BLEND roast's per-component sources (Edit Roast
-- modal / AddRoast picker) retroactively re-attributes each component's lots —
-- matching how single-origin already re-points via coffee_source_id.
--
-- BACKGROUND: recompute_origin_lot_consumption is the retroactive replay. For a
-- pre-blend it could only steer the ONE component whose origin matched the single
-- roast_log.coffee_source_id; every other component fell to the group's active
-- source / FIFO. The per-component roast_log.planned_lots jsonb map
-- ({origin_id: coffee_source_id}) is written at roast time but was never read by
-- the replay, and planned_lots wasn't a trigger-watched column — so editing it
-- did nothing. This migration:
--   1. recompute reads planned_lots->>origin as the per-component preferred
--      source (takes precedence over coffee_source_id for pre-blend; a fallback
--      when coffee_source_id is null for single-origin).
--   2. the dispatch trigger watches planned_lots and treats a planned_lots-only
--      edit as a retroactive change that fires the replay.
-- A same-group planned source steers its lots first (via _deduct_origin_fifo's
-- preferred-source ordering within the origin); a borrow planned source has no
-- lots in the origin bucket so it harmlessly falls through to FIFO — cross-group
-- borrow still rides borrow_origin_purchase_id, semantics unchanged.
-- Rebased on 20260624000003 (recompute) + 20260623000005 (dispatch/trigger).

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
              -- this lot's OWN latest count
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
               rl.borrow_origin_purchase_id, rl.planned_lots, rr.roast_type,
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
            -- Per-component planned source (Edit Roast / AddRoast picker) wins:
            -- it's how a blend's individual components get re-attributed.
            v_pref := NULLIF(v_roast.planned_lots ->> p_origin_id, '');
            -- Fall back to the single coffee_source_id (steers only the matching component).
            IF v_pref IS NULL AND v_roast.coffee_source_id IS NOT NULL THEN
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
            -- Single-origin fallback: honor planned_lots[origin] only when there
            -- is no coffee_source_id pick (coffee_source_id stays authoritative).
            IF v_pref IS NULL THEN
                v_pref := NULLIF(v_roast.planned_lots ->> p_origin_id, '');
            END IF;
        END IF;
        IF COALESCE(v_needed, 0) <= 0 THEN CONTINUE; END IF;

        PERFORM public._deduct_origin_fifo(
            v_roast.roast_log_id, p_origin_id, p_facility_id, v_needed, v_pref, v_roast.roast_date, v_force);
    END LOOP;

    PERFORM public.recalculate_origin_total_stock(p_origin_id, p_facility_id);
END;
$function$;

-- Dispatch trigger function: add a planned_lots-only edit to the retroactive
-- replay test (otherwise the trigger watch-list change below would fire but the
-- function would no-op on a planned_lots-only update). Rebased on 20260623000005.
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
              NEW.planned_lots      IS DISTINCT FROM OLD.planned_lots OR
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

-- Watch planned_lots so a per-component source edit actually fires the replay.
DROP TRIGGER IF EXISTS trg_lot_consumption_recompute ON public.roast_log;
CREATE TRIGGER trg_lot_consumption_recompute
  AFTER INSERT OR DELETE OR UPDATE OF "charged?", charge_weight_lbs, charge_weight,
        origin_id, recipe_id, coffee_source_id, borrow_origin_purchase_id, planned_lots
  ON public.roast_log FOR EACH ROW EXECUTE FUNCTION roast_log_lot_recompute();
