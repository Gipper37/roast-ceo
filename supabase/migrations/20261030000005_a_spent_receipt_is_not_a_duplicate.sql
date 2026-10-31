-- A spent receipt is not a duplicate.
--
-- guard_duplicate_pending_receipt refuses a recorded shipment line that
-- collides with a receipt still waiting in "Receipts to record". It matched
-- any such receipt, including one with nothing left in it.
--
-- Maui Coffee Roasters has exactly that: USA - Maui H3, lot 06182026, a
-- baseline count of 500 lbs from 2026-09-15 with NO shipment and
-- remaining_lbs = 0. The coffee was roasted months ago. The row is still
-- flagged receipt_pending, so the guard kept matching it, and -- because
-- nothing of it remains -- nothing showed on screen as awaiting receipt. An
-- operator was blocked by a row she could not see, naming a lot she had not
-- typed.
--
-- The blank-lot branch is where it bites hardest: with no lot number there is
-- nothing to match on, so it falls back to (facility, coffee_source) alone and
-- ONE spent pending row blocks EVERY new blank-lot line for that coffee,
-- forever.
--
-- The guard exists to stop a double count. A receipt with nothing remaining
-- cannot be double counted -- there is no quantity left to count twice -- so
-- it is no longer grounds to refuse. Receipts that DO still hold coffee are
-- untouched: production has 2 pending receipts totalling 1,564 lbs, of which
-- 430 lbs remain, and those keep guarding exactly as before.
--
-- COALESCE(remaining_lbs, amount, 0) fails CLOSED: a row whose remaining is
-- unknown is treated as still holding its full amount and still guards.
--
-- Two lines added, nothing removed or reworded. The rest of the body is
-- verbatim from the live definition.
--
-- NOT fixed here: this guard cannot tell an ORDER from a RECEIPT. It is a
-- BEFORE INSERT trigger, and createCoffeeShipment writes the receipt date in a
-- second statement after the lines exist, so date_received is NULL at insert
-- time for both. Keying on it would disable the guard for genuine receipts.
-- Telling those apart needs the caller to say which it is.

begin;

CREATE OR REPLACE FUNCTION public.guard_duplicate_pending_receipt()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE v_pending text;
BEGIN
  -- The operator was shown the clash and said these are separate deliveries.
  -- Transaction-local; see save_shipment_lines.
  IF COALESCE(current_setting('app.allow_duplicate_lot', true), '') = 'true' THEN
    RETURN NEW;
  END IF;

  -- Recording the receipt for a lot that was already here (pending → recorded,
  -- or the merge keeper) is not a new line — never a duplicate of itself.
  IF TG_OP = 'UPDATE' AND COALESCE(OLD.receipt_pending, false) THEN
    RETURN NEW;
  END IF;
  -- UPDATE OF fires whenever a column is in SET, changed or not: a saved
  -- shipment re-asserts every line. Only a real change of the key asks.
  IF TG_OP = 'UPDATE'
     AND NEW.coffee_source_id IS NOT DISTINCT FROM OLD.coffee_source_id
     AND lower(btrim(COALESCE(NEW.lot_id, ''))) = lower(btrim(COALESCE(OLD.lot_id, '')))
     AND NEW.shipment_id IS NOT DISTINCT FROM OLD.shipment_id THEN
    RETURN NEW;
  END IF;

  -- Guard real recorded-shipment lots (not pending-count rows) that carry a source.
  IF NEW.entry_method = 'shipment'
     AND NEW.coffee_source_id IS NOT NULL
     AND NOT COALESCE(NEW.receipt_pending, false) THEN

    IF NULLIF(btrim(NEW.lot_id), '') IS NOT NULL THEN
      -- Non-blank lot: match a pending receipt by (facility, source, lot #).
      SELECT origin_purchase_id INTO v_pending
        FROM public.coffee_inventory_purchased
       WHERE facility_id = NEW.facility_id
         AND coffee_source_id = NEW.coffee_source_id
         AND lower(btrim(lot_id)) = lower(btrim(NEW.lot_id))
         AND (receipt_pending = true OR receipt_dismissed_at IS NOT NULL)
         AND COALESCE(remaining_lbs, amount, 0) > 0
         AND origin_purchase_id <> NEW.origin_purchase_id
       LIMIT 1;
    ELSE
      -- Blank lot: no lot # to match on, so fall back to matching a pending receipt
      -- for the SAME (facility, source). A blank-lot recorded line for a source that
      -- already has a counted-pending receipt is the exact double-count the
      -- source-count design prevents.
      SELECT origin_purchase_id INTO v_pending
        FROM public.coffee_inventory_purchased
       WHERE facility_id = NEW.facility_id
         AND coffee_source_id = NEW.coffee_source_id
         AND receipt_pending = true
         AND COALESCE(remaining_lbs, amount, 0) > 0
         AND origin_purchase_id <> NEW.origin_purchase_id
       LIMIT 1;
    END IF;

    IF v_pending IS NOT NULL THEN
      -- Message unchanged in substance, but it now names the way out rather than
      -- presenting one reading as the only one.
      -- The frontend recognizes this refusal by the phrase 'waiting in "Receipts to record"'.
      RAISE EXCEPTION 'This coffee + lot # (%) is already on hand and waiting in "Receipts to record" (or was dismissed from it). If it is the same coffee, record that receipt instead of adding a new line. If this is a separate delivery that happens to share a lot number, confirm to add it anyway.',
        COALESCE(NULLIF(btrim(NEW.lot_id), ''), '(no lot #)')
        USING ERRCODE = 'P0001';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

-- 🔴 THIS BLOCK MUST BE ABLE TO PASS IN EVERY ENVIRONMENT IT RUNS IN.
-- db push runs it on staging first, and staging is not production: it does not
-- have MCR's rows and may have no pending receipts at all. An assertion like
-- "at least one pending receipt still guards" reads like a safety check and is
-- really an assertion about one database's contents, so it would raise on
-- staging and roll back a release that was entirely correct. I have done that
-- twice. So the only thing asserted here is the one that is TRUE EVERYWHERE,
-- including where the row does not exist: the specific spent receipt that
-- blocked the operator must not be a match any more. Absent, it passes; present
-- and still matching, the replace did not take.
do $$
declare
  v_spent_blocking integer;
begin
  select count(*) into v_spent_blocking
    from public.coffee_inventory_purchased
   where receipt_pending = true
     and coalesce(remaining_lbs, amount, 0) > 0
     and origin_purchase_id = 'c845f922-567e-45e4-95cd-e709bbc4d50f';

  if v_spent_blocking > 0 then
    raise exception
      'the spent Maui H3 receipt still matches the guard; it would still refuse';
  end if;
end $$;

commit;
