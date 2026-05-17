-- Migration 00062: Add missing audit triggers
--
-- Audit found sales_region was missing its insert trigger.
-- user_roles.trg_audit_update already exists; only the insert trigger is missing.
-- Using DROP IF EXISTS to make this idempotent.
-- handle_new_record() and handle_updated_record() gracefully handle tables
-- without company_id or _by columns via EXCEPTION blocks.

-- ── sales_region: add missing insert trigger ───────────────────
DROP TRIGGER IF EXISTS trg_audit_insert ON public.sales_region;
CREATE TRIGGER trg_audit_insert
    BEFORE INSERT ON public.sales_region
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();

-- ── user_roles: add missing insert trigger ─────────────────────
-- (update trigger trg_audit_update already exists on this table)
DROP TRIGGER IF EXISTS trg_audit_insert ON public.user_roles;
CREATE TRIGGER trg_audit_insert
    BEFORE INSERT ON public.user_roles
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();
