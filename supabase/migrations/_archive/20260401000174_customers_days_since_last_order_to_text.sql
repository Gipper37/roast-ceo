-- Migration 00174: Change customers.days_since_last_order from numeric to text
-- Allows AppSheet formula to store "No Orders" / "No Recent Orders" text
-- as well as numeric day counts from update_customer_metrics_on_order trigger.

ALTER TABLE public.customers
  ALTER COLUMN days_since_last_order TYPE text USING days_since_last_order::text;
