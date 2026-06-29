-- Optional expected-arrival (ETA) date on coffee shipments / purchase orders.
-- Lets the inventory "Low · incoming" at-risk badge compare a group's on-hand
-- run-out date against when the in-flight order is actually due, instead of a
-- fixed 14-day heuristic. Nullable — an ETA is never required when ordering.
ALTER TABLE public.shipment_received
  ADD COLUMN IF NOT EXISTS expected_arrival date;

COMMENT ON COLUMN public.shipment_received.expected_arrival IS
  'Optional expected arrival / ETA date for an in-flight order (po_draft/po_sent). Drives the inventory at-risk projection; not required.';
