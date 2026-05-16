ALTER TABLE public.product_filter ADD COLUMN IF NOT EXISTS user_email text;
ALTER TABLE public.sales_data_filter ADD COLUMN IF NOT EXISTS user_email text;

-- Backfill existing rows with the created_by email from the team table
UPDATE public.product_filter pf
SET user_email = t.email
FROM public.team t
WHERE t.team_member_id = pf.created_by
AND pf.user_email IS NULL;

UPDATE public.sales_data_filter sdf
SET user_email = t.email
FROM public.team t
WHERE t.team_member_id = sdf.created_by
AND sdf.user_email IS NULL;
