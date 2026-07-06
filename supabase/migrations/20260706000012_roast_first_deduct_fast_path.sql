-- Fast path for FIRST-TIME metadata on a charged roast (fixes slow impromptu save).
--
-- An impromptu roast is INSERTed at charge with charged?=true but NULL
-- recipe/origin/charge (nothing selected). Its metadata is filled in later — via
-- the mid-roast Edit or at DROP. Writing recipe/origin/charge on an
-- already-charged roast trips roast_log_lot_recompute's "retroactive edit"
-- branch, which FULL-FIFO-REPLAYS the whole origin (~15-25s). Worse: an
-- impromptu roast with NO charge weight still triggers the full replay for a
-- roast that consumes nothing.
--
-- But a charged roast that has NO consumption rows yet has never been deducted —
-- filling its metadata is a FIRST deduct, identical to charging it with that
-- metadata, which the charge path already handles with the fast incremental
-- deduct_one_roast(). So: in the retroactive branch, if the roast has no
-- existing consumption, deduct incrementally instead of replaying history.
-- (deduct_one_roast is a no-op when charge_weight_lbs<=0, so a no-charge-weight
-- impromptu save becomes instant.)
--
-- Only change vs 20260706000011: the two-line fast-path guard at the top of the
-- retroactive branch. Defer guard + all other branches unchanged.
CREATE OR REPLACE FUNCTION public.roast_log_lot_recompute()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    o text;
    v_lender text;
BEGIN
    IF current_setting('app.defer_lot_recompute', true) = 'true' THEN RETURN NULL; END IF;

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
        -- FAST PATH: a still-charged roast with NO consumption yet has never been
        -- deducted (e.g. an impromptu roast whose recipe/origin/charge were NULL
        -- at charge and are filled in now). This is a FIRST deduct, not a
        -- re-attribution — do it incrementally instead of replaying the whole
        -- origin's history. deduct_one_roast no-ops when charge_weight_lbs<=0.
        IF COALESCE(NEW."charged?", false) = true
           AND NOT EXISTS (SELECT 1 FROM public.roast_log_lot_consumption
                            WHERE roast_log_id = NEW.roast_log_id) THEN
            PERFORM public.deduct_one_roast(NEW.roast_log_id);
            RETURN NULL;
        END IF;

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

NOTIFY pgrst, 'reload schema';
