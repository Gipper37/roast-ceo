ALTER TABLE public.contacts ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true;
