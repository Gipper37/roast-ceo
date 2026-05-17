-- Update process_company_signup() to insert a trialing subscription row
-- when a new company is created via the AppSheet in-app signup form.
-- Stripe customer creation is skipped here (no API access from plpgsql);
-- stripe_customer_id stays NULL until the user subscribes via the paywall.

CREATE OR REPLACE FUNCTION public.process_company_signup()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
    v_company_id    TEXT := gen_random_uuid()::text;
    v_facility_id   TEXT := gen_random_uuid()::text;
    v_team_id       TEXT := gen_random_uuid()::text;
    v_sub_id        TEXT := gen_random_uuid()::text;
    v_param         RECORD;
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
    INSERT INTO public.recent_coffee_order
      (recent_coffee_order_id, company_id, facility_id,
       total_pallets, lbs_ordered, recommended_pallets, bags_left, created_by)
    VALUES
      (gen_random_uuid()::text, v_company_id, v_facility_id,
       0, 0, 0, 0, v_team_id);

    -- 6. Create 14-day trialing subscription (no Stripe customer yet)
    INSERT INTO public.subscriptions
      (subscription_id, company_id, plan_id, status, trial_end, created_by)
    VALUES
      (v_sub_id, v_company_id, 'starter', 'trialing',
       now() + interval '14 days', v_team_id);

    -- 7. Mark processed
    NEW.processed := TRUE;
    RETURN NEW;

EXCEPTION WHEN OTHERS THEN
    NEW.error_message := SQLERRM;
    NEW.processed := FALSE;
    RETURN NEW;
END;
$$;
