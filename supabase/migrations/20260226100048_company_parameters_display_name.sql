-- Migration 00048: Company parameters — display_name, backfill, unique constraint
--
-- 1. Add display_name column to company_parameters (human-readable label)
-- 2. Backfill display_name from standard_parameters.parameter for all existing rows
-- 3. Backfill missing parameters for Social Hour Coffee (pre-dates units & orders_reset_day)
-- 4. Fix unique constraint: (company_id, parameter_id) → (company_id, facility_id, parameter_id)
-- 5. Update process_company_signup() to include display_name when seeding

-- ═══════════════════════════════════════════════════════════════
-- A. Add display_name column
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE public.company_parameters
  ADD COLUMN IF NOT EXISTS display_name text;

-- ═══════════════════════════════════════════════════════════════
-- B. Backfill display_name for all existing rows
-- ═══════════════════════════════════════════════════════════════

UPDATE public.company_parameters cp
SET display_name = sp.parameter
FROM public.standard_parameters sp
WHERE cp.parameter_id = sp.parameters_id
  AND cp.display_name IS NULL;

-- ═══════════════════════════════════════════════════════════════
-- C. Backfill missing parameters for Social Hour Coffee
-- ═══════════════════════════════════════════════════════════════
-- Social Hour (R7CbqHmA1j / cc844abb) was created before migrations
-- 00015 and 00030 added orders_reset_day and units to standard_parameters.
-- This INSERT is future-proof: fills any missing parameters, not just those two.

INSERT INTO public.company_parameters
  (company_id, facility_id, parameter_id, value, value_number, display_name)
SELECT
  'R7CbqHmA1j',
  'cc844abb-db0b-48db-9aeb-abd8df9117de',
  sp.parameters_id,
  sp.text_value,
  sp.amount,
  sp.parameter
FROM public.standard_parameters sp
WHERE sp.parameters_id NOT IN (
  SELECT parameter_id FROM public.company_parameters
  WHERE company_id = 'R7CbqHmA1j'
    AND facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de'
)
ON CONFLICT DO NOTHING;

-- ═══════════════════════════════════════════════════════════════
-- D. Fix unique constraint to include facility_id
-- ═══════════════════════════════════════════════════════════════
-- Current: UNIQUE(company_id, parameter_id) — blocks multi-facility companies
-- New:     UNIQUE(company_id, facility_id, parameter_id)

ALTER TABLE public.company_parameters
  DROP CONSTRAINT company_parameters_company_id_parameter_id_key;

ALTER TABLE public.company_parameters
  ADD CONSTRAINT company_parameters_company_facility_parameter_key
  UNIQUE (company_id, facility_id, parameter_id);

-- ═══════════════════════════════════════════════════════════════
-- E. Update process_company_signup() to include display_name
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

    -- 5. Mark processed
    NEW.processed := TRUE;
    RETURN NEW;

EXCEPTION WHEN OTHERS THEN
    NEW.error_message := SQLERRM;
    NEW.processed := FALSE;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
