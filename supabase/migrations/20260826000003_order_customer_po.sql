-- The customer's PO number on the order.
--
-- Wholesale buyers with any purchasing process issue a PO and expect it quoted
-- back on the invoice -- restaurants, hotels, hospitals, universities, anyone
-- whose AP department matches invoice to PO before it pays. Without it the
-- invoice lands on a desk that cannot match it, and payment waits.
--
-- NOT the same as shipment_received.po_number, which already exists and points
-- the OTHER WAY: that is the PO the roaster issues to a green-coffee supplier.
-- This is the one the customer issues to the roaster. Same words, opposite
-- direction, so they stay separate columns on separate tables.
--
-- Free text on purpose. A PO number is the customer's identifier, not ours: it
-- is whatever their system emits, and validating its shape would only reject
-- the real ones.
--
-- Tracking is deliberately absent from this migration -- orders.tracking_number
-- and orders.carrier already exist and are already written by the Delivery >
-- Shipping view. They only ever needed surfacing, which is a frontend change.

begin;

alter table public.orders
  add column if not exists customer_po text;

comment on column public.orders.customer_po is
  'PO number the CUSTOMER issued for this order, quoted back on the invoice so '
  'their AP can match it. Distinct from shipment_received.po_number, which is '
  'the PO this roaster issues to a supplier.';

commit;
