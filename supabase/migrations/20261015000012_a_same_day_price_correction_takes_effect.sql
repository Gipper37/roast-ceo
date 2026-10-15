-- A same-day price correction takes effect.
--
-- THE BUG. `sync_product_price_from_log` resolves the live price with
--
--     ORDER BY date_updated DESC LIMIT 1
--
-- and `date_updated` is a DATE. Two entries on the same effective date are
-- tied, and a tied ORDER BY in Postgres returns whichever row the scan reached
-- first -- nothing in the plan makes that the newer one. So the single most
-- ordinary price edit there is, "I typed 62.50, I meant 52.50, fix it now",
-- lands a second entry on today's date and then resolves to EITHER row. The
-- roaster sees the correction appear in the price log and the price on the
-- product NOT change, with no error and nothing to click. Re-reading can even
-- flip the answer, because a different plan reaches a different row first.
--
-- Found while building the pack-count rescale in `updateProduct`: changing a
-- Case of 12 to a plain bag wrote the restated per-unit price into the log
-- correctly (20) and left `products.price` reading the stale case price (300),
-- because the restated entry tied with the one it was restating.
--
-- THE FIX. Break the tie by when the row was WRITTEN. `created_at` is set on
-- every insert by `handle_new_record` (BEFORE INSERT, and it fires before this
-- AFTER trigger reads the table), so every row written by any of the eight
-- call sites that insert here carries one, whether or not the caller passed it.
--
-- NULLS LAST is deliberate and it is not a formality: 415 of prod's 1,007
-- entries have `created_at` NULL, all of them dated 2020-01-01..2026-05-21 --
-- the AppSheet-era import, written before the audit trigger existed. A NULL
-- created_at means "older than the trigger", so on a shared date it must LOSE
-- to a row that carries a timestamp. Sorting NULLs first would let a 2020
-- import outrank today's correction.
--
-- `price_log_id` settles what is left. It is a UUID, so it is not
-- chronological and is not pretending to be; its job is that two rows which
-- tie on both date and timestamp resolve the SAME WAY on every read, instead
-- of the answer changing with the plan. The rows that can reach it are two
-- historical imports sharing a date -- frozen history nobody is correcting.
--
-- 🔴 Function patched from `pg_get_functiondef`, not retyped: the body carries
-- the facility-timezone resolution and the two staged-entry guards from the
-- earlier review (P1/P2), and retyping it is how those get silently dropped.
-- The ORDER BY is the only line that differs.
--
-- EFFECT ON PROD TODAY: none. 29 same-date groups exist, 24 of them agree on
-- price; the other 5 are mid-history ties, not the newest due entry, so no
-- product's live price moves. The fix is for the next correction, not for a
-- backlog.

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
    -- which is tomorrow from 2pm in Hawaii: a UTC bound would put a staged
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
    -- entry (a staged one on a product with an otherwise empty log, which is
    -- most of the catalogue) erased the price customers pay today (review P1).
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
    -- 🔴 date_updated is a DATE, so same-day entries tie, and a tied ORDER BY
    -- returns whatever the scan reaches first. created_at breaks it (set for
    -- every row by handle_new_record); NULLS LAST keeps a pre-trigger import
    -- from outranking today's edit; price_log_id makes the remainder stable
    -- rather than plan-dependent. See this migration's header.
    ORDER BY date_updated DESC, created_at DESC NULLS LAST, price_log_id DESC
    LIMIT 1;

    IF v_latest_price IS NULL THEN
        -- No DUE entry. Two very different cases (caught in rehearsal):
        -- entries exist but are all future -> the product's current price
        -- stands until they arrive, DON'T null it (many products have a live
        -- price and an empty log, and staging one future price must not erase
        -- the price customers pay today). No entries at all -> the original
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

-- Verify against the TABLES, not by calling the function: this is a trigger
-- function, it cannot be invoked directly, and a verify block that compares
-- two NULLs passes while proving nothing (done that -- see 20261015000010).
-- So: build a tied pair in a temp table and check the ordering picks the
-- later-written row.
do $verify$
DECLARE
    v_pick numeric;
BEGIN
    CREATE TEMP TABLE _tie(price numeric, date_updated date,
                           created_at timestamp, price_log_id text) ON COMMIT DROP;
    INSERT INTO _tie VALUES
      (62.50, '2026-10-15', '2026-10-15 01:00:00', 'aaa'),  -- the mistake
      (52.50, '2026-10-15', '2026-10-15 01:05:00', 'zzz'),  -- the correction
      (49.00, '2026-05-01', NULL,                  'mmm');  -- an old import

    SELECT price INTO v_pick FROM _tie
    WHERE price > 0 AND date_updated <= '2026-10-15'::date
    ORDER BY date_updated DESC, created_at DESC NULLS LAST, price_log_id DESC
    LIMIT 1;
    IF v_pick IS DISTINCT FROM 52.50 THEN
        RAISE EXCEPTION 'same-day tie resolved to %, expected the correction 52.50', v_pick;
    END IF;

    -- A pre-trigger import must lose its own date to a timestamped row, even
    -- when its uuid sorts higher.
    INSERT INTO _tie VALUES
      (99.00, '2026-10-15', NULL, 'zzzz');
    SELECT price INTO v_pick FROM _tie
    WHERE price > 0 AND date_updated <= '2026-10-15'::date
    ORDER BY date_updated DESC, created_at DESC NULLS LAST, price_log_id DESC
    LIMIT 1;
    IF v_pick IS DISTINCT FROM 52.50 THEN
        RAISE EXCEPTION 'a NULL-created import outranked a timestamped row: got %', v_pick;
    END IF;

    -- And the guards the dumped body carried are still in it.
    IF (SELECT prosrc FROM pg_proc WHERE oid = 'public.sync_product_price_from_log'::regproc)
       NOT LIKE '%OLD.date_updated > v_today%' THEN
        RAISE EXCEPTION 'the staged-delete guard (review P1) is gone from the body';
    END IF;
    IF (SELECT prosrc FROM pg_proc WHERE oid = 'public.sync_product_price_from_log'::regproc)
       NOT LIKE '%AT TIME ZONE COALESCE(f.time_zone%' THEN
        RAISE EXCEPTION 'the facility-timezone resolution (review P2) is gone from the body';
    END IF;

    RAISE NOTICE 'same-day price corrections now win the tie';
END;
$verify$;

commit;
