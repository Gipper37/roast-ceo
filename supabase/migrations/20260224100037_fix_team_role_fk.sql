-- Migration 00037: Fix team.role FK regression introduced in migration 00030
--
-- Migration 00030 incorrectly:
--   1. Converted team.role data from role_id values ('company_admin') to
--      display names ('Company Admin')
--   2. Wired the FK to user_roles.role_name instead of user_roles.role_id (the PK)
--
-- This was inconsistent with the invitations table (created in same migration),
-- which correctly references user_roles.role_id. It also broke AppSheet's
-- reference column which expected role_id values.
--
-- Fix: convert data back to role_id values and re-wire FK to the PK.

-- Step 1: drop the incorrect FK (references role_name, not the PK)
ALTER TABLE public.team DROP CONSTRAINT IF EXISTS team_role_fkey;

-- Step 2: convert display names back to role_id values
UPDATE public.team SET role = 'company_admin'   WHERE role = 'Company Admin';
UPDATE public.team SET role = 'facility_admin'  WHERE role = 'Facility Admin';
UPDATE public.team SET role = 'manager'         WHERE role = 'Manager';
UPDATE public.team SET role = 'roastmaster'     WHERE role = 'Roastmaster';
UPDATE public.team SET role = 'staff'           WHERE role = 'Staff' OR role IS NULL OR role = '';

-- Catch-all: anything not matching a valid role_id → staff
UPDATE public.team
    SET role = 'staff'
    WHERE role NOT IN ('company_admin', 'facility_admin', 'manager', 'roastmaster', 'staff');

-- Step 3: align the column default with the new pattern
ALTER TABLE public.team ALTER COLUMN role SET DEFAULT 'staff';

-- Step 4: add correct FK → user_roles.role_id (the PK)
-- Consistent with invitations.role_id → user_roles.role_id
ALTER TABLE public.team
    ADD CONSTRAINT team_role_fkey
    FOREIGN KEY (role) REFERENCES public.user_roles(role_id);
