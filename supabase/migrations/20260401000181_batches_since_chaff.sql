-- Replaces the O(n²) AppSheet VC "Last Chaff" with a DB-maintained stored column.
-- batches_since_chaff: for charged rows after the facility's last chaff clean date,
-- stores the count of charged roasts since that clean. NULL for all other rows.
-- Updated by trigger on charged?/chaff_cleaned?/roast_date changes.

-- ── 1. Teach handle_updated_record() to respect an internal bypass flag ─────
--    When app.skip_audit = 'true', skip bumping updated_at.
--    Used by recalculate_batches_since_chaff() to avoid AppSheet re-syncing
--    every cascade-updated row.

CREATE OR REPLACE FUNCTION public.handle_updated_record()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF current_setting('app.skip_audit', TRUE) = 'true' THEN
        RETURN NEW;
    END IF;
    NEW.updated_at := NOW();
    BEGIN
        IF NEW.company_id IS NULL THEN
            NEW.company_id := OLD.company_id;
        END IF;
    EXCEPTION WHEN undefined_column THEN
        NULL;
    END;
    RETURN NEW;
END;
$$;

-- ── 2. Add the stored column ─────────────────────────────────────────────────

ALTER TABLE public.roast_log
    ADD COLUMN IF NOT EXISTS batches_since_chaff integer;

-- ── 3. Recalculation function ─────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.recalculate_batches_since_chaff(p_facility_id text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_last_chaff_date timestamp without time zone;
    v_count           integer;
BEGIN
    -- Bypass updated_at bumping for this internal batch update
    PERFORM set_config('app.skip_audit', 'true', true);

    SELECT MAX(roast_date) INTO v_last_chaff_date
    FROM public.roast_log
    WHERE facility_id = p_facility_id AND "chaff_cleaned?" = TRUE;

    IF v_last_chaff_date IS NOT NULL THEN
        SELECT COUNT(*) INTO v_count
        FROM public.roast_log
        WHERE facility_id     = p_facility_id
          AND "charged?"      = TRUE
          AND roast_date      > v_last_chaff_date;

        -- Only touch rows whose value actually needs to change
        UPDATE public.roast_log
        SET batches_since_chaff = CASE
            WHEN "charged?" = TRUE AND roast_date > v_last_chaff_date THEN v_count
            ELSE NULL
        END
        WHERE facility_id = p_facility_id
          AND batches_since_chaff IS DISTINCT FROM CASE
              WHEN "charged?" = TRUE AND roast_date > v_last_chaff_date THEN v_count
              ELSE NULL
          END;
    ELSE
        UPDATE public.roast_log
        SET batches_since_chaff = NULL
        WHERE facility_id = p_facility_id
          AND batches_since_chaff IS NOT NULL;
    END IF;
END;
$$;

-- ── 4. Trigger function ───────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_update_batches_since_chaff()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM public.recalculate_batches_since_chaff(OLD.facility_id);
        RETURN OLD;
    END IF;
    PERFORM public.recalculate_batches_since_chaff(NEW.facility_id);
    -- Handle facility_id reassignment (edge case)
    IF TG_OP = 'UPDATE' AND OLD.facility_id IS DISTINCT FROM NEW.facility_id THEN
        PERFORM public.recalculate_batches_since_chaff(OLD.facility_id);
    END IF;
    RETURN NEW;
END;
$$;

-- ── 5. Trigger ────────────────────────────────────────────────────────────────

DROP TRIGGER IF EXISTS trg_update_batches_since_chaff ON public.roast_log;

CREATE TRIGGER trg_update_batches_since_chaff
    AFTER INSERT OR DELETE
        OR UPDATE OF "charged?", "chaff_cleaned?", roast_date, facility_id
    ON public.roast_log
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_update_batches_since_chaff();

-- ── 6. Initial population ─────────────────────────────────────────────────────

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
