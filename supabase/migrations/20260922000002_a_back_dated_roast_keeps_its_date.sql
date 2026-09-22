-- "Add a roast that already happened" saved it as today.
--
-- A roastmaster picked the 14th, saved, and the roast landed on the 22nd.
-- The app was right: it sent roast_date, and the server validated it, refused
-- a future date and inserted it. The trigger then threw it away.
--
-- trg_stamp_roasted_weight's live-roasting branch says "never trust the value
-- sent by the app" and stamps NOW() whenever a row arrives charged. That is
-- correct for the path it was written for, where charging IS the moment and
-- the app sends no date. A back-dated roast is inserted charged too, because
-- it already happened, so it fell into the same branch and lost its day.
--
-- Every roast MCR logged this way carries the same fingerprint: roast_date
-- exactly equal to created_at in facility-local time, never the day chosen.
--
-- The carve-out is narrow on purpose:
--   INSERT only. An UPDATE that flips charged? on an existing row is still
--   the live charge, and still stamps now.
--   Only when a roast_date was actually supplied. A live charge sends none,
--   so it is untouched.
-- Everything else about the branch, including clearing both columns when
-- charged? goes false, is unchanged.

begin;

create or replace function public.trg_stamp_roasted_weight()
returns trigger
language plpgsql
as $function$
DECLARE
    v_charge_weight numeric;
    v_retention     numeric;
    v_tz            text;
BEGIN
    IF NEW.roasted_weight IS NULL AND NEW.charge_weight IS NOT NULL THEN
        SELECT cw.charge_weight INTO v_charge_weight
        FROM public.charge_weights cw WHERE cw.id = NEW.charge_weight;

        SELECT COALESCE(
                 (SELECT rr.retention_factor FROM public.roast_recipes rr
                   WHERE rr.recipe_id = NEW.recipe_id AND rr.retention_factor IS NOT NULL),
                 (SELECT cp.value::numeric FROM public.company_parameters cp
                   WHERE cp.company_id = NEW.company_id AND cp.parameter_id = 'RF1iFWjOh7'),
                 (SELECT sp.value::numeric FROM public.standard_parameters sp
                   WHERE sp.parameters_id = 'RF1iFWjOh7'),
                 0.82)
          INTO v_retention;

        NEW.roasted_weight := ROUND(COALESCE(v_charge_weight, 0) * v_retention, 2);
    END IF;

    SELECT COALESCE(NULLIF(time_zone, ''), 'UTC') INTO v_tz
    FROM public.facilities WHERE facility_id = NEW.facility_id;
    v_tz := COALESCE(v_tz, 'UTC');

    IF NEW.external_roast_id IS NOT NULL THEN
        IF NEW."charged?" = false THEN
            NEW.roast_date     := NULL;
            NEW.roast_date_utc := NULL;
        ELSIF NEW.roast_date_utc IS NOT NULL THEN
            NEW.roast_date := (NEW.roast_date_utc AT TIME ZONE v_tz);
        ELSIF NEW.roast_date IS NOT NULL THEN
            NEW.roast_date_utc := NEW.roast_date AT TIME ZONE v_tz;
        END IF;
    ELSE
        IF NEW."charged?" = true AND (TG_OP = 'INSERT' OR OLD."charged?" IS DISTINCT FROM true) THEN
            IF TG_OP = 'INSERT' AND NEW.roast_date IS NOT NULL THEN
                -- Back-dated: the caller named the day it happened. Keep it and
                -- derive the UTC twin from the facility's clock.
                NEW.roast_date_utc := NEW.roast_date AT TIME ZONE v_tz;
            ELSE
                -- Live charge: charging IS the moment, so now wins.
                NEW.roast_date     := (NOW() AT TIME ZONE v_tz)::timestamp without time zone;
                NEW.roast_date_utc := NOW();
            END IF;
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

commit;
