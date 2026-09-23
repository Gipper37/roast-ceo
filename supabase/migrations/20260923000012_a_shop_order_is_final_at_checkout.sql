-- A shop order is final at checkout.
--
-- The last hole in this guard set, and the one the previous seven could not
-- see. A storefront order sends its confirmation from the checkout itself,
-- via sendOrderConfirmationEmail -- not through the invoice paths -- so it
-- never stamps invoice_sent_at. Once such an order reaches Delivered it would
-- have satisfied every other condition here: opted in, finished, no invoice
-- number, nothing "sent".
--
-- But the buyer was shown a total, accepted it, and in the card flow has
-- already been charged. There is no reading under which that price may later
-- move. The owner: "order confirmation from the shop is a final."
--
-- Preventative rather than corrective: exactly one shop order exists in the
-- whole database today, at Social Hour, and it is not delivered. The point is
-- that it cannot bite later.
--
-- That completes the set. A price may rewrite a written order only when
-- somebody asked for it, the order is finished, and nobody has ever been told
-- what it costs -- by invoice, by email, or at a checkout.

begin;

CREATE OR REPLACE FUNCTION public.propagate_price_log_to_orders()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_date_end date;
    v_reduces  boolean;
    v_today    date;
BEGIN
    -- An order is LOCKED AT CREATION. Entering a price must not reach back and
    -- rewrite orders that already exist -- that is the owner's instruction and
    -- it is the safe default: "we don't want to touch existing orders in the
    -- normal case."
    --
    -- This function still exists, because the case it was written for is real:
    -- "the only case that was meant for was for truing up inaccurate history."
    -- That is now something you ASK for on the price entry, once, deliberately,
    -- rather than something every price change does silently.
    IF NOT COALESCE(NEW.backfill_orders, false) THEN
        RETURN NEW;
    END IF;

    -- Skip zero/null prices — can't fix orders with no price information
    IF NEW.price IS NULL OR NEW.price = 0 THEN
        RETURN NEW;
    END IF;

    -- A future-dated entry is STAGED, not live: there is nothing to rewrite
    -- yet. The hourly cron touches the row when its date arrives and this
    -- trigger runs again, then against real orders in its window. "Future" is
    -- judged in the FACILITY's timezone, same as the sync trigger.
    SELECT (now() AT TIME ZONE COALESCE(f.time_zone, 'UTC'))::date
    INTO   v_today
    FROM   public.products p
    LEFT   JOIN public.facilities f ON f.facility_id = p.facility_id
    WHERE  p.product_id = NEW.product_id;
    IF NEW.date_updated > COALESCE(v_today, current_date) THEN
        RETURN NEW;
    END IF;

    -- End of this entry's validity window: the date_updated of the next price
    -- log entry for this product. Scoped by PRODUCT only — see the header note
    -- on why facility cannot narrow what a product_id match already narrowed.
    -- A staged future entry correctly ends the window: orders dated on/after
    -- it belong to the staged price, applied when it comes due.
    SELECT MIN(ppl.date_updated) INTO v_date_end
    FROM public.products_price_log ppl
    WHERE ppl.product_id    = NEW.product_id
      AND ppl.price_log_id <> NEW.price_log_id
      AND ppl.date_updated  > NEW.date_updated;

    SELECT COALESCE(pt.reduces_total, false) INTO v_reduces
    FROM   public.products p
    LEFT   JOIN public.product_type pt ON pt.product_type_id = p.product_type
    WHERE  p.product_id = NEW.product_id;

    -- One direction, same as handle_order_detail_logic: the new price is the
    -- LIST unit; list, discount and net derive from it.
    UPDATE public.order_details od
    SET    unit_price_at_sale = CASE WHEN v_reduces THEN -abs(NEW.price) ELSE NEW.price END,
           list_price_total   = CASE WHEN v_reduces
                                     THEN -abs(od.quantity * NEW.price)
                                     ELSE  od.quantity * NEW.price END,
           discount_amount    = CASE
               WHEN od.discount_kind = 'percent' AND COALESCE(od.discount_value, 0) > 0
                   THEN round(abs(od.quantity * NEW.price) * od.discount_value / 100.0, 2)
               -- 'price' is what they PAY per unit; the discount is the rest.
               -- A price of 0.00 is a free item, so this arm deliberately does
               -- not require value > 0.
               WHEN od.discount_kind = 'price'
                   THEN greatest(0, round(abs(od.quantity * NEW.price)
                                          - (od.discount_value * od.quantity), 2))
               -- 'amount' is PER UNIT, matching handle_order_detail_logic.
               WHEN od.discount_kind IS NOT NULL AND COALESCE(od.discount_value, 0) > 0
                   THEN least(od.discount_value * od.quantity, abs(od.quantity * NEW.price))
               ELSE 0
           END,
           total_price        = (CASE WHEN v_reduces
                                      THEN -abs(od.quantity * NEW.price)
                                      ELSE  od.quantity * NEW.price END)
                                - (CASE WHEN v_reduces THEN -1 ELSE 1 END) * (CASE
               WHEN od.discount_kind = 'percent' AND COALESCE(od.discount_value, 0) > 0
                   THEN round(abs(od.quantity * NEW.price) * od.discount_value / 100.0, 2)
               -- 'price' is what they PAY per unit; the discount is the rest.
               -- A price of 0.00 is a free item, so this arm deliberately does
               -- not require value > 0.
               WHEN od.discount_kind = 'price'
                   THEN greatest(0, round(abs(od.quantity * NEW.price)
                                          - (od.discount_value * od.quantity), 2))
               -- 'amount' is PER UNIT, matching handle_order_detail_logic.
               WHEN od.discount_kind IS NOT NULL AND COALESCE(od.discount_value, 0) > 0
                   THEN least(od.discount_value * od.quantity, abs(od.quantity * NEW.price))
               ELSE 0
           END)
    FROM   public.orders o
    WHERE  od.order_id    = o.order_id
      AND  od.product_id  = NEW.product_id
      AND  o.order_status <> 'Canceled'
      AND  o.order_date   >= NEW.date_updated
      AND  (v_date_end IS NULL OR o.order_date < v_date_end)
      AND  COALESCE(od.quantity, 0) > 0
      -- The four guards from 000004, unchanged.
      AND  NOT COALESCE(o.is_legacy_import, false)
      AND  NOT COALESCE(o.posted, false)
      AND  od.amount_override IS NULL
      -- And a fifth. `posted` is the immutability LOCK, not "invoiced": at MCR
      -- 3,761 orders carry an invoice number and only 203 are posted -- 201 of
      -- those by the QuickBooks importer, with exactly ONE invoice ever sent
      -- from STRATA. So `NOT posted` was protecting almost nothing. Anything
      -- you have invoiced is now off limits regardless, because a figure a
      -- customer has already been sent must never move underneath them.
      AND  o.invoice_number IS NULL
      -- And a sixth. A true-up is for HISTORY. An order still Open or Packed
      -- has not happened yet, and repricing a live order underneath the person
      -- working it is not correcting history, it is changing a commitment.
      --
      -- The split on MCR's own data is exact: the 40 uninvoiced orders dated
      -- before their invoicing cutover are all Delivered, spanning Jun 2025 to
      -- Jun 2026 -- genuinely historical, never invoiced, and precisely what
      -- this function exists for. The 100 uninvoiced orders after it are all
      -- Open, dated Aug-Sep 2026. Forty in, one hundred out.
      --
      -- Allow-list rather than `<> 'Open'`: a status added later should have to
      -- be let in deliberately, not inherit permission to rewrite money.
      AND  o.order_status IN ('Delivered', 'Shipped')
      -- And a seventh. The owner assumed emailing an invoice locked the order.
      -- It does not: finalize_invoice is what locks, and the send path has a
      -- fallback --
      --   invoiceNumber: order.invoice_number ?? order.shop_order_ref ?? order.order_id
      -- so a document with a total on it can be emailed to a customer for an
      -- order that was never finalized, and nothing about it was locked.
      --
      -- invoice_sent_at IS stamped on every send path, so it is the honest
      -- record of "this figure has been in front of a customer". A number
      -- somebody has been sent must never move, finalized or not.
      AND  o.invoice_sent_at IS NULL
      -- And the last one. A shop order is FINAL at checkout: the buyer was
      -- shown a total, agreed to it, and in the card flow has already paid.
      -- sendOrderConfirmationEmail goes out from the checkout itself, and it
      -- does NOT stamp invoice_sent_at -- that column belongs to the invoice
      -- paths -- so a delivered shop order would otherwise have satisfied
      -- every other guard here.
      --
      -- The owner: "order confirmation from the shop is a final."
      AND  o.shop_order_ref IS NULL;

    RETURN NEW;
END;
$function$;;

do $$
declare
  v_src text;
  g     text;
begin
  select prosrc into v_src from pg_proc
  where oid = 'public.propagate_price_log_to_orders()'::regprocedure;

  -- Every guard, by name. Each exists because something real got through, and
  -- a future rewrite that drops one silently reopens that hole.
  foreach g in array array[
    'backfill_orders',                          -- 000008 opt-in
    'o.invoice_number IS NULL',                 -- 000008 invoiced
    'order_status IN (''Delivered'', ''Shipped'')', -- 000010 live orders
    'o.invoice_sent_at IS NULL',                -- 000011 sent figures
    'o.shop_order_ref IS NULL'                  -- 000012 shop orders
  ] loop
    if position(g in v_src) = 0 then
      raise exception 'guard lost from propagate_price_log_to_orders: %', g;
    end if;
  end loop;

  if (length(v_src) - length(replace(v_src, 'od.discount_kind = ''price''', '')))
     / length('od.discount_kind = ''price''') <> 2 then
    raise exception 'the price arm from 000009 was lost from one of the two CASEs';
  end if;
end $$;

commit;
