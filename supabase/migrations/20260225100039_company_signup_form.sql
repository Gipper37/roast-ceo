-- Migration 00039: company_signup_form table + trigger
-- In-app company signup form for AppSheet (mirrors web-based company-signup edge function)
-- DB trigger processes the form submission and creates company, facility, team, company_parameters

-- 1. Form table
CREATE TABLE IF NOT EXISTS public.company_signup_form (
    id             TEXT        PRIMARY KEY DEFAULT gen_random_uuid()::text,
    company_name   TEXT        NOT NULL,
    facility_name  TEXT        NOT NULL,
    timezone       TEXT        NOT NULL,
    country_code   TEXT,
    admin_name     TEXT        NOT NULL,
    email          TEXT        NOT NULL,
    processed      BOOLEAN     NOT NULL DEFAULT FALSE,
    error_message  TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

GRANT ALL ON public.company_signup_form TO anon, authenticated, service_role;

-- 2. Trigger function: processes form submission and creates all related records
CREATE OR REPLACE FUNCTION public.process_company_signup()
RETURNS TRIGGER AS $$
DECLARE
    v_company_id   TEXT := gen_random_uuid()::text;
    v_facility_id  TEXT := gen_random_uuid()::text;
    v_team_id      TEXT := gen_random_uuid()::text;
    v_param        RECORD;
BEGIN
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

-- 3. Trigger: fires before insert to process the signup
CREATE TRIGGER trg_process_company_signup
    BEFORE INSERT ON public.company_signup_form
    FOR EACH ROW
    EXECUTE FUNCTION public.process_company_signup();
