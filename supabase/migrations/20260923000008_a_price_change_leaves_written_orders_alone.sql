-- Entering a price stops rewriting orders that already exist.
--
-- propagate_price_log_to_orders repriced every order DATED inside a new
-- price's effective window. For a price starting today that is harmless --
-- no order is dated in the future. For a BACK-DATED price it silently
-- rewrote history, and back-dating is routine: it is how you correct a price
-- you forgot to enter.
--
-- The owner, on being shown what it does: "we don't want to touch existing
-- orders in the normal case. the only case that was meant for was for truing
-- up inaccurate history." So the capability stays and the default flips. An
-- order is locked at creation; truing up history is a thing you ask for.
--
-- WHAT THIS CHANGES IN PRACTICE. Nothing, for a price that starts today or
-- later. Everything, for a back-dated one: it now does nothing unless the
-- entry says backfill_orders.
--
-- THE FIFTH GUARD. The function skipped `posted` orders, and `posted` is the
-- immutability lock rather than "invoiced". At MCR 3,761 orders carry an
-- invoice number and only 203 are posted -- 201 of those stamped by the
-- QuickBooks importer, with exactly ONE invoice ever sent from STRATA. So
-- 3,558 invoiced orders were repriceable. Now nothing with an invoice number
-- moves, whatever the flag says: a figure a customer has already been sent
-- must never change underneath them.
--
-- KNOWN BEHAVIOUR CHANGE, deliberate and flagged to the owner: a FUTURE-dated
-- price that comes due no longer reprices orders already drafted into its
-- window. The hourly cron still re-fires this trigger, it just declines to act
-- unless asked. If pre-drafted orders should follow a staged price, the entry
-- that stages it sets backfill_orders -- which is the same explicit act.

begin;

alter table public.products_price_log
  add column if not exists backfill_orders boolean not null default false;

comment on column public.products_price_log.backfill_orders is
  'Deliberately rewrite orders already dated inside this price''s window. Default false: an order is locked at creation. Only for truing up history, and never touches an invoiced order.';

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
               WHEN od.discount_kind IS NOT NULL AND COALESCE(od.discount_value, 0) > 0
                   THEN least(od.discount_value, abs(od.quantity * NEW.price))
               ELSE 0
           END,
           total_price        = (CASE WHEN v_reduces
                                      THEN -abs(od.quantity * NEW.price)
                                      ELSE  od.quantity * NEW.price END)
                                - (CASE WHEN v_reduces THEN -1 ELSE 1 END) * (CASE
               WHEN od.discount_kind = 'percent' AND COALESCE(od.discount_value, 0) > 0
                   THEN round(abs(od.quantity * NEW.price) * od.discount_value / 100.0, 2)
               WHEN od.discount_kind IS NOT NULL AND COALESCE(od.discount_value, 0) > 0
                   THEN least(od.discount_value, abs(od.quantity * NEW.price))
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
      AND  o.invoice_number IS NULL;

    RETURN NEW;
END;
$function$;

do $$
declare
  v_src text;
begin
  select prosrc into v_src from pg_proc
  where oid = 'public.propagate_price_log_to_orders()'::regprocedure;

  if position('backfill_orders' in v_src) = 0 then
    raise exception 'the opt-in guard is not in propagate_price_log_to_orders';
  end if;
  if position('o.invoice_number IS NULL' in v_src) = 0 then
    raise exception 'the invoice guard is not in propagate_price_log_to_orders';
  end if;

  -- The trigger must still be attached, or this all does nothing quietly.
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.products_price_log'::regclass
      and tgname = 'trg_propagate_price_log_to_orders'
  ) then
    raise exception 'trg_propagate_price_log_to_orders is missing';
  end if;
end $$;

commit;
