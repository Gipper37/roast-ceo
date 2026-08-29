-- The "Effective" date on a price becomes true.
--
-- The price editor offers an effective date, and operators reasonably read it
-- as "this price starts then". It did not: sync_product_price_from_log takes
-- the latest log entry by date with no upper bound, so a price dated next
-- month went live the moment it was saved (open-list item, review P2).
--
-- Three pieces:
--   1. sync only considers entries whose date has ARRIVED — the live price is
--      the latest DUE entry. Deleting a staged future entry is a no-op on the
--      live price, exactly as an operator would expect.
--   2. propagation skips future-dated entries at insert (nothing to rewrite
--      yet). A staged entry still correctly ENDS the window of the current
--      price — orders dated on/after the staged date are left for it.
--   3. an hourly pg_cron touch re-fires both triggers for entries that came
--      due (with a 3-day catch-up, and both functions are idempotent absolute
--      derivations, so a double touch is harmless). No new state to track.
--
-- Prod has zero future-dated entries today, so nothing changes retroactively.

begin;

CREATE OR REPLACE FUNCTION public.sync_product_price_from_log()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_product_id   text;
    v_latest_price numeric;
    v_today        date;
BEGIN
    v_product_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.product_id ELSE NEW.product_id END;

    -- "Today" is the FACILITY's today, not the server's. The DB runs UTC,
    -- which is tomorrow from 2pm in Hawaii — a UTC bound would put a staged
    -- price live ten hours early, while the editor still said "staged"
    -- (review P2). Facilities without a timezone fall back to UTC.
    SELECT (now() AT TIME ZONE COALESCE(f.time_zone, 'UTC'))::date
    INTO   v_today
    FROM   public.products p
    LEFT   JOIN public.facilities f ON f.facility_id = p.facility_id
    WHERE  p.product_id = v_product_id;
    v_today := COALESCE(v_today, current_date);

    -- Deleting a STAGED entry (still in the future) can never move the live
    -- price: it never contributed to it. Without this, deleting the only log
    -- entry — a staged one on a product with an otherwise empty log, which is
    -- most of the catalogue — erased the price customers pay today
    -- (review P1).
    IF TG_OP = 'DELETE' AND OLD.date_updated > v_today THEN
        RETURN OLD;
    END IF;

    -- The LIVE price is the latest entry whose effective date has arrived.
    -- Without the date bound, a price staged for next month went live today.
    SELECT price INTO v_latest_price
    FROM public.products_price_log
    WHERE product_id = v_product_id
      AND price > 0
      AND date_updated <= v_today
    ORDER BY date_updated DESC
    LIMIT 1;

    IF v_latest_price IS NULL THEN
        -- No DUE entry. Two very different cases (caught in rehearsal):
        -- entries exist but are all future → the product's current price
        -- stands until they arrive, DON'T null it (many products have a live
        -- price and an empty log — staging one future price must not erase
        -- the price customers pay today). No entries at all → the original
        -- semantics: deleting the last log entry clears the price.
        IF EXISTS (SELECT 1 FROM public.products_price_log
                    WHERE product_id = v_product_id AND price > 0) THEN
            RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
        END IF;
    END IF;

    UPDATE public.products
    SET price = v_latest_price
    WHERE product_id = v_product_id;

    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$function$;

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
      AND  od.amount_override IS NULL;

    RETURN NEW;
END;
$function$;

commit;

-- ── Schedule ───────────────────────────────────────────────────────────────
-- Outside the transaction: cron.schedule commits its own work (same pattern
-- as 20260728000008). The daily wake-up touches date_updated (a
-- self-assignment) on entries that just came due — that column is in both
-- triggers' UPDATE OF lists, so the touch re-runs sync (price goes live) and
-- propagation (windows rewrite). 3-day catch-up in case a run is missed;
-- double application is harmless — both functions are idempotent absolute
-- derivations.
do $do$
BEGIN
  -- pg_cron is installed on prod but NOT on staging (free tier) — same guard
  -- as 20260728000008: the functions above land everywhere, the schedule only
  -- where a cron schema exists.
  IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'cron') THEN
    RAISE NOTICE 'pg_cron not installed — functions created, schedule skipped.';
    RETURN;
  END IF;

  PERFORM cron.unschedule('apply_due_price_log')
    WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'apply_due_price_log');

  -- Hourly, because "midnight" is a different UTC hour per facility timezone.
  -- The touch is idempotent (both triggers are absolute derivations), so a row
  -- being touched repeatedly across its 3-day catch-up window is harmless.
  PERFORM cron.schedule(
    'apply_due_price_log',
    '10 * * * *',
    $cron$update public.products_price_log ppl
       set date_updated = ppl.date_updated
      from public.products p
      left join public.facilities f on f.facility_id = p.facility_id
     where p.product_id = ppl.product_id
       and ppl.price > 0
       and ppl.date_updated <= (now() at time zone coalesce(f.time_zone, 'UTC'))::date
       and ppl.date_updated >  (now() at time zone coalesce(f.time_zone, 'UTC'))::date - 3$cron$
  );
END $do$;
