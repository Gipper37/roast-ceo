-- Make item_status default to 'Open' at the DB level so newly-inserted
-- order_details rows can never silently land with NULL item_status
-- regardless of which code path created them. The application code is
-- also being updated to set item_status: 'Open' explicitly on every
-- insert site (createOrder, addLineItem, duplicateOrder, shop checkout)
-- — this default is a backstop for future paths that forget.
--
-- Backfill any existing NULL rows in the same migration so the totals
-- view (which filters on item_status='Open'/'Packed') stops dropping
-- legitimate open orders from its aggregates.

-- 1. Backfill existing NULLs based on the parent order's status
UPDATE order_details od
SET item_status = CASE
  WHEN o.order_status = 'Packed' THEN 'Packed'
  WHEN o.order_status = 'Delivered' THEN 'Packed'
  WHEN o.order_status = 'Canceled' THEN 'Open'
  ELSE 'Open'
END
FROM orders o
WHERE od.order_id = o.order_id
  AND od.item_status IS NULL;

-- 2. Add the default so future inserts always get a value
ALTER TABLE order_details ALTER COLUMN item_status SET DEFAULT 'Open';
