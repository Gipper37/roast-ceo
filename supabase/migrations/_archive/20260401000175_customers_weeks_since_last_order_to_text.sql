-- Migration 00175: Change customers.weeks_since_last_order from numeric to text
-- Same pattern as days_since_last_order — AppSheet formula returns text or number.

ALTER TABLE public.customers
  ALTER COLUMN weeks_since_last_order TYPE text USING weeks_since_last_order::text;
