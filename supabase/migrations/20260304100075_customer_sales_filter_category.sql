-- Migration 00075: Rename customer_sales_filter.sales_status → sales_category
--
-- sales_status was a filter field for AppSheet's customer sales section.
-- Renaming to sales_category to match the sales_category reference table it
-- will now be linked to. All current values are NULL — no data migration needed.

-- ── A. Rename column ─────────────────────────────────────────────
ALTER TABLE public.customer_sales_filter
    RENAME COLUMN sales_status TO sales_category;

-- ── B. Add FK to sales_category ──────────────────────────────────
-- NOT VALID: skips row scan (all values currently NULL, safe to add immediately)
ALTER TABLE public.customer_sales_filter
    ADD CONSTRAINT customer_sales_filter_sales_category_fkey
    FOREIGN KEY (sales_category)
    REFERENCES public.sales_category(sales_category)
    NOT VALID;
