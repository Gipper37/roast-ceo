-- Migration 00060: Clean up customer_sales_filter
--
-- 1. contact_info: text → boolean (AppSheet compares it as = TRUE / = FALSE)
-- 2. Drop blank_1, blank_2 placeholder columns
-- 3. Rename searcher → user_email for clarity

-- ── 1. contact_info: text → boolean ───────────────────────────
ALTER TABLE public.customer_sales_filter
  ALTER COLUMN contact_info TYPE boolean
  USING CASE LOWER(contact_info)
    WHEN 'true'  THEN TRUE
    WHEN 'false' THEN FALSE
    ELSE NULL
  END;

-- ── 2. Drop placeholder columns ────────────────────────────────
ALTER TABLE public.customer_sales_filter
  DROP COLUMN IF EXISTS blank_1,
  DROP COLUMN IF EXISTS blank_2;

-- ── 3. Rename searcher → user_email ───────────────────────────
ALTER TABLE public.customer_sales_filter
  RENAME COLUMN searcher TO user_email;
