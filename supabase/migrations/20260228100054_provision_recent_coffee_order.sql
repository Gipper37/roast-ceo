-- Migration 00054: Provision recent_coffee_order on new company signup
--
-- process_company_signup() seeds companies, facilities, team, and
-- company_parameters but never creates the singleton row in
-- recent_coffee_order that the Shipment Order Guide requires.
-- New tenants would land with an empty Shipment Order Guide window.
--
-- Fix:
--   A. Add UNIQUE(facility_id) to recent_coffee_order (enforces one-row-per-facility)
--   B. Update process_company_signup() to INSERT a starter row into recent_coffee_order

-- ═══════════════════════════════════════════════════════════════
-- A. Unique constraint: one recent_coffee_order row per facility
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE public.recent_coffee_order
  ADD CONSTRAINT recent_coffee_order_facility_id_key UNIQUE (facility_id);

-- ═══════════════════════════════════════════════════════════════
-- B. Update process_company_signup() to provision recent_coffee_order
-- ═══════════════════════════════════════════════════════════════

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
    FOR v_param IN SELECT parameters_id, text_value, amount, parameter FROM public.standard_parameters
    LOOP
        INSERT INTO public.company_parameters
          (company_id, facility_id, parameter_id, value, value_number, display_name, created_by)
        VALUES
          (v_company_id, v_facility_id, v_param.parameters_id,
           v_param.text_value, v_param.amount, v_param.parameter, v_team_id);
    END LOOP;

    -- 5. Provision Shipment Order Guide singleton row for this facility
    --    current_shipment_id starts NULL (no shipment received yet)
    INSERT INTO public.recent_coffee_order
      (recent_coffee_order_id, company_id, facility_id,
       total_pallets, lbs_ordered, recommended_pallets, bags_left, created_by)
    VALUES
      (gen_random_uuid()::text, v_company_id, v_facility_id,
       0, 0, 0, 0, v_team_id);

    -- 6. Mark processed
    NEW.processed := TRUE;
    RETURN NEW;

EXCEPTION WHEN OTHERS THEN
    NEW.error_message := SQLERRM;
    NEW.processed := FALSE;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
