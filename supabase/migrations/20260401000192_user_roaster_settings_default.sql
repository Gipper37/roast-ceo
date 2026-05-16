-- Auto-select first active roaster for the facility on user creation.
-- Backfill existing rows with NULL roaster_unit_id.

CREATE OR REPLACE FUNCTION public.provision_user_roaster_settings()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_default_roaster uuid;
BEGIN
    IF NEW.email IS NOT NULL THEN
        SELECT roaster_unit_id INTO v_default_roaster
          FROM public.roaster_units
         WHERE facility_id = NEW.facility_id AND is_active = true
         ORDER BY created_at
         LIMIT 1;

        INSERT INTO public.user_roaster_settings
            (email, facility_id, company_id, roaster_unit_id)
        VALUES
            (NEW.email, NEW.facility_id, NEW.company_id, v_default_roaster)
        ON CONFLICT (email) DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$;

-- Backfill existing rows that have no roaster selected
UPDATE public.user_roaster_settings urs
SET roaster_unit_id = (
    SELECT roaster_unit_id
      FROM public.roaster_units ru
     WHERE ru.facility_id = urs.facility_id AND ru.is_active = true
     ORDER BY ru.created_at
     LIMIT 1
)
WHERE urs.roaster_unit_id IS NULL;
