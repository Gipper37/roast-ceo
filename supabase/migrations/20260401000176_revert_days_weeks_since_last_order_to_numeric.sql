-- Migration 00176: Revert days_since_last_order and weeks_since_last_order back to numeric
-- Display logic handled by AppSheet Virtual Columns instead.

ALTER TABLE public.customers
  ALTER COLUMN days_since_last_order TYPE numeric USING days_since_last_order::numeric;

ALTER TABLE public.customers
  ALTER COLUMN weeks_since_last_order TYPE numeric USING weeks_since_last_order::numeric;
