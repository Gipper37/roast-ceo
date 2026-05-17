-- Stores each AppSheet user's currently selected roaster unit.
-- One row per user (keyed by email). Updated via AppSheet form/action.
-- roast_log.roaster_unit_id initial value:
--   LOOKUP(USEREMAIL(), user_roaster_settings, email, roaster_unit_id)

CREATE TABLE public.user_roaster_settings (
    email           text        PRIMARY KEY,
    roaster_unit_id uuid        REFERENCES public.roaster_units(roaster_unit_id),
    facility_id     text,
    company_id      text,
    created_at      timestamptz DEFAULT now(),
    updated_at      timestamptz DEFAULT now(),
    created_by      text,
    updated_by      text
);

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.user_roaster_settings
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();
CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.user_roaster_settings
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();
