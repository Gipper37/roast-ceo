-- ============================================================================
-- Incremental charge deduction (stop the per-charge full replay)
-- ============================================================================
-- Every roast_log mutation (charge, then the session-save that writes
-- coffee_source_id, etc.) fired a full O(roasts) recompute (~2s for a busy
-- origin), and they serialize on the origin's lot rows — so a day of roasting
-- backs up into minutes-long lag before a roast even shows as charged.
--
-- Fix: a roast is always charged "now" (it's the newest), so a fresh charge
-- just deducts THAT roast incrementally from current lot state (O(lots), ms).
-- A full replay only runs on genuinely retroactive changes — uncharge, delete,
-- or an edit to a charged roast's weight/origin/recipe/source.
-- ============================================================================

-- Deduct a single roast against the CURRENT lot state (no reset/replay).
-- Idempotent: skips if this roast already has consumption recorded.
CREATE OR REPLACE FUNCTION public.deduct_one_roast(p_roast_log_id text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    rl record;
    o text;
    v_needed numeric;
    v_pref text;
BEGIN
    SELECT rl2.roast_log_id, rl2.facility_id, rl2.charge_weight_lbs, rl2.coffee_source_id,
           rl2.recipe_id, rl2.origin_id, rl2.roast_date, rl2.created_at,
           rl2."charged?" AS charged, rl2.external_roast_id, rr.roast_type
      INTO rl
      FROM public.roast_log rl2
      LEFT JOIN public.roast_recipes rr ON rr.recipe_id = rl2.recipe_id
     WHERE rl2.roast_log_id = p_roast_log_id;
    IF NOT FOUND THEN RETURN; END IF;

    -- Same skip rules as the replay.
    IF rl.charged IS NOT TRUE OR COALESCE(rl.charge_weight_lbs, 0) <= 0 THEN RETURN; END IF;
    IF rl.external_roast_id IS NOT NULL THEN RETURN; END IF;
    IF rl.roast_date < (rl.created_at::date - interval '1 day') THEN RETURN; END IF;
    IF rl.facility_id IS NULL THEN RETURN; END IF;
    -- Idempotency: never double-deduct a roast.
    IF EXISTS (SELECT 1 FROM public.roast_log_lot_consumption WHERE roast_log_id = p_roast_log_id) THEN
        RETURN;
    END IF;

    FOREACH o IN ARRAY public._roast_affected_origins(rl.recipe_id, rl.origin_id) LOOP
        IF rl.roast_type = 'Pre-Blend' THEN
            SELECT rl.charge_weight_lbs * COALESCE(rc.percentage, 0) INTO v_needed
              FROM public.recipe_components rc
             WHERE rc.recipe_id = rl.recipe_id AND rc.coffee_item = o
             ORDER BY rc.percentage DESC LIMIT 1;
        ELSE
            v_needed := rl.charge_weight_lbs;
        END IF;
        IF COALESCE(v_needed, 0) <= 0 THEN CONTINUE; END IF;

        v_pref := NULL;
        IF rl.coffee_source_id IS NOT NULL THEN
            SELECT CASE WHEN cs.origin_id = o THEN rl.coffee_source_id ELSE NULL END
              INTO v_pref FROM public.coffee_source cs WHERE cs.coffee_source_id = rl.coffee_source_id;
        END IF;

        PERFORM public._deduct_origin_fifo(rl.roast_log_id, o, rl.facility_id, v_needed, v_pref, rl.roast_date);
        PERFORM public.recalculate_origin_total_stock(o, rl.facility_id);
    END LOOP;
END;
$$;

-- Smart trigger: incremental on fresh charge, full replay only on retroactive change.
CREATE OR REPLACE FUNCTION public.roast_log_lot_recompute()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    o text;
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
        END IF;
        RETURN NULL;
    END IF;

    -- UPDATE: fresh charge (false→true) → fast incremental deduct.
    IF COALESCE(OLD."charged?", false) = false AND NEW."charged?" = true THEN
        PERFORM public.deduct_one_roast(NEW.roast_log_id);
        RETURN NULL;
    END IF;

    -- Retroactive change to lot attribution → full replay of affected origins:
    --   * un-charge (true→false): restore stock
    --   * edit of a charged roast's weight / origin / recipe / source
    IF (COALESCE(OLD."charged?", false) = true AND COALESCE(NEW."charged?", false) = false)
       OR (NEW."charged?" = true AND (
              NEW.charge_weight_lbs IS DISTINCT FROM OLD.charge_weight_lbs OR
              NEW.charge_weight     IS DISTINCT FROM OLD.charge_weight OR
              NEW.origin_id         IS DISTINCT FROM OLD.origin_id OR
              NEW.recipe_id         IS DISTINCT FROM OLD.recipe_id OR
              NEW.coffee_source_id  IS DISTINCT FROM OLD.coffee_source_id))
    THEN
        IF NEW.facility_id IS NOT NULL THEN
            FOREACH o IN ARRAY public._roast_affected_origins(NEW.recipe_id, NEW.origin_id) LOOP
                PERFORM public.recompute_origin_lot_consumption(o, NEW.facility_id);
            END LOOP;
        END IF;
        IF OLD.facility_id IS NOT NULL AND OLD.facility_id IS DISTINCT FROM NEW.facility_id THEN
            FOREACH o IN ARRAY public._roast_affected_origins(OLD.recipe_id, OLD.origin_id) LOOP
                PERFORM public.recompute_origin_lot_consumption(o, OLD.facility_id);
            END LOOP;
        ELSIF OLD.facility_id IS NOT NULL THEN
            FOREACH o IN ARRAY public._roast_affected_origins(OLD.recipe_id, OLD.origin_id) LOOP
                PERFORM public.recompute_origin_lot_consumption(o, OLD.facility_id);
            END LOOP;
        END IF;
    END IF;
    RETURN NULL;
END;
$$;
