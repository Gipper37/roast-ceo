-- Migration 00040: Fix company_signup_form — add missing audit columns + triggers
-- The table was missing created_by/updated_by and the standard audit triggers
-- that every other table has (which handle AppSheet sending explicit NULLs)

-- 1. Add missing columns
ALTER TABLE public.company_signup_form
    ADD COLUMN IF NOT EXISTS created_by TEXT,
    ADD COLUMN IF NOT EXISTS updated_by TEXT;

-- 2. Add standard audit triggers (handle_new_record sets created_at/updated_at when NULL)
CREATE TRIGGER trg_audit_insert
    BEFORE INSERT ON public.company_signup_form
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();

CREATE TRIGGER trg_audit_update
    BEFORE UPDATE ON public.company_signup_form
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();

-- 3. Update process_company_signup() with COALESCE safety for id/processed
CREATE OR REPLACE FUNCTION public.process_company_signup()
RETURNS TRIGGER AS $$
DECLARE
    v_company_id   TEXT := gen_random_uuid()::text;
    v_facility_id  TEXT := gen_random_uuid()::text;
    v_team_id      TEXT := gen_random_uuid()::text;
    v_param        RECORD;
BEGIN
    -- Safety: ensure defaults for columns AppSheet may send as NULL
    NEW.id        := COALESCE(NEW.id, gen_random_uuid()::text);
    NEW.processed := COALESCE(NEW.processed, FALSE);

    -- 1. Create company
    INSERT INTO public.companies (company_id, company_name, created_by)
    VALUES (v_company_id, NEW.company_name, v_team_id);

    -- 2. Create facility
    INSERT INTO public.facilities (facility_id, company_id, facility_name, time_zone, country_code, created_by)
    VALUES (v_facility_id, v_company_id, NEW.facility_name, NEW.timezone, NEW.country_code, v_team_id);

    -- 3. Create team member (company_admin)
    INSERT INTO public.team (team_member_id, name, email, company_id, facility_id, role, onboarding_completed, first_app_open_at, created_by)
    VALUES (v_team_id, NEW.admin_name, NEW.email, v_company_id, v_facility_id, 'company_admin', FALSE, NULL, v_team_id);

    -- 4. Seed company_parameters from standard_parameters
    FOR v_param IN SELECT parameters_id, text_value, amount FROM public.standard_parameters
    LOOP
        INSERT INTO public.company_parameters (company_id, facility_id, parameter_id, value, value_number, created_by)
        VALUES (v_company_id, v_facility_id, v_param.parameters_id, v_param.text_value, v_param.amount, v_team_id);
    END LOOP;

    -- 5. Mark processed
    NEW.processed := TRUE;
    RETURN NEW;

EXCEPTION WHEN OTHERS THEN
    NEW.error_message := SQLERRM;
    NEW.processed := FALSE;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
