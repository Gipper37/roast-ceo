-- Migration 00217: Fix roast_date timezone stamping
--
-- Problem: chargeToggle actions sent new Date().toISOString() (UTC) for roast_date,
-- which is a timestamp WITHOUT TIME ZONE column that stores local Hawaii time.
-- The trigger then computed roast_date_utc = stored_utc_as_if_local AT TIME ZONE 'Pacific/Honolulu',
-- making both columns 10 hours wrong.
--
-- Fix: update trg_stamp_roasted_weight to stamp roast_date itself from NOW() AT TIME ZONE v_tz
-- when a row is being charged, so the action never needs to compute local time.
--
-- When charged? becomes true  → set roast_date = NOW() AT TIME ZONE v_tz, roast_date_utc = NOW()
-- When charged? becomes false → clear both date fields
-- Otherwise (other field edits on charged row) → keep roast_date, recompute roast_date_utc

CREATE OR REPLACE FUNCTION public.trg_stamp_roasted_weight()
RETURNS trigger LANGUAGE plpgsql AS $function$
DECLARE
    v_retention     numeric;
    v_charge_weight numeric;
    v_tz            text;
BEGIN
    -- Resolve charge_weight UUID → numeric
    SELECT cwo.charge_weight INTO v_charge_weight
    FROM public.charge_weight_options cwo
    WHERE cwo.id = NEW.charge_weight LIMIT 1;

    IF v_charge_weight IS NULL AND NEW.charge_weight ~ '^[0-9]+(\.[0-9]+)?$' THEN
        v_charge_weight := NEW.charge_weight::numeric;
    END IF;

    -- Retention factor (3-tier)
    SELECT value_number INTO v_retention FROM company_parameters
    WHERE parameter_id = '1de271df' AND facility_id = NEW.facility_id LIMIT 1;
    IF v_retention IS NULL OR v_retention = 0 THEN
        SELECT amount INTO v_retention FROM standard_parameters WHERE parameters_id = '1de271df' LIMIT 1;
    END IF;
    IF v_retention IS NULL OR v_retention = 0 THEN v_retention := 0.82; END IF;

    NEW.roasted_weight := ROUND(COALESCE(v_charge_weight, 0) * v_retention, 2);

    -- Facility timezone
    SELECT COALESCE(NULLIF(time_zone, ''), 'UTC') INTO v_tz
    FROM public.facilities WHERE facility_id = NEW.facility_id;

    -- Stamp roast_date as facility-local time; never trust value sent by app
    IF NEW."charged?" = true AND (TG_OP = 'INSERT' OR OLD."charged?" IS DISTINCT FROM true) THEN
        -- Row is being charged: stamp current local time from server
        NEW.roast_date     := (NOW() AT TIME ZONE v_tz)::timestamp without time zone;
        NEW.roast_date_utc := NOW();
    ELSIF NEW."charged?" = false THEN
        -- Row is being uncharged: clear both date fields
        NEW.roast_date     := NULL;
        NEW.roast_date_utc := NULL;
    ELSIF NEW.roast_date IS NOT NULL THEN
        -- Charged row, other field edit: keep roast_date, recompute utc
        NEW.roast_date_utc := NEW.roast_date AT TIME ZONE v_tz;
    END IF;

    RETURN NEW;
END;
$function$;
