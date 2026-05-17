-- Onboarding schema prep
--
-- 0. Fix handle_new_record / handle_updated_record to not crash on tables
--    without a company_id column (e.g. standard_parameters, which had its
--    company_id dropped in migration 00025)
-- 1. Add auth_user_id to team (links app users to Supabase Auth)
-- 2. Drop team_member_role (unused, replaced by user_roles)
-- 3. Seed user_roles with standard roastery roles
-- 4. Normalize team.role values and add FK to user_roles.role_name
-- 5. Add 'units' weight parameter to standard_parameters
-- 6. Create invitations table for future team member invite flow

-- ─── 0. Fix audit trigger functions ──────────────────────────────────────────
-- The original functions used:
--   IF TG_OP = 'UPDATE' AND NEW.company_id IS NULL THEN ...
-- PostgreSQL does not always short-circuit the AND when evaluating NEW.field
-- on a table that lacks that column. Restructure to nested IF + EXCEPTION block
-- so tables without company_id are handled gracefully.

CREATE OR REPLACE FUNCTION public.handle_new_record() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.created_at IS NULL THEN NEW.created_at := NOW(); END IF;
    IF NEW.updated_at IS NULL THEN NEW.updated_at := NOW(); END IF;
    -- Protect company_id on UPDATE (AppSheet wipeout fix).
    -- Wrapped in EXCEPTION for tables that don't have company_id.
    IF TG_OP = 'UPDATE' THEN
        BEGIN
            IF NEW.company_id IS NULL THEN
                NEW.company_id := OLD.company_id;
            END IF;
        EXCEPTION WHEN undefined_column THEN
            NULL;
        END;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.handle_updated_record() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
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

-- ─── 1. Add auth_user_id to team ─────────────────────────────────────────────
-- UUID type — populated only by Edge Function, not by AppSheet.
-- Mark non-editable and hidden in AppSheet column settings.

ALTER TABLE public.team
    ADD COLUMN IF NOT EXISTS auth_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL;

-- ─── 2. Drop team_member_role ─────────────────────────────────────────────────

DROP TABLE IF EXISTS public.team_member_role;

-- ─── 3. Seed user_roles ───────────────────────────────────────────────────────
-- Clear existing rows first (no FK dependencies yet) then insert clean set.

DELETE FROM public.user_roles;

INSERT INTO public.user_roles (role_id, role_name) VALUES
    ('company_admin',   'Company Admin'),
    ('facility_admin',  'Facility Admin'),
    ('manager',         'Manager'),
    ('roastmaster',     'Roastmaster'),
    ('staff',           'Staff');

-- ─── 4. Normalize team.role and add FK ───────────────────────────────────────
-- Map existing values to new role names before adding the FK constraint.

UPDATE public.team SET role = 'Staff'          WHERE role IS NULL OR role = '';
UPDATE public.team SET role = 'Company Admin'  WHERE LOWER(role) IN ('admin', 'company admin', 'company_admin');
UPDATE public.team SET role = 'Facility Admin' WHERE LOWER(role) IN ('facility admin', 'facility_admin');
UPDATE public.team SET role = 'Manager'        WHERE LOWER(role) = 'manager';
UPDATE public.team SET role = 'Roastmaster'    WHERE LOWER(role) IN ('roaster', 'roastmaster');

-- Catch-all: anything still not matching → Staff
UPDATE public.team
    SET role = 'Staff'
    WHERE role NOT IN ('Company Admin', 'Facility Admin', 'Manager', 'Roastmaster', 'Staff');

ALTER TABLE public.team
    ADD CONSTRAINT team_role_fkey
    FOREIGN KEY (role) REFERENCES public.user_roles(role_name);

-- ─── 5. Add units weight parameter to standard_parameters ────────────────────

INSERT INTO public.standard_parameters (parameters_id, parameter, text_value, data_type)
VALUES ('units', 'Weight Units', 'lbs', 'text')
ON CONFLICT (parameters_id) DO NOTHING;

-- ─── 6. Create invitations table ─────────────────────────────────────────────

CREATE TABLE public.invitations (
    invitation_id   text        NOT NULL DEFAULT (gen_random_uuid()::text),
    company_id      text        NOT NULL,
    facility_id     text,
    invited_email   text        NOT NULL,
    role_id         text        NOT NULL,
    invited_by      text,
    token           text        NOT NULL DEFAULT (gen_random_uuid()::text),
    accepted_at     timestamptz,
    expires_at      timestamptz NOT NULL DEFAULT (now() + interval '7 days'),
    created_at      timestamptz NOT NULL DEFAULT now(),
    created_by      text,
    updated_at      timestamptz NOT NULL DEFAULT now(),
    updated_by      text,
    CONSTRAINT invitations_pkey          PRIMARY KEY (invitation_id),
    CONSTRAINT invitations_token_key     UNIQUE (token),
    CONSTRAINT invitations_company_fk    FOREIGN KEY (company_id)  REFERENCES public.companies(company_id)  ON DELETE CASCADE,
    CONSTRAINT invitations_facility_fk   FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id),
    CONSTRAINT invitations_role_fk       FOREIGN KEY (role_id)     REFERENCES public.user_roles(role_id),
    CONSTRAINT invitations_invited_by_fk FOREIGN KEY (invited_by)  REFERENCES public.team(team_member_id)
);

CREATE TRIGGER trg_audit_insert
    BEFORE INSERT ON public.invitations
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();

CREATE TRIGGER trg_audit_update
    BEFORE UPDATE ON public.invitations
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();
