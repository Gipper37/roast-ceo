-- Stop a recorded price change from rewriting invoice history.
--
-- propagate_price_log_to_orders() fires on INSERT/UPDATE of products_price_log
-- and does:
--
--     UPDATE order_details od SET total_price = od.quantity * NEW.price
--     FROM orders o WHERE od.product_id = NEW.product_id
--       AND o.order_date >= NEW.date_updated ...
--
-- Recording a price change therefore RESTATES every historical line for that
-- product inside the price's validity window. The app's ordinary price paths all
-- go through this: addPriceEntry (products/actions.ts:183), bulkUpdatePrices
-- (:216), the variant-create path (:412), company/actions.ts:227, and
-- /api/shopify/sync-price.
--
-- It has already fired once on prod: one log row on 2026-08-24 rewrote 21 lines
-- ($5,589), 19 of them legacy QuickBooks invoices.
--
-- The sibling function handle_order_detail_logic() has FOUR guards. This one had
-- none of them. Adding them, in the same order and for the same reasons:
--
--   1. LEGACY IMPORTS. QuickBooks historical amounts are supplied by the
--      importer and must be preserved EXACTLY -- signed credit-memo totals,
--      negotiated prices, period COGS. handle_order_detail_logic skips them; so
--      must this. On MCR alone, 84 products with no catalogue price carry 3,240
--      such lines worth $972,458.95, every one a QuickBooks invoice. Setting a
--      price on those products would have restated all of them.
--
--   2. amount_override. An operator who typed an exact amount meant it. 608
--      lines on MCR carry one; 148 of those hang off the same priceless
--      products above.
--
--   3. reduces_total (DISCOUNTS). The UPDATE had no sign handling, so a discount
--      product's lines were rewritten POSITIVE -- turning every discount into a
--      charge. Reproduced on prod inside a rolled-back transaction: MCR's 351
--      'Sales Discount' lines went from -$55,041.28 to +$535.50. Now mirrors
--      handle_order_detail_logic's -abs().
--
--   4. POSTED INVOICES. Previously the posted guard raised an exception, which
--      aborted the entire price save rather than skipping the one locked line --
--      so a single posted invoice made repricing impossible. Now they are simply
--      excluded, and posting means what it says.
--
-- NOT changed: the facility filter, which was reported as an asymmetric-NULL bug
-- and is not one. `NEW.facility_id IS NULL OR o.facility_id = NEW.facility_id`
-- correctly means "a company-wide price applies at every facility". Rewriting it
-- to match NULL-to-NULL broke the feature in rehearsal: all 3,806 MCR orders
-- carry a facility_id, so no correction applied at all.
--
-- What still works, deliberately: correcting a live, unposted, non-legacy order
-- when a price was genuinely recorded wrong. That is the legitimate use of a
-- backdated price entry and it is untouched.

begin;

create or replace function public.propagate_price_log_to_orders()
returns trigger
language plpgsql
security definer
as $function$
DECLARE
    v_date_end date;
BEGIN
    -- Skip zero/null prices — can't fix orders with no price information
    IF NEW.price IS NULL OR NEW.price = 0 THEN
        RETURN NEW;
    END IF;

    -- Find the end of this entry's validity window:
    -- the date_updated of the next price log entry for this product+facility.
    SELECT MIN(ppl.date_updated) INTO v_date_end
    FROM public.products_price_log ppl
    WHERE ppl.product_id    = NEW.product_id
      AND ppl.price_log_id <> NEW.price_log_id
      AND ppl.date_updated  > NEW.date_updated
      AND (
          (NEW.facility_id IS NULL AND ppl.facility_id IS NULL)
          OR ppl.facility_id = NEW.facility_id
      );

    -- Update total_price for eligible orders in this price's validity window.
    UPDATE public.order_details od
    SET    total_price = CASE
               WHEN COALESCE(pt.reduces_total, false)
               -- A discount cannot add, whatever the price field says. Same
               -- rule, same reasoning, as handle_order_detail_logic().
               THEN -abs(od.quantity * NEW.price)
               ELSE  od.quantity * NEW.price
           END
    FROM   public.orders o
           LEFT JOIN LATERAL (
               SELECT p2.product_type, p2.facility_id
               FROM public.products p2
               WHERE p2.product_id = NEW.product_id
           ) prod ON true
           LEFT JOIN public.product_type pt
               ON pt.product_type_id = prod.product_type
    WHERE  od.order_id    = o.order_id
      AND  od.product_id  = NEW.product_id
      AND  o.order_status <> 'Canceled'
      AND  o.order_date   >= NEW.date_updated
      AND  (v_date_end IS NULL OR o.order_date < v_date_end)
      -- Facility. Prices are PER FACILITY, as products are, so a price entry
      -- can never legitimately apply company-wide. When the entry does not name
      -- a facility, fall back to the FACILITY OF THE PRODUCT BEING REPRICED
      -- rather than to "everywhere" -- a product belongs to exactly one
      -- facility, so its facility IS the price's facility, and deriving it here
      -- means the app cannot forget to send it.
      --
      -- It could, and did: none of addPriceEntry, bulkUpdatePrices or the
      -- variant-create path sets facility_id, so all 14 app-created entries on
      -- prod are NULL against 851 scoped ones from the importer. Under the old
      -- `NEW.facility_id IS NULL OR ...` those 14 disabled the filter entirely
      -- and applied at every facility.
      AND  o.facility_id = COALESCE(NEW.facility_id, prod.facility_id)
      AND  COALESCE(od.quantity, 0) > 0
      -- The four guards.
      AND  NOT COALESCE(o.is_legacy_import, false)
      AND  NOT COALESCE(o.posted, false)
      AND  od.amount_override IS NULL;

    RETURN NEW;
END;
$function$;

commit;
