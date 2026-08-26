-- Drop the facility scoping from propagate_price_log_to_orders(), in both the
-- window lookup and the UPDATE. It could never do any work.
--
-- products.facility_id already pins a product to exactly one facility, so
-- `od.product_id = NEW.product_id` has constrained the facility before either
-- clause is reached. Verified on prod:
--   * of 865 price entries, all 851 that name a facility name their own
--     product's facility, and NONE disagrees;
--   * of 36,891 order lines across all five tenants, ZERO are cross-facility.
--
-- Two earlier attempts at "fixing" this clause were both worse than deleting it,
-- and 20260826000004 shipped the second of them:
--
--   Matching NULL-to-NULL matched nothing, because every order carries a
--   facility_id -- so no correction applied at all.
--
--   Deriving the facility from the product (what 000004 actually did) compares
--   the order's HISTORICAL facility against the product's CURRENT one. Move a
--   product between facilities and every historical correction for it silently
--   stops applying. A redundant clause traded for a latent one. That is what
--   this migration removes.
--
-- In the WINDOW lookup the same redundancy was not merely inert, it was a real
-- bug: NULL-to-NULL matching meant a facility-less entry could not see a SCOPED
-- entry as its window end, so its validity window ran past a later price change
-- and covered dates that the later price already governed. Exactly one product
-- in the database hits it, and its older entry is priced 0.00 and early-returns,
-- so nothing was miscalculated in practice.
--
-- The four guards added in 000004 -- legacy imports, amount_override,
-- reduces_total, posted -- are unchanged and still the point of the function.

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

    -- End of this entry's validity window: the date_updated of the next price
    -- log entry for this product. Scoped by PRODUCT only — see the header note
    -- on why facility cannot narrow what a product_id match already narrowed.
    SELECT MIN(ppl.date_updated) INTO v_date_end
    FROM public.products_price_log ppl
    WHERE ppl.product_id    = NEW.product_id
      AND ppl.price_log_id <> NEW.price_log_id
      AND ppl.date_updated  > NEW.date_updated;

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
      -- The four guards from 000004, unchanged.
      AND  NOT COALESCE(o.is_legacy_import, false)
      AND  NOT COALESCE(o.posted, false)
      AND  od.amount_override IS NULL;

    RETURN NEW;
END;
$function$;

commit;
