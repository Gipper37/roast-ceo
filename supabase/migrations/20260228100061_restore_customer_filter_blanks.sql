-- Migration 00061: Restore blank_1, blank_2 on customer_sales_filter
--
-- These columns were dropped in 00060 but are required by the AppSheet frontend.

ALTER TABLE public.customer_sales_filter
  ADD COLUMN IF NOT EXISTS blank_1 text,
  ADD COLUMN IF NOT EXISTS blank_2 text;
