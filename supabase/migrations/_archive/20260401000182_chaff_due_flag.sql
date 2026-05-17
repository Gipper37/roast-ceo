-- Adds chaff_due boolean to roast_log.
-- TRUE when batches_since_chaff >= facility threshold (company_parameters → standard_parameters).
-- Maintained by the same trigger as batches_since_chaff.
-- AppSheet bot condition: [chaff_due] = TRUE AND [roast_date] > NOW()-1min

ALTER TABLE public.roast_log
    ADD COLUMN IF NOT EXISTS chaff_due boolean;

-- ── Update recalculate_batches_since_chaff to also set chaff_due ─────────────

CREATE OR REPLACE FUNCTION public.recalculate_batches_since_chaff(p_facility_id text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_last_chaff_date timestamp without time zone;
    v_count           integer;
    v_threshold       numeric;
BEGIN
    PERFORM set_config('app.skip_audit', 'true', true);

    -- 2-tier threshold lookup: company_parameters → standard_parameters
    SELECT COALESCE(
        (SELECT value_number
           FROM public.company_parameters
          WHERE parameter_id = 'xd38srqb'
            AND facility_id  = p_facility_id
            AND value_number IS NOT NULL
          LIMIT 1),
        (SELECT amount
           FROM public.standard_parameters
          WHERE parameters_id = 'xd38srqb'),
        15
    ) INTO v_threshold;

    SELECT MAX(roast_date) INTO v_last_chaff_date
    FROM public.roast_log
    WHERE facility_id = p_facility_id AND "chaff_cleaned?" = TRUE;

    IF v_last_chaff_date IS NOT NULL THEN
        SELECT COUNT(*) INTO v_count
        FROM public.roast_log
        WHERE facility_id = p_facility_id
          AND "charged?"  = TRUE
          AND roast_date  > v_last_chaff_date;

        UPDATE public.roast_log
        SET batches_since_chaff = CASE
                WHEN "charged?" = TRUE AND roast_date > v_last_chaff_date THEN v_count
                ELSE NULL
            END,
            chaff_due = CASE
                WHEN "charged?" = TRUE AND roast_date > v_last_chaff_date
                     THEN (v_count >= v_threshold)
                ELSE NULL
            END
        WHERE facility_id = p_facility_id
          AND (
              batches_since_chaff IS DISTINCT FROM CASE
                  WHEN "charged?" = TRUE AND roast_date > v_last_chaff_date THEN v_count
                  ELSE NULL
              END
              OR
              chaff_due IS DISTINCT FROM CASE
                  WHEN "charged?" = TRUE AND roast_date > v_last_chaff_date
                       THEN (v_count >= v_threshold)
                  ELSE NULL
              END
          );
    ELSE
        UPDATE public.roast_log
        SET batches_since_chaff = NULL,
            chaff_due           = NULL
        WHERE facility_id = p_facility_id
          AND (batches_since_chaff IS NOT NULL OR chaff_due IS NOT NULL);
    END IF;
END;
$$;

-- ── Re-populate existing rows ─────────────────────────────────────────────────

DO $$
DECLARE
    v_fid text;
BEGIN
    FOR v_fid IN
        SELECT DISTINCT facility_id FROM public.roast_log WHERE facility_id IS NOT NULL
    LOOP
        PERFORM public.recalculate_batches_since_chaff(v_fid);
    END LOOP;
END;
$$;
