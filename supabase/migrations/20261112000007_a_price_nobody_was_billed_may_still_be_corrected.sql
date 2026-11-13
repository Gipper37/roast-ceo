-- A price nobody was ever billed may still be corrected.
--
-- propagate_price_log_to_orders is the "apply to past orders" true-up: the one
-- deliberate way a price entry reaches orders that already exist. Its target
-- set, from its own WHERE clause, is
--      order_status IN ('Delivered','Shipped')
--  AND invoice_number IS NULL AND invoice_sent_at IS NULL
--  AND shop_order_ref IS NULL AND NOT is_legacy_import
--  AND amount_override IS NULL AND quantity > 0
-- -- history that was delivered and never billed.
--
-- 🔴 EVERY ROW IN THAT SET IS NOW CLOSED. Delivered stamps the document, and
-- prod holds ZERO 'Shipped' orders, so after 20261112000003 the first line the
-- true-up touches raises and the WHOLE price entry rolls back. Not some rows:
-- the entire feature, every time.
--
-- Latent rather than live, which is why this is the last of the four and not
-- the first: backfill_orders has been ticked 0 times in 1,026 prod price-log
-- rows. It fires the first time anyone ticks "true up past orders". I told the
-- owner this one "breaks outright" and cited 379 price changes in 90 days --
-- that counted writes to the trigger's TABLE, not runs of its BODY.
--
-- WHAT IS DELIVERED DOES NOT MOVE; WHAT THEY WERE NEVER CHARGED MAY BE FIXED.
-- The exception is written as a property of the row, not as a sentinel the
-- caller sets, so nothing has to be trusted to be honest about who it is:
--   - quantity, product and the per-line override must not move -- that is
--     what was delivered, and it is a fact about goods in a customer's hands;
--   - the order must never have carried an invoice number, never have been
--     sent, and not be a shop order, whose confirmation email IS the figure
--     the buyer agreed to.
-- So the invariant the database defends is "a figure the customer has seen
-- never moves". The app rule the owner asked for -- editable until delivered
-- or sent -- is stricter than that, and assertInvoiceNotIssued still enforces
-- it, so no screen offers this. The gap is deliberate and is exactly the width
-- of the true-up.

begin;

-- Body is 20261112000003's, with one branch added before the locked-column
-- check and nothing else retyped.
CREATE OR REPLACE FUNCTION public.guard_posted_order_detail_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE v_posted boolean; v_type text;
BEGIN
  v_posted := public.order_document_is_closed(COALESCE(NEW.order_id, OLD.order_id));

  IF NOT COALESCE(v_posted, false) THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'invoice % has gone to the customer — void it or issue a credit memo', OLD.order_id;
  END IF;
  IF TG_OP = 'INSERT' THEN
    -- The one sanctioned append: a late-fee line, inserted by apply_late_fee
    -- in THIS transaction (the sentinel names the order). Product type alone
    -- was spoofable over PostgREST — RLS is tenancy-only (review P1).
    SELECT p.product_type INTO v_type FROM public.products p WHERE p.product_id = NEW.product_id;
    IF v_type = 'ptype_late_fee'
       AND current_setting('app.late_fee_append', true) = NEW.order_id THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'invoice % has gone to the customer — void it or issue a credit memo', NEW.order_id;
  END IF;

  -- Correcting the price of something nobody was ever billed for. What was
  -- delivered is untouched: quantity, product and the override all stand. See
  -- the header — this is the width of the "apply to past orders" true-up and
  -- nothing else, and it is decided from the row, not from a caller's claim.
  IF  NEW.quantity        IS NOT DISTINCT FROM OLD.quantity
  AND NEW.product_id      IS NOT DISTINCT FROM OLD.product_id
  AND NEW.amount_override IS NOT DISTINCT FROM OLD.amount_override
  AND EXISTS (SELECT 1 FROM public.orders o
               WHERE o.order_id = NEW.order_id
                 AND o.invoice_number  IS NULL
                 AND o.invoice_sent_at IS NULL
                 AND o.shop_order_ref  IS NULL
                 AND NOT COALESCE(o.is_legacy_import, false)) THEN
    RETURN NEW;
  END IF;

  -- Every number the invoice shows, not just the net. A discount that can move
  -- while total_price stands still is a silently restated invoice.
  IF (NEW.quantity         IS DISTINCT FROM OLD.quantity)
  OR (NEW.product_id       IS DISTINCT FROM OLD.product_id)
  OR (NEW.total_price      IS DISTINCT FROM OLD.total_price)
  OR (NEW.list_price_total IS DISTINCT FROM OLD.list_price_total)
  OR (NEW.discount_kind    IS DISTINCT FROM OLD.discount_kind)
  OR (NEW.discount_value   IS DISTINCT FROM OLD.discount_value)
  OR (NEW.discount_amount  IS DISTINCT FROM OLD.discount_amount)
  OR (NEW.amount_override  IS DISTINCT FROM OLD.amount_override) THEN
    RAISE EXCEPTION 'invoice % has gone to the customer, so its lines are locked — void it or issue a credit memo', OLD.order_id;
  END IF;
  RETURN NEW;
END;
$function$;

do $$
declare v_n integer;
begin
  -- Still routed through the one helper: the whole reason re-meaning the lock
  -- in 20261112000005 was a one-statement change.
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'guard_posted_order_detail_immutable'
                    and p.prosrc like '%order_document_is_closed%') then
    raise exception 'the detail guard no longer calls the helper';
  end if;

  -- The late-fee append survived the rewrite. It is the other sanctioned path
  -- and retyping this body is exactly how it would be lost.
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'guard_posted_order_detail_immutable'
                    and p.prosrc like '%app.late_fee_append%') then
    raise exception 'the late-fee append was dropped from the detail guard';
  end if;

  -- The true-up still refuses anything that was billed. If its WHERE clause
  -- ever loosened, the exception above would widen with it silently.
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'propagate_price_log_to_orders'
     and p.prosrc like '%o.invoice_number IS NULL%'
     and p.prosrc like '%o.invoice_sent_at IS NULL%'
     and p.prosrc like '%o.shop_order_ref IS NULL%';
  if v_n <> 1 then
    raise exception 'the true-up no longer restricts itself to never-billed orders, so the guard exception no longer matches it';
  end if;
end $$;

commit;
