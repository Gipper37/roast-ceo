-- Add sort_order to user_roles for hierarchy display
ALTER TABLE public.user_roles ADD COLUMN IF NOT EXISTS sort_order integer;

-- Set hierarchy order for existing roles
UPDATE public.user_roles SET sort_order = 1 WHERE role_id = 'company_admin';
UPDATE public.user_roles SET sort_order = 2 WHERE role_id = 'facility_admin';
UPDATE public.user_roles SET sort_order = 3 WHERE role_id = 'manager';
UPDATE public.user_roles SET sort_order = 4 WHERE role_id = 'roastmaster';
UPDATE public.user_roles SET sort_order = 6 WHERE role_id = 'staff';
UPDATE public.user_roles SET sort_order = 7 WHERE role_id = 'sales_person';

-- Add assistant_roaster between roastmaster (4) and staff (6)
INSERT INTO public.user_roles (role_id, role_name, sort_order)
VALUES ('assistant_roaster', 'Assistant Roaster', 5)
ON CONFLICT (role_id) DO NOTHING;
