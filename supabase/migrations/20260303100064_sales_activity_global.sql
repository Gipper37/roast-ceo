-- Migration 00064: Make sales_activity a global lookup table
--
-- Activity types (New, Signed, Cold Call, etc.) are universal — they drive
-- sales_goals category logic and are too interdependent to allow per-company
-- or per-facility customisation. Remove company_id and facility_id so they
-- behave like other global lookups (sales_region, stock_types, etc.).

ALTER TABLE public.sales_activity
    DROP CONSTRAINT IF EXISTS sales_activity_company_id_fkey,
    DROP CONSTRAINT IF EXISTS sales_activity_facility_id_fkey,
    DROP COLUMN    IF EXISTS company_id,
    DROP COLUMN    IF EXISTS facility_id;
