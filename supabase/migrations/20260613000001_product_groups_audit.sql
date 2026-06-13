-- ============================================================================
-- product_groups: add audit columns + attach shared audit triggers
-- ----------------------------------------------------------------------------
-- product_groups was introduced in the 2026-04-05 product redesign with only
-- created_at/updated_at (defaulted) and NO created_by/updated_by + NO audit
-- triggers — unlike every sibling table (products, channel, product_category).
-- Two consequences fixed here:
--   1. No created_by/updated_by columns (attribution gap).
--   2. updated_at never refreshed on UPDATE (no trigger; stuck at creation time).
-- handle_new_record()/handle_updated_record() only touch created_at/updated_at/
-- company_id (with an undefined_column guard), all present here — safe to attach.
-- ============================================================================

BEGIN;

ALTER TABLE public.product_groups
    ADD COLUMN IF NOT EXISTS created_by text,
    ADD COLUMN IF NOT EXISTS updated_by text;

DROP TRIGGER IF EXISTS trg_audit_insert ON public.product_groups;
CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.product_groups
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();

DROP TRIGGER IF EXISTS trg_audit_update ON public.product_groups;
CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.product_groups
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();

COMMIT;
