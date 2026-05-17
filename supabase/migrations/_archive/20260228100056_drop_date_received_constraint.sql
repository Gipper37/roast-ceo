-- Migration 00056: Drop chk_date_received_not_future constraint
--
-- AppSheet surfaces PostgreSQL CHECK constraint violations as a generic
-- loading error rather than a user-facing message, breaking the app.
-- Validation is moved to AppSheet via a Valid If expression instead.

ALTER TABLE public.shipment_received
  DROP CONSTRAINT chk_date_received_not_future;
