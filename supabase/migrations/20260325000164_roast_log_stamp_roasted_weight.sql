-- Trigger function: stamp roasted_weight at time of INSERT using 3-tier retention factor
CREATE OR REPLACE FUNCTION public.trg_stamp_roasted_weight()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_retention numeric;
BEGIN
    -- Tier 1: facility-specific override in company_parameters
    SELECT value_number INTO v_retention
    FROM public.company_parameters
    WHERE parameter_id = '1de271df'
      AND facility_id  = NEW.facility_id
    LIMIT 1;

    -- Tier 2: system default in standard_parameters
    IF v_retention IS NULL OR v_retention = 0 THEN
        SELECT amount INTO v_retention
        FROM public.standard_parameters
        WHERE parameters_id = '1de271df'
        LIMIT 1;
    END IF;

    -- Tier 3: hardcoded fallback
    IF v_retention IS NULL OR v_retention = 0 THEN
        v_retention := 0.82;
    END IF;

    NEW.roasted_weight := ROUND(COALESCE(NEW.charge_weight, 0) * v_retention, 2);

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_stamp_roasted_weight
BEFORE INSERT OR UPDATE ON public.roast_log
FOR EACH ROW
EXECUTE FUNCTION public.trg_stamp_roasted_weight();
