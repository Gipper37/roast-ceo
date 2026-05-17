-- Migration 00072: Drop sales_region from customer_sales_filter
--
-- customers.sales_region was removed in migration 00063.
-- customer_sales_filter.sales_region is now orphaned — no FK existed,
-- all 3 rows have NULL values. Completes the sales_region cleanup.

ALTER TABLE public.customer_sales_filter
    DROP COLUMN IF EXISTS sales_region;
