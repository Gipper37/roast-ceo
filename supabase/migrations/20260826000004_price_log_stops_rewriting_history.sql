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
-- REMOVED, not fixed: the facility filter, in both the window lookup and the
-- UPDATE. It could never do any work. products.facility_id already pins a
-- product to exactly one facility, so `od.product_id = NEW.product_id` has
-- already constrained the facility before the clause is reached. Verified on
-- prod: of 865 price entries, all 851 that name a facility name their own
-- product's and none disagree; and of 36,891 order lines across all five
-- tenants, ZERO are cross-facility.
--
-- Two earlier attempts at "fixing" it were both worse than deleting it.
-- Matching NULL-to-NULL matched nothing, because every order carries a
-- facility_id. Deriving the facility from the product compared the order's
-- HISTORICAL facility against the product's CURRENT one, so moving a product
-- between facilities would have silently stopped every historical correction
-- for it -- a redundant clause traded for a latent one.
--
-- In the window lookup the same redundancy was not merely inert, it was a bug:
-- NULL-to-NULL matching meant a facility-less entry could not see a SCOPED
-- entry as its window end, so its validity window ran past a later price
-- change. Exactly one product in the database hits it, and its older entry is
-- priced 0.00 and early-returns, so nothing was miscalculated in practice.
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
    -- the date_updated of the next price log entry for this product.
    -- Scoped by PRODUCT only -- see the header note on why facility cannot
    -- narrow anything a product_id match has not already narrowed.
    SELECT MIN(ppl.date_updated) INTO v_date_end
    FROM public.products_price_log ppl
    WHERE ppl.product_id    = NEW.product_id
      AND ppl.price_log_id <> NEW.price_log_id
      AND ppl.date_updated  > NEW.date_updated;

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
               SELECT p2.product_type FROM public.products p2
               WHERE p2.product_id = NEW.product_id
           ) prod ON true
           LEFT JOIN public.product_type pt
               ON pt.product_type_id = prod.product_type
    WHERE  od.order_id    = o.order_id
      AND  od.product_id  = NEW.product_id
      AND  o.order_status <> 'Canceled'
      AND  o.order_date   >= NEW.date_updated
      AND  (v_date_end IS NULL OR o.order_date < v_date_end)
      AND  COALESCE(od.quantity, 0) > 0
      -- The four guards.
      AND  NOT COALESCE(o.is_legacy_import, false)
      AND  NOT COALESCE(o.posted, false)
      AND  od.amount_override IS NULL;

    RETURN NEW;
END;
$function$;

commit;
