-- Source-count Phase 2B: duplicate-guard.
--
-- If a lot was counted on the floor (receipt_pending) and an admin then records a
-- NORMAL shipment for the same coffee + lot #, that's the same physical coffee
-- entered twice → double stock. Block it at the DB level (holds even if the UI is
-- bypassed) and point them at the Receipts to record queue, where they fill the
-- purchase onto the lot that's already on hand. Join key = facility + source + lot#
-- (the lot # is the only differentiator when a source is re-used).
CREATE OR REPLACE FUNCTION public.guard_duplicate_pending_receipt()
RETURNS trigger LANGUAGE plpgsql AS $function$
DECLARE v_pending text;
BEGIN
  -- only guard real recorded-shipment lots that carry a source + lot #
  IF NEW.entry_method = 'shipment'
     AND NEW.coffee_source_id IS NOT NULL
     AND NULLIF(btrim(NEW.lot_id), '') IS NOT NULL
     AND NOT COALESCE(NEW.receipt_pending, false) THEN
    SELECT origin_purchase_id INTO v_pending
      FROM public.coffee_inventory_purchased
     WHERE facility_id = NEW.facility_id
       AND coffee_source_id = NEW.coffee_source_id
       AND lower(btrim(lot_id)) = lower(btrim(NEW.lot_id))
       AND receipt_pending = true
       AND origin_purchase_id <> NEW.origin_purchase_id
     LIMIT 1;
    IF v_pending IS NOT NULL THEN
      RAISE EXCEPTION 'This coffee + lot # (%) was already counted and is waiting in "Receipts to record". Record that receipt instead of adding a new shipment line — otherwise the same coffee is counted twice.', NEW.lot_id
        USING ERRCODE = 'P0001';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_guard_dup_pending_receipt ON public.coffee_inventory_purchased;
CREATE TRIGGER trg_guard_dup_pending_receipt
  BEFORE INSERT ON public.coffee_inventory_purchased
  FOR EACH ROW EXECUTE FUNCTION public.guard_duplicate_pending_receipt();
