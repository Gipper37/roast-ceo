-- Migration 00063: Location hierarchy cleanup
--
-- A. Drop circular FK on sales_state:
--    sales_state.area_id → sales_area creates a circular dependency with
--    sales_area.state_id → sales_state. Almost certainly a mistake.
--
-- B. Add missing audit triggers to sales_state (oversight from migration 00032/00033).
--
-- C. Drop sales_region column from customers (user confirmed — region is too coarse
--    for per-salesperson filtering and is derivable via sales_area → sales_state → region).

-- ── A. Drop circular FK on sales_state ─────────────────────────
ALTER TABLE public.sales_state
    DROP CONSTRAINT IF EXISTS sales_state_area_id_fkey,
    DROP COLUMN    IF EXISTS area_id;

-- ── B. Add missing audit triggers to sales_state ───────────────
DROP TRIGGER IF EXISTS trg_audit_insert ON public.sales_state;
CREATE TRIGGER trg_audit_insert
    BEFORE INSERT ON public.sales_state
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();

DROP TRIGGER IF EXISTS trg_audit_update ON public.sales_state;
CREATE TRIGGER trg_audit_update
    BEFORE UPDATE ON public.sales_state
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();

-- ── C. Drop sales_region from customers ────────────────────────
ALTER TABLE public.customers
    DROP CONSTRAINT IF EXISTS customers_sales_region_fkey,
    DROP COLUMN    IF EXISTS sales_region;
