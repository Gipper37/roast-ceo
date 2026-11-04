-- A delivery zone can say Pickup.
--
-- Owner, 2026-11-03, on invoices and packing slips: "both should have delivery
-- method too. Delivery, pickup, or ship. and that should be prominent."
--
-- An order keyed in by the roaster has no buyer's choice on it
-- (orders.fulfillment_method is NULL on 15,942 of 15,944), so its zone is the only
-- thing that can answer, and a zone could only say delivery or shipping. MCR runs
-- zones named "Pick-Up" and "Ship", both 'delivery', because there was nothing else
-- to pick for the first and nobody had flipped the second. Reading the zone's NAME
-- would have made this work for exactly one roaster.
--
-- 'pickup' schedules the way 'delivery' does: the frontend's route readers ask
-- "not shipping" now, so flipping a zone to pickup moves nothing off the day views.
-- Only what a document says changes. No SQL function reads this column.

alter table public.sales_area drop constraint sales_area_fulfillment_method_check;
alter table public.sales_area add constraint sales_area_fulfillment_method_check
  check (fulfillment_method = any (array['delivery'::text, 'shipping'::text, 'pickup'::text]));
