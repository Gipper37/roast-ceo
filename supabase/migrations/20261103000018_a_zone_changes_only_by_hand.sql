-- A delivery zone changes only by hand.
--
-- THE HOLE. update_order_metrics set NEW.area from the customer on every write to
-- orders, whatever the write was. So:
--
--   * Any save could move an order onto or off a route: a PO, a delivery method, a
--     line edit (update_order_aggregates writes the header), a status change.
--   * An old delivered order's zone was rewritten by any later save, once its
--     customer had changed zones.
--   * An override on an order could not stick. The Delivery Zone picker in Edit
--     Order wrote the value and this trigger overwrote it in the same statement.
--
-- WHAT CHANGES. Only the lines that set NEW.area, from pg_get_functiondef with
-- staging and prod byte-identical:
--
--   * INSERT: a null area takes the customer's zone. A named area stays, so the New
--     Order form's override now sticks, and a reissue keeps the original's zone.
--   * UPDATE: area is left alone unless customer_id changes. A change of customer,
--     which includes a customer merge, takes the new customer's zone.
--
-- THE NEW COLUMN. orders.area_set_by_hand says somebody chose this order's zone apart
-- from its customer's. It cannot be worked out from the zone:
--
--   * No zone, chosen in Edit Order, looks like an order that never had one, and a
--     customer's next move would put it back on a route.
--   * An order overridden to Y whose customer then moved to Y looks like one that
--     followed them, and their next move would take it along.
--   * An order reopened after its customer moved sits on a zone they left, which looks
--     like an override nobody made, and no later move would reach it.
--
-- Only the Edit Order picker and the New Order form's override set it. A change of
-- customer clears it, because whatever was chosen was chosen for the old one. An INSERT
-- that says it by hand with a null area keeps the null, which is a reissue of an order
-- somebody took off its zone. Nothing to backfill: on prod 0 open or packed orders
-- differ from their customer's zone (3 Nov 2026), so false is true of all of them.
--
-- Everything else this function derives is untouched: customer_category, the totals
-- from the lines, and the order interval. The read of the customer stays where it
-- was because customer_category needs it, and it still goes through the order's
-- facility, so an order at another facility from its customer finds no zone.
--
-- WHAT IT WOULD HAVE REWRITTEN. Measured on prod 2026-11-03, the customer read
-- through the order's facility as this function reads it. 3,704 of 15,945 orders
-- have an area that differs from their customer's zone, so the next save on any of
-- them would have changed it:
--
--   * 3,703 are NULL becoming the customer's zone: 3,684 at MCR, 19 at R7CbqHmA1j.
--   * 1 is one zone becoming another, at R7CbqHmA1j.
--   * 0 lose a zone.
--   * All 3,704 are Delivered. 0 are Open or Packed.
--
-- NOTHING IS BACKFILLED. Those rows keep what they have. The delivery tabs read the
-- order's own zone and nothing else, because a null area on an open order with a
-- zoned customer now means somebody took it off its zone. The documents read the
-- order's zone and then the customer's. 27 open or packed orders have a null area on
-- prod today, and none of their customers has a zone, so nothing changes for them
-- until somebody gives that customer one by hand, which moves them.
--
-- ORDER. This ships before the frontend. The frontend that comes with it saves an
-- override on the order and moves open orders when a customer's zone changes, and
-- under the old trigger an override would be overwritten while its delivery date
-- was kept.

begin;

alter table public.orders
  add column if not exists area_set_by_hand boolean not null default false;

comment on column public.orders.area_set_by_hand is
  'Somebody chose this order''s zone apart from its customer''s, No zone included. A move of the customer leaves it alone. Set by Edit Order and the New Order override, cleared by a change of customer.';

CREATE OR REPLACE FUNCTION public.update_order_metrics()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    prev_date DATE;
    v_cat TEXT;
    v_area TEXT;
    v_facility_id TEXT;
BEGIN
    -- 0. Identify Facility
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    -- 1. Grab from Customer record (Isolated by Facility)
    SELECT customer_category, sales_area
    INTO v_cat, v_area
    FROM customers
    WHERE customer_id = NEW.customer_id
      AND facility_id = v_facility_id;

    NEW.customer_category := v_cat;
    -- A zone changes only by hand: on the customer, or overridden on the order.
    -- An order takes its customer's zone when it is created with none, and when
    -- it changes customer. Any other write leaves it alone.
    IF TG_OP = 'INSERT' THEN
        IF NEW.area IS NULL AND NOT NEW.area_set_by_hand THEN
            NEW.area := v_area;
        END IF;
    ELSIF NEW.customer_id IS DISTINCT FROM OLD.customer_id THEN
        NEW.area := v_area;
        NEW.area_set_by_hand := false;
    END IF;

    -- 2. Sum up totals from "Order Details" so the header stays in sync with the
    --    lines. SKIPPED for opening-balance stubs, which are line-less and carry
    --    the imported open balance in order_total already.
    IF NOT COALESCE(NEW.is_opening_balance, false) THEN
        SELECT
            COALESCE(SUM(total_price), 0),
            COALESCE(SUM(roasted_weight), 0)
        INTO NEW.order_total, NEW.total_weight
        FROM order_details
        WHERE order_id = NEW.order_id;
    END IF;

    -- 3. Find previous order date for interval calculation (Isolated by Facility)
    SELECT MAX(order_date) INTO prev_date
    FROM orders
    WHERE customer_id = NEW.customer_id
      AND order_date < NEW.order_date
      AND order_status != 'Canceled'
      AND facility_id = v_facility_id;

    -- 4. Calculate interval math
    IF prev_date IS NOT NULL THEN
        NEW.interval_days := (NEW.order_date - prev_date);
        NEW.interval_wks := GREATEST(1, ROUND(CAST((NEW.order_date - prev_date) AS numeric) / 7.0, 1));
    ELSE
        NEW.interval_days := 0;
        NEW.interval_wks := 0;
    END IF;

    RETURN NEW;
END;
$function$;

commit;
