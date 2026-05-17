ALTER TABLE public.user_roaster_settings
    ADD COLUMN IF NOT EXISTS user_roaster_settings_id text
        DEFAULT gen_random_uuid()::text;

-- Backfill existing rows
UPDATE public.user_roaster_settings
SET user_roaster_settings_id = gen_random_uuid()::text
WHERE user_roaster_settings_id IS NULL;

ALTER TABLE public.user_roaster_settings
    ALTER COLUMN user_roaster_settings_id SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS user_roaster_settings_id_key
    ON public.user_roaster_settings(user_roaster_settings_id);
