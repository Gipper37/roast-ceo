-- Source-count Phase 2B: "Receipts to record" reconciliation.
--
-- receipt_pending: a lot counted via the source-count "Add spent/unlisted source"
-- flow (addSourceLot) whose PURCHASE (cost / supplier / shipment) hasn't been
-- recorded yet. It's on-hand truth already (from the count); it just needs its
-- buy-side filled in. Existing baseline lots default false (they already carry
-- cost), so only forward count-created lots surface in the queue.
ALTER TABLE public.coffee_inventory_purchased
  ADD COLUMN IF NOT EXISTS receipt_pending boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN public.coffee_inventory_purchased.receipt_pending IS
  'Counted (via source-count add-source) but purchase not yet recorded — surfaces in the Receipts to record queue.';

-- Record the purchase for a pending counted lot: attach a received shipment + set
-- cost, flip it to a recorded receipt. NEVER overwrites remaining_lbs (the manual
-- count is the physical truth). WARNS (returns a flag, does not apply) if the
-- received date is AFTER the lot's manual count date — the counted bags can't have
-- come from a shipment received later; caller re-invokes with p_confirm_past_count
-- to override. p_shipment_id links to an existing shipment (grouping) instead of
-- creating one.
CREATE OR REPLACE FUNCTION public.record_lot_receipt(
  p_origin_purchase_id text, p_cost_lb numeric, p_supplier_id text, p_received_date date,
  p_shipping_cost numeric DEFAULT 0, p_shipment_id text DEFAULT NULL, p_confirm_past_count boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE
  v_lot record; v_count_date date; v_ship text;
BEGIN
  SELECT * INTO v_lot FROM public.coffee_inventory_purchased WHERE origin_purchase_id = p_origin_purchase_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'lot % not found', p_origin_purchase_id; END IF;
  IF NOT COALESCE(v_lot.receipt_pending, false) THEN RAISE EXCEPTION 'lot has no pending receipt to record'; END IF;
  IF p_cost_lb IS NULL OR p_cost_lb < 0 THEN RAISE EXCEPTION 'cost per lb is required'; END IF;
  IF p_received_date IS NULL THEN RAISE EXCEPTION 'received date is required'; END IF;

  -- the lot's manual count date (latest anchor)
  SELECT MAX(count_date) INTO v_count_date
    FROM public.coffee_lot_count WHERE origin_purchase_id = p_origin_purchase_id;

  -- WARN: receipt dated AFTER the count → the counted bags can't be from this shipment
  IF v_count_date IS NOT NULL AND p_received_date > v_count_date AND NOT p_confirm_past_count THEN
    RETURN jsonb_build_object(
      'warning', 'received_after_count',
      'count_date', v_count_date, 'received_date', p_received_date,
      'message', format('This lot was counted on %s but the receipt is dated %s (later). The counted bags can''t have come from a shipment received after the count — check the date, or confirm to record anyway.', v_count_date, p_received_date));
  END IF;

  -- shipment header: link to an existing one (grouping), else create a received one
  IF p_shipment_id IS NOT NULL THEN
    v_ship := p_shipment_id;
  ELSE
    v_ship := 'rcpt-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 18);
    INSERT INTO public.shipment_received
      (shipment_id, company_id, facility_id, supplier_id, order_date, date_received, shipping_cost, status, voided, created_at, updated_at)
    VALUES
      (v_ship, v_lot.company_id, v_lot.facility_id, p_supplier_id, p_received_date, p_received_date, COALESCE(p_shipping_cost, 0), 'received', false, now(), now());
  END IF;

  -- attach + set cost + flip to recorded. remaining_lbs is LEFT ALONE (count is truth).
  UPDATE public.coffee_inventory_purchased
     SET shipment_id = v_ship, cost_lb = p_cost_lb, entry_method = 'shipment',
         receipt_pending = false, updated_at = now()
   WHERE origin_purchase_id = p_origin_purchase_id;

  RETURN jsonb_build_object('ok', true, 'shipment_id', v_ship);
END;
$function$;
