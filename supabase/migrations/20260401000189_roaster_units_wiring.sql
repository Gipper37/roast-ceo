-- 1. Add max_charge_weight_id (Ref to charge_weight_options) to roaster_units
-- 2. Trigger to sync max_charge_weight_lbs from ref
-- 3. Create Giesen W15A for Social Hour
-- 4. Backfill all Social Hour roast_log rows
-- 5. Auto-create user_roaster_settings on team INSERT
-- 6. Backfill existing team members

-- ── 1. Add max_charge_weight_id ───────────────────────────────────────────────

ALTER TABLE public.roaster_units
    ADD COLUMN IF NOT EXISTS max_charge_weight_id text
        REFERENCES public.charge_weight_options(id);

-- ── 2. Trigger to keep max_charge_weight_lbs in sync ─────────────────────────

CREATE OR REPLACE FUNCTION public.fn_sync_roaster_charge_weight()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.max_charge_weight_id IS NOT NULL THEN
        SELECT charge_weight INTO NEW.max_charge_weight_lbs
          FROM public.charge_weight_options
         WHERE id = NEW.max_charge_weight_id;
    ELSE
        NEW.max_charge_weight_lbs := NULL;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_sync_roaster_charge_weight
    BEFORE INSERT OR UPDATE OF max_charge_weight_id
    ON public.roaster_units
    FOR EACH ROW EXECUTE FUNCTION public.fn_sync_roaster_charge_weight();

-- ── 3. Create Giesen W15A for Social Hour / Waikapu Roasting Facility ─────────

INSERT INTO public.roaster_units (
    facility_id,
    company_id,
    name,
    max_charge_weight_id,
    max_charge_weight_lbs,
    is_active
) VALUES (
    'cc844abb-db0b-48db-9aeb-abd8df9117de',
    'R7CbqHmA1j',
    'Giesen W15A',
    'a8a262d4-9e6b-46c9-8520-6f16627034b7',  -- 30 lbs
    30,
    true
);

-- ── 4. Backfill all Social Hour roast_log rows ────────────────────────────────

DO $$
DECLARE
    v_roaster_unit_id uuid;
BEGIN
    SELECT roaster_unit_id INTO v_roaster_unit_id
      FROM public.roaster_units
     WHERE facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de'
       AND name = 'Giesen W15A';

    SET session_replication_role = replica;

    UPDATE public.roast_log
       SET roaster_unit_id = v_roaster_unit_id
     WHERE facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de'
       AND roaster_unit_id IS NULL;

    SET session_replication_role = DEFAULT;
END;
$$;

-- ── 5. Auto-create user_roaster_settings on team INSERT ──────────────────────

CREATE OR REPLACE FUNCTION public.provision_user_roaster_settings()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.email IS NOT NULL THEN
        INSERT INTO public.user_roaster_settings (email, facility_id, company_id)
        VALUES (NEW.email, NEW.facility_id, NEW.company_id)
        ON CONFLICT (email) DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_provision_user_roaster_settings
    AFTER INSERT ON public.team
    FOR EACH ROW EXECUTE FUNCTION public.provision_user_roaster_settings();

-- ── 6. Backfill existing team members ────────────────────────────────────────

INSERT INTO public.user_roaster_settings (email, facility_id, company_id)
SELECT email, facility_id, company_id
  FROM public.team
 WHERE email IS NOT NULL
ON CONFLICT (email) DO NOTHING;

