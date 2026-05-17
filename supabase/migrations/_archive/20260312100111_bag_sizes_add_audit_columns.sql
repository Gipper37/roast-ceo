-- Migration 00111: Add missing audit columns to bag_sizes
--
-- bag_sizes was created without facility_id, created_by, updated_by.
-- Adding them to match the standard pattern on all other tables.
-- Also adding audit triggers (handle_new_record / handle_updated_record).

ALTER TABLE public.bag_sizes
    ADD COLUMN IF NOT EXISTS facility_id text,
    ADD COLUMN IF NOT EXISTS created_by  text,
    ADD COLUMN IF NOT EXISTS updated_by  text;

CREATE TRIGGER trg_audit_insert
    BEFORE INSERT ON public.bag_sizes
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_record();

CREATE TRIGGER trg_audit_update
    BEFORE UPDATE ON public.bag_sizes
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_updated_record();
