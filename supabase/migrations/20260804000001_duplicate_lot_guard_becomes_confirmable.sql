-- guard_duplicate_pending_receipt: ask instead of refuse.
--
-- WHAT IT DOES TODAY. Adding a shipment line for (coffee source + lot #) that
-- already has a lot sitting in "Receipts to record" raises P0001 and the insert
-- fails. It cannot be overridden, and its advice — "record that receipt instead"
-- — is only right for one of the two cases it catches:
--
--   · the same delivery entered from both ends  → correct, record the receipt
--   · a SECOND, GENUINE delivery of the same lot number → wrong, and the
--     roaster is stuck with no way to say so
--
-- The guard cannot tell those apart, because nothing in the data distinguishes
-- them. Only the operator knows. So the trigger stops deciding and starts
-- asking: it still refuses by default, but honours an explicit confirmation.
--
-- The exposure widened on 2026-08-04 when quick-add lots began carrying
-- receipt_pending = true (they must, or they never reach the queue and can
-- never be combined). Before that only floor counts armed this.
--
-- HOW THE CONFIRMATION TRAVELS. A transaction-local GUC, set by
-- save_shipment_lines when the caller passes p_allow_duplicate_lot. Local, so
-- it cannot leak past the statement that asked for it, and it is never on by
-- default — a caller that does not know about duplicates gets the old refusal.
--
-- The duplicate itself is no longer invisible either way: as of the same day it
-- surfaces on the inventory page, on the shipment row, and inside Edit Shipment,
-- each offering to combine. The block is no longer the only thing standing
-- between a roaster and a double count, which is what makes softening it safe.

begin;

create or replace function public.guard_duplicate_pending_receipt()
returns trigger
language plpgsql
as $function$
DECLARE v_pending text;
BEGIN
  -- The operator was shown the clash and said these are separate deliveries.
  -- Transaction-local; see save_shipment_lines.
  IF COALESCE(current_setting('app.allow_duplicate_lot', true), '') = 'true' THEN
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
         AND receipt_pending = true
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
         AND origin_purchase_id <> NEW.origin_purchase_id
       LIMIT 1;
    END IF;

    IF v_pending IS NOT NULL THEN
      -- Message unchanged in substance, but it now names the way out rather than
      -- presenting one reading as the only one.
      RAISE EXCEPTION 'This coffee + lot # (%) is already on hand and waiting in "Receipts to record". If it is the same coffee, record that receipt instead of adding a new line. If this is a separate delivery that happens to share a lot number, confirm to add it anyway.',
        COALESCE(NULLIF(btrim(NEW.lot_id), ''), '(no lot #)')
        USING ERRCODE = 'P0001';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

-- save_shipment_lines gains the confirmation flag. Extended IN PLACE with a
-- DEFAULT rather than added as an overload: two functions of the same name would
-- leave PostgREST to choose between them, and "could not choose the best
-- candidate function" is not an error anybody should meet while saving a
-- shipment. With the default, every existing 5-argument caller is unaffected.
--
-- Body below is the deployed definition verbatim, plus the four lines that set
-- the GUC. Nothing else in it was touched.

CREATE OR REPLACE FUNCTION public.save_shipment_lines(p_shipment_id text, p_facility_id text, p_company_id text, p_lines jsonb, p_delete_ids text[], p_allow_duplicate_lot boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_line          jsonb;
    v_pid           text;
    v_origin        text;
    v_old_origin    text;
    v_old_cost      numeric;
    v_new_cost      numeric;
    v_amt           numeric;
    v_affected      text[] := ARRAY[]::text[];   -- origins needing par + cost reconcile (pre+post)
    v_cogs_origins  text[] := ARRAY[]::text[];   -- origins needing COGS reconcile (inserts w/ cost + cost changes)
    v_revalue_ids   text[] := ARRAY[]::text[];   -- purchase_ids whose cost changed (revalue)
    v_o             text;
    v_rid           uuid;
BEGIN
    -- The operator saw the clash and said these are separate deliveries that
    -- happen to share a lot number. Transaction-local, so it cannot outlive this
    -- call; guard_duplicate_pending_receipt reads it.
    IF p_allow_duplicate_lot THEN
      PERFORM set_config('app.allow_duplicate_lot', 'true', true);
    END IF;

    -- Tenant guard (defense behind RLS WITH CHECK): the caller must belong to the
    -- company it is writing. For the authenticated EditShipmentModal caller this is
    -- never more restrictive than RLS; it just fails fast with a clear error.
    IF p_company_id IS NULL
       OR NOT (p_company_id IN (SELECT public.auth_company_ids())) THEN
        RAISE EXCEPTION 'not authorized for company %', p_company_id USING ERRCODE = '42501';
    END IF;

    PERFORM set_config('app.defer_shipment_recompute', 'true', true);

    -- Deletes (gather pre-image origins first). Scoped to caller facility+company.
    IF p_delete_ids IS NOT NULL AND array_length(p_delete_ids, 1) IS NOT NULL THEN
        FOR v_old_origin IN
            SELECT origin FROM public.coffee_inventory_purchased
             WHERE origin_purchase_id = ANY(p_delete_ids)
               AND facility_id = p_facility_id AND company_id = p_company_id
               AND origin IS NOT NULL
        LOOP
            v_affected := array_append(v_affected, v_old_origin);
        END LOOP;
        DELETE FROM public.coffee_inventory_purchased
         WHERE origin_purchase_id = ANY(p_delete_ids)
           AND facility_id = p_facility_id AND company_id = p_company_id;
    END IF;

    -- Upserts.
    FOR v_line IN SELECT * FROM jsonb_array_elements(COALESCE(p_lines, '[]'::jsonb))
    LOOP
        v_pid    := NULLIF(v_line->>'purchase_id', '');
        v_origin := v_line->>'origin_id';
        v_new_cost := CASE WHEN v_line ? 'cost_lb' AND v_line->>'cost_lb' IS NOT NULL
                           THEN (v_line->>'cost_lb')::numeric ELSE NULL END;
        v_amt := CASE WHEN v_line ? 'amount_lbs' AND v_line->>'amount_lbs' IS NOT NULL
                      THEN (v_line->>'amount_lbs')::numeric ELSE NULL END;
        v_affected := array_append(v_affected, v_origin);

        IF v_pid IS NULL THEN
            -- INSERT
            v_pid := gen_random_uuid()::text;
            INSERT INTO public.coffee_inventory_purchased(
                origin_purchase_id, shipment_id, origin, bags_ordered, cost_lb, target_cost_lb,
                coffee_source_id, lot_id, facility_id, company_id, bag_size,
                amount, amount_manual)
            VALUES (
                v_pid, p_shipment_id, v_origin, (v_line->>'bags_ordered')::numeric, v_new_cost,
                NULLIF(v_line->>'target_cost_lb','')::numeric,
                NULLIF(v_line->>'coffee_source_id',''), NULLIF(v_line->>'lot_id',''),
                p_facility_id, p_company_id, NULLIF(v_line->>'bag_size',''),
                v_amt, (v_amt IS NOT NULL));
            IF COALESCE(v_new_cost, 0) <> 0 THEN
                v_cogs_origins := array_append(v_cogs_origins, v_origin);
            END IF;
        ELSE
            -- UPDATE (capture pre-image cost + origin for change detection). Scoped
            -- to caller facility+company so a foreign purchase_id can't be edited.
            SELECT cost_lb, origin INTO v_old_cost, v_old_origin
              FROM public.coffee_inventory_purchased
             WHERE origin_purchase_id = v_pid
               AND facility_id = p_facility_id AND company_id = p_company_id;
            IF v_old_origin IS NOT NULL AND v_old_origin IS DISTINCT FROM v_origin THEN
                v_affected := array_append(v_affected, v_old_origin);
            END IF;
            UPDATE public.coffee_inventory_purchased SET
                bags_ordered   = (v_line->>'bags_ordered')::numeric,
                cost_lb        = v_new_cost,
                target_cost_lb = NULLIF(v_line->>'target_cost_lb','')::numeric,
                coffee_source_id = NULLIF(v_line->>'coffee_source_id',''),
                lot_id         = NULLIF(v_line->>'lot_id',''),
                origin         = v_origin,
                bag_size       = NULLIF(v_line->>'bag_size',''),
                amount         = CASE WHEN v_amt IS NOT NULL THEN v_amt ELSE amount END,
                amount_manual  = (v_amt IS NOT NULL)
            WHERE origin_purchase_id = v_pid
              AND facility_id = p_facility_id AND company_id = p_company_id;
            IF v_old_cost IS DISTINCT FROM v_new_cost THEN
                v_revalue_ids  := array_append(v_revalue_ids, v_pid);
                IF COALESCE(v_new_cost, 0) <> 0 THEN
                    v_cogs_origins := array_append(v_cogs_origins, v_origin);
                END IF;
            END IF;
        END IF;
    END LOOP;

    PERFORM set_config('app.defer_shipment_recompute', 'false', true);

    -- Dedupe the affected sets (drop nulls).
    v_affected     := ARRAY(SELECT DISTINCT x FROM unnest(v_affected)     AS x WHERE x IS NOT NULL);
    v_cogs_origins := ARRAY(SELECT DISTINCT x FROM unnest(v_cogs_origins) AS x WHERE x IS NOT NULL);
    v_revalue_ids  := ARRAY(SELECT DISTINCT x FROM unnest(v_revalue_ids)  AS x WHERE x IS NOT NULL);

    -- ── Reconcile ONCE, in strict order ──
    PERFORM public.calculate_shipment_totals_for(p_shipment_id, p_facility_id);
    FOREACH v_o IN ARRAY v_affected
    LOOP PERFORM public.recalculate_inventory_cost(v_o, p_facility_id); END LOOP;
    FOREACH v_pid IN ARRAY v_revalue_ids LOOP
        FOR v_rid IN SELECT DISTINCT roast_log_id FROM public.roast_log_lot_consumption
                      WHERE origin_purchase_id = v_pid
        LOOP PERFORM public.value_roast_lot_consumption(v_rid); END LOOP;
    END LOOP;
    FOREACH v_o IN ARRAY v_affected
    LOOP PERFORM public.refresh_coffee_stock_par(v_o, p_facility_id); END LOOP;
    FOREACH v_o IN ARRAY v_cogs_origins
    LOOP PERFORM public.propagate_coffee_cost_for_shipment_origin(p_shipment_id, v_o, p_facility_id); END LOOP;
    PERFORM public.recalculate_green_purchasing_metrics(p_facility_id);
END;
$function$;

comment on function public.guard_duplicate_pending_receipt() is
  'Blocks a shipment line duplicating a lot already waiting in Receipts to record, unless app.allow_duplicate_lot is set for the transaction — the operator confirming these are separate deliveries that share a lot number.';

commit;
