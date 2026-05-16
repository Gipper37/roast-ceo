-- Migration: Fix charge_weight_lbs not being stamped in trg_stamp_roasted_weight
--
-- Root cause: the timezone fix migration (20260406210000) rewrote the trigger
-- using a local variable v_charge_weight but forgot to assign it back to
-- NEW.charge_weight_lbs. The original trigger (00179) stamped it directly.
--
-- 24 rows created via bulk-duplicate at 2026-04-06 21:37:27 have charge_weight
-- set but charge_weight_lbs NULL as a result.
--
-- Fix: restore NEW.charge_weight_lbs := v_charge_weight in the trigger,
-- then directly backfill the affected rows via a JOIN update (no trigger needed).

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

    -- Stamp resolved value back onto the row
    NEW.charge_weight_lbs := v_charge_weight;

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
        NEW.roast_date     := (NOW() AT TIME ZONE v_tz)::timestamp without time zone;
        NEW.roast_date_utc := NOW();
    ELSIF NEW."charged?" = false THEN
        NEW.roast_date     := NULL;
        NEW.roast_date_utc := NULL;
    ELSIF NEW.roast_date IS NOT NULL THEN
        NEW.roast_date_utc := NEW.roast_date AT TIME ZONE v_tz;
    END IF;

    RETURN NEW;
END;
$function$;

-- Backfill the affected rows directly — don't go through the trigger since
-- we only need to set charge_weight_lbs from the lookup (roasted_weight was
-- already computed correctly by the broken trigger via v_charge_weight).
SET session_replication_role = replica;

UPDATE roast_log rl
SET charge_weight_lbs = cwo.charge_weight
FROM charge_weight_options cwo
WHERE rl.charge_weight = cwo.id::text
  AND rl.charge_weight_lbs IS NULL;

SET session_replication_role = DEFAULT;
