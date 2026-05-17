-- Migration 00065: Add missing FK constraints to sales tables
--
-- All three use NOT VALID to avoid scanning live data rows on a production DB.
-- Run VALIDATE CONSTRAINT separately once data is confirmed clean.
--
-- 1. customers.state → sales_state (AppSheet already treats this as a Ref;
--    DB constraint was never added)
-- 2. sales_notes.customer_id → customers (no orphan protection existed)
-- 3. sales_notes.sales_activity_type → sales_activity (column stores activity IDs;
--    FK enforces referential integrity)

-- ── 1. customers.state → sales_state ───────────────────────────
ALTER TABLE public.customers
    ADD CONSTRAINT customers_state_fkey
    FOREIGN KEY (state) REFERENCES public.sales_state(id)
    NOT VALID;

-- ── 2. sales_notes.customer_id → customers ─────────────────────
ALTER TABLE public.sales_notes
    ADD CONSTRAINT sales_notes_customer_id_fkey
    FOREIGN KEY (customer_id) REFERENCES public.customers(customer_id)
    NOT VALID;

-- ── 3. sales_notes.sales_activity_type → sales_activity ────────
ALTER TABLE public.sales_notes
    ADD CONSTRAINT sales_notes_activity_fkey
    FOREIGN KEY (sales_activity_type) REFERENCES public.sales_activity(sales_activity_id)
    NOT VALID;
