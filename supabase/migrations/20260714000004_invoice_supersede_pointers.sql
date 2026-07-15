-- Revise & reissue ("supersede") correction flow for posted invoices.
--
-- A posted invoice is immutable (guard_posted_order_immutable). To correct one,
-- the operator voids it and issues a REPLACEMENT: we clone the order into a fresh
-- editable draft, let them fix it, and re-finalize to a NEW number. These two
-- nullable pointers record the link both ways:
--   supersedes_invoice_number  — stamped on the REPLACEMENT (for its PDF/email header)
--   superseded_by_order_id      — stamped on the VOID original (for traceability)
-- Both sit outside guard_posted_order_immutable's checked columns, so stamping the
-- void original doesn't trip the lock.

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS supersedes_invoice_number text,
  ADD COLUMN IF NOT EXISTS superseded_by_order_id     text REFERENCES public.orders(order_id);

NOTIFY pgrst, 'reload schema';
