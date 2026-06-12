-- ============================================================================
-- Imported roasts drive inventory (migration-to-current-state)
-- ============================================================================
-- A migrating customer should land "up to date": their imported roast history
-- must deduct green from the baseline count, exactly like live roasting.
--
-- Two things blocked that:
--   1. trg_stamp_roasted_weight is built for LIVE roasting: it derives
--      charge_weight_lbs from NEW.charge_weight (a UUID/option) and stamps
--      roast_date := NOW() ("never trust the app"). An importer that sets
--      charge_weight_lbs + roast_date_utc directly got both clobbered —
--      charge_weight_lbs → NULL (so roasted_weight → 0) and every roast
--      re-dated to today.
--   2. The lot-consumption engine (recompute_origin_lot_consumption /
--      deduct_one_roast) skips rows where external_roast_id IS NOT NULL and
--      rows whose roast_date is far before created_at (the import guard) —
--      so imported roasts never deducted from lots.
--
-- Fix: make BOTH paths import-aware, keyed on external_roast_id (an imported
-- roast carries the source system's stable id). Live roasting (external_roast_id
-- IS NULL) is byte-for-byte unchanged.
-- ============================================================================

-- ─── 1. Import-aware stamp trigger ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.trg_stamp_roasted_weight()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_retention     numeric;
    v_charge_weight numeric;
    v_tz            text;
BEGIN
    -- Resolve charge_weight UUID/option → numeric (or a numeric string).
    SELECT cwo.charge_weight INTO v_charge_weight
    FROM public.charge_weight_options cwo
    WHERE cwo.id = NEW.charge_weight LIMIT 1;

    IF v_charge_weight IS NULL AND NEW.charge_weight ~ '^[0-9]+(\.[0-9]+)?$' THEN
        v_charge_weight := NEW.charge_weight::numeric;
    END IF;

    -- Imported roast: the source system already knows the green weight. When
    -- charge_weight didn't resolve, trust the charge_weight_lbs the importer set.
    IF v_charge_weight IS NULL AND NEW.external_roast_id IS NOT NULL THEN
        v_charge_weight := NEW.charge_weight_lbs;
    END IF;

    NEW.charge_weight_lbs := v_charge_weight;

    -- Retention factor (3-tier).
    SELECT value_number INTO v_retention FROM public.company_parameters
    WHERE parameter_id = '1de271df' AND facility_id = NEW.facility_id LIMIT 1;
    IF v_retention IS NULL OR v_retention = 0 THEN
        SELECT amount INTO v_retention FROM public.standard_parameters WHERE parameters_id = '1de271df' LIMIT 1;
    END IF;
    IF v_retention IS NULL OR v_retention = 0 THEN v_retention := 0.82; END IF;

    -- roasted_weight: an imported roast carries the real drop weight — keep it.
    -- Otherwise compute from retention (live-roasting behaviour, unchanged).
    IF NEW.external_roast_id IS NOT NULL AND COALESCE(NEW.roasted_weight, 0) > 0 THEN
        NULL;  -- trust importer's roasted_weight
    ELSE
        NEW.roasted_weight := ROUND(COALESCE(v_charge_weight, 0) * v_retention, 2);
    END IF;

    -- Facility timezone.
    SELECT COALESCE(NULLIF(time_zone, ''), 'UTC') INTO v_tz
    FROM public.facilities WHERE facility_id = NEW.facility_id;
    v_tz := COALESCE(v_tz, 'UTC');

    IF NEW.external_roast_id IS NOT NULL THEN
        -- Imported/external roast carries an authoritative timestamp. Trust
        -- roast_date_utc, derive the facility-local roast_date — never NOW().
        IF NEW."charged?" = false THEN
            NEW.roast_date     := NULL;
            NEW.roast_date_utc := NULL;
        ELSIF NEW.roast_date_utc IS NOT NULL THEN
            NEW.roast_date := (NEW.roast_date_utc AT TIME ZONE v_tz);
        ELSIF NEW.roast_date IS NOT NULL THEN
            NEW.roast_date_utc := NEW.roast_date AT TIME ZONE v_tz;
        END IF;
    ELSE
        -- Live roasting (unchanged): stamp roast_date as facility-local time;
        -- never trust the value sent by the app.
        IF NEW."charged?" = true AND (TG_OP = 'INSERT' OR OLD."charged?" IS DISTINCT FROM true) THEN
            NEW.roast_date     := (NOW() AT TIME ZONE v_tz)::timestamp without time zone;
            NEW.roast_date_utc := NOW();
        ELSIF NEW."charged?" = false THEN
            NEW.roast_date     := NULL;
            NEW.roast_date_utc := NULL;
        ELSIF NEW.roast_date IS NOT NULL THEN
            NEW.roast_date_utc := NEW.roast_date AT TIME ZONE v_tz;
        END IF;
    END IF;

    RETURN NEW;
END;
$function$;

-- ─── 2. Incremental deduct includes imported roasts ─────────────────────────
CREATE OR REPLACE FUNCTION public.deduct_one_roast(p_roast_log_id text)
RETURNS void
LANGUAGE plpgsql
AS $function$
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

    IF rl.charged IS NOT TRUE OR COALESCE(rl.charge_weight_lbs, 0) <= 0 THEN RETURN; END IF;
    -- Import guard applies to NATIVE roasts only: a native roast dated far
    -- before its created_at is a data slip and is skipped. Imported roasts
    -- (external_roast_id set) carry authoritative historical dates and DO deduct.
    IF rl.external_roast_id IS NULL
       AND rl.roast_date < (rl.created_at::date - interval '1 day') THEN
        RETURN;
    END IF;
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
$function$;

-- ─── 3. Full replay includes imported roasts ────────────────────────────────
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

    DELETE FROM public.roast_log_lot_consumption rlc
     USING public.coffee_inventory_purchased cip
     WHERE rlc.origin_purchase_id = cip.origin_purchase_id
       AND cip.origin = p_origin_id AND cip.facility_id = p_facility_id;

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
           -- Import guard: native roasts must be dated ~now; imported roasts
           -- (external_roast_id set) carry real historical dates and replay.
           AND (rl.external_roast_id IS NOT NULL
                OR rl.roast_date >= (rl.created_at::date - interval '1 day'))
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
