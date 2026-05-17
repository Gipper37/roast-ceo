-- Add standard audit triggers to roast_stock_log
--
-- AppSheet explicitly sends NULL for created_at/updated_at on INSERT,
-- which overrides the column DEFAULT and violates the NOT NULL constraint.
-- handle_new_record() catches NULL and sets NOW() — it just needs to be
-- wired up to this table via triggers (same pattern as all other tables).

CREATE TRIGGER trg_audit_insert
    BEFORE INSERT ON public.roast_stock_log
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();

CREATE TRIGGER trg_audit_update
    BEFORE UPDATE ON public.roast_stock_log
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();
