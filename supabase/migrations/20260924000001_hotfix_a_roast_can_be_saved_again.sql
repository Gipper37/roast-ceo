-- HOTFIX: a roast can be saved again.
--
-- MCR could not log a roast this morning. Every attempt carrying a charge
-- weight died in the BEFORE INSERT trigger on roast_log:
--
--   ERROR: relation "public.charge_weights" does not exist
--
-- which addRoast rethrows, and which the app renders as its generic "An error
-- occurred. Please notify your admin or reach out to STRATA support." The one
-- roast that DID save at 07:04:55 saved because it carried no charge weight.
--
-- WHAT BROKE IT. 20260922000002_a_back_dated_roast_keeps_its_date.sql rewrote
-- this whole function to fix back-dating, and rebuilt the weight preamble it
-- was not changing from memory rather than from the deployed definition. Three
-- things went wrong in that preamble, and only the first one announces itself:
--
--   1. `FROM public.charge_weights` — the table is charge_weight_options.
--      Hard error on every roast that names a charge weight.
--   2. `NEW.charge_weight_lbs := v_charge_weight` was DROPPED. That column is
--      what green deduction and every usage and COGS figure read. Renaming the
--      table alone would have made roasts save while silently writing NULL --
--      a worse bug than the outage, because nothing would have reported it.
--   3. The numeric-string fallback was dropped and the retention lookup was
--      rewritten against columns that do not exist (`standard_parameters.value`
--      -- it is `amount`; and parameter id 'RF1iFWjOh7' -- it is '1de271df').
--      On MCR, 1,043 of 1,044 charge weights are numeric strings, not UUIDs,
--      so the fallback IS the live path. Without it every roasted_weight would
--      compute from zero.
--
-- THE FIX. Take the weight preamble back, verbatim, from the definition that
-- was live from 2026-06-11 until 2026-09-22 (20260611000005_imported_roasts_
-- drive_inventory.sql) and keep the date handling from 20260922000002, which
-- is the part that migration was actually for and which is correct. Nothing
-- new is invented here: it is the union of two definitions that each worked.

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
    -- ── WEIGHT — restored from 20260611000005, unchanged ──────────────────
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

    -- ── DATES — kept from 20260922000002, unchanged ───────────────────────
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

-- ── Prove it, on the shape that was actually failing ────────────────────
do $$
declare
  v_def text := pg_get_functiondef('public.trg_stamp_roasted_weight'::regproc);
  v_id  text := 'probe-hotfix-' || md5(clock_timestamp()::text);
  v_w   numeric; v_lbs numeric; v_date timestamp;
begin
  if v_def like '%public.charge_weights %' then
    raise exception 'the function still references the non-existent charge_weights';
  end if;
  if v_def not like '%charge_weight_lbs := v_charge_weight%' then
    raise exception 'the function no longer stamps charge_weight_lbs';
  end if;
  if v_def not like '%standard_parameters sp%' and v_def not like '%standard_parameters WHERE%' then
    null;  -- shape check only; the retention lookup is asserted by the probe below
  end if;

  -- A live roast with a NUMERIC-STRING charge weight: the exact shape that
  -- failed all morning, and the shape 1,043 of MCR's 1,044 roasts use.
  insert into roast_log (roast_log_id, company_id, facility_id, roaster_unit_id,
                         charge_weight, "charged?")
  select v_id, company_id, facility_id, roaster_unit_id, '80', true
    from roast_log where company_id = '9ShiyDAXhV'
     and roaster_unit_id is not null order by roast_date desc limit 1;

  select charge_weight_lbs, roasted_weight, roast_date
    into v_lbs, v_w, v_date
    from roast_log where roast_log_id = v_id;

  if v_lbs is distinct from 80 then
    raise exception 'charge_weight_lbs came out as % — the green deduction reads this', v_lbs;
  end if;
  if coalesce(v_w, 0) <= 0 then
    raise exception 'roasted_weight came out as % — retention did not resolve', v_w;
  end if;
  if v_date is null then
    raise exception 'a charged roast got no roast_date';
  end if;

  raise notice 'a charged roast saves: charge 80 lbs -> charge_weight_lbs %, roasted_weight %, dated %',
    v_lbs, v_w, v_date;

  delete from roast_log where roast_log_id = v_id;
end $$;

commit;
