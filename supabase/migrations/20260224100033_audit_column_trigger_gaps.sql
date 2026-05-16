-- Migration 00033: Fix remaining audit column and trigger gaps
--
-- Confirmed live gaps (validated against live DB errors and audit):
--   facilities     — all 4 columns present, both triggers were never added
--   order_statuses — global table: missing updated_at + both triggers
--   sales_state    — columns correct after 00032, both triggers missing
--
-- Non-issues (removed after live DB validation):
--   customer_category — triggers already exist in live DB
--   blend_in_stock / origin_in_stock — dropped in migration 00023
--
-- Deferred:
--   order_statuses.status_id rename ('Open' → 'open' etc.) — requires
--       updating calculate_totals_columns() and related references
--   customer_category / management_type name-as-PK antipattern


-- ── facilities ────────────────────────────────────────────────────────────────

CREATE OR REPLACE TRIGGER trg_audit_insert
    BEFORE INSERT ON public.facilities
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();

CREATE OR REPLACE TRIGGER trg_audit_update
    BEFORE UPDATE ON public.facilities
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


-- ── order_statuses ────────────────────────────────────────────────────────────
-- Global table: created_at + updated_at only, no _by columns.

ALTER TABLE public.order_statuses
    ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

CREATE OR REPLACE TRIGGER trg_audit_insert
    BEFORE INSERT ON public.order_statuses
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();

CREATE OR REPLACE TRIGGER trg_audit_update
    BEFORE UPDATE ON public.order_statuses
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


-- ── sales_state ───────────────────────────────────────────────────────────────

CREATE OR REPLACE TRIGGER trg_audit_insert
    BEFORE INSERT ON public.sales_state
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();

CREATE OR REPLACE TRIGGER trg_audit_update
    BEFORE UPDATE ON public.sales_state
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();
