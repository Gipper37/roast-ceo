-- Audit fixes (2026-07-04) — from the 2026-07-03 read-only audit + 2026-07-04 re-check.
-- REVIEW-FIRST: written for review. Do NOT apply until approved (commit → db-push
-- staging → verify → release tag for prod).
--
-- Items addressed:
--   #2  get_origin_roasted_cost_on_date — NULL-cost lots (green_cost_lb IS NULL →
--       the GENERATED lot_cost COALESCEs green→0, so lot_cost = 0, NOT NULL) slipped
--       past the `lot_cost IS NOT NULL` guard and entered the roasted-cost DENOMINATOR
--       with a 0 numerator, diluting origin $/lb downward (live: 460 lb on MCR).
--       Fix: guard on the SOURCE cost (green_cost_lb IS NOT NULL) so uncosted lots
--       leave BOTH numerator and denominator.
--   #3  guard_duplicate_pending_receipt — a blank-lot source-tracked recorded line
--       bypassed the dup-pending check (guard required a non-blank lot_id), re-opening
--       the counted-pending + recorded-shipment double-count. Fix: add a source-only
--       fallback so a blank-lot recorded line for a source that has a pending receipt
--       is blocked. (EditShipmentModal now also REQUIRES a lot# on received
--       source-tracked lines; this is the DB backstop for any other write path.)
--   (a) REVOKE PUBLIC EXECUTE on the 6 batch/recompute RPCs (anon-callable via
--       PostgREST once save_shipment_lines went live). authenticated + service_role
--       grants are separate ACL entries and are retained.
--   (b) save_shipment_lines — validate p_company_id against auth_company_ids()
--       (defense behind RLS WITH CHECK) + scope the DELETE (and its pre-image gather)
--       to the caller's facility+company (RLS is company-scoped only, so this adds
--       facility-level protection).  ⟵ REVIEW-SENSITIVE: the top tenant guard rejects
--       a call whose p_company_id is not in the caller's JWT companies. The only
--       caller is the authenticated EditShipmentModal, for which this is never more
--       restrictive than the existing RLS WITH CHECK. If a service_role/no-JWT caller
--       is ever added it would need the guard relaxed.
--   (c) propagate_coffee_cost_for_shipment_origin — restore the books_closed guard
--       (JOIN companies cmp + od.order_date > COALESCE(cmp.books_closed_through,
--       '-infinity')) that was dropped when this helper was extracted from
--       propagate_coffee_purchase_to_orders. Dormant until a company sets
--       books_closed_through (MCR = NULL today), but prevents rewriting COGS on a
--       closed period once one does.

-- ── #2: COGS roasted-cost guard — exclude genuinely uncosted lots ──────────────
CREATE OR REPLACE FUNCTION public.get_origin_roasted_cost_on_date(p_origin_id text, p_facility_id text, p_order_date date)
 RETURNS numeric
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_cost numeric;
BEGIN
    SELECT SUM(rlc.lot_cost)
           / NULLIF(SUM(rlc.lbs_consumed
               * COALESCE(rl.measured_roasted_weight, rl.roasted_weight,
                          rl.charge_weight_lbs * COALESCE(public.get_retention_factor(rl.facility_id, rl.recipe_id), 0.82))
               / NULLIF(rl.charge_weight_lbs, 0)), 0)
      INTO v_cost
      FROM public.roast_log_lot_consumption rlc
      JOIN public.roast_log rl  ON rl.roast_log_id       = rlc.roast_log_id
      JOIN public.coffee_inventory_purchased cip ON cip.origin_purchase_id = rlc.origin_purchase_id
     WHERE cip.origin       = p_origin_id
       AND rl.facility_id   = p_facility_id
       AND rl.roast_date   <= p_order_date
       AND rlc.green_cost_lb IS NOT NULL;   -- was `rlc.lot_cost IS NOT NULL` — cost-blind:
                                            -- generated lot_cost COALESCEs a NULL green
                                            -- cost to 0, so uncosted lots passed the guard
                                            -- and diluted the denominator.
    RETURN v_cost;  -- NULL => caller falls back to the group/shipment path
END;
$function$;

-- ── #3: dup-pending guard — cover blank-lot source-tracked recorded lines ──────
CREATE OR REPLACE FUNCTION public.guard_duplicate_pending_receipt()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE v_pending text;
BEGIN
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
      RAISE EXCEPTION 'This coffee + lot # (%) was already counted and is waiting in "Receipts to record". Record that receipt instead of adding a new shipment line — otherwise the same coffee is counted twice.',
        COALESCE(NULLIF(btrim(NEW.lot_id), ''), '(no lot #)')
        USING ERRCODE = 'P0001';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

-- ── (c): restore the books_closed guard in the extracted COGS helper ───────────
CREATE OR REPLACE FUNCTION public.propagate_coffee_cost_for_shipment_origin(
    p_shipment_id text, p_origin text, p_facility text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_this_date date;
    v_next_date date;
    v_new_cost  numeric;
    v_rec       record;
BEGIN
    SELECT sr.date_received INTO v_this_date
      FROM public.shipment_received sr
     WHERE sr.shipment_id = p_shipment_id AND COALESCE(sr.voided, false) = false
     LIMIT 1;
    IF v_this_date IS NULL THEN RETURN; END IF;

    SELECT sr.date_received INTO v_next_date
      FROM public.coffee_inventory_purchased cp
      JOIN public.shipment_received sr ON sr.shipment_id = cp.shipment_id
     WHERE cp.origin = p_origin AND cp.facility_id = p_facility
       AND sr.date_received IS NOT NULL AND sr.date_received > v_this_date
       AND cp.shipment_id != p_shipment_id AND COALESCE(sr.voided, false) = false
     ORDER BY sr.date_received ASC LIMIT 1;

    FOR v_rec IN
        SELECT DISTINCT od.order_detail_id, od.product_id, od.facility_id, od.order_date, od.quantity
          FROM public.order_details od
          JOIN public.orders o    ON o.order_id   = od.order_id
          JOIN public.products p  ON p.product_id = od.product_id
          JOIN public.recipe_components rc ON rc.recipe_id = p.recipe_id AND rc.facility_id = od.facility_id
          JOIN public.companies cmp ON cmp.company_id = od.company_id
         WHERE o.order_status != 'Canceled'
           AND od.order_date >= v_this_date
           AND (v_next_date IS NULL OR od.order_date < v_next_date)
           AND od.order_date  > COALESCE(cmp.books_closed_through, '-infinity'::date)  -- books-closed guard (restored)
           AND rc.coffee_item = p_origin
           AND COALESCE(od.quantity, 0) > 0
    LOOP
        v_new_cost := public.get_product_cogs_on_date(v_rec.product_id, v_rec.facility_id, v_rec.order_date);
        IF v_new_cost IS NOT NULL AND v_new_cost > 0 THEN
            UPDATE public.order_details
               SET unit_cost_at_sale = v_new_cost * v_rec.quantity, updated_at = now()
             WHERE order_detail_id = v_rec.order_detail_id;
        END IF;
    END LOOP;
END;
$$;

-- ── (b): save_shipment_lines — tenant guard + scoped DELETE ────────────────────
CREATE OR REPLACE FUNCTION public.save_shipment_lines(
    p_shipment_id text,
    p_facility_id text,
    p_company_id  text,
    p_lines       jsonb,
    p_delete_ids  text[]
) RETURNS void
LANGUAGE plpgsql AS $$
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
$$;

-- ── (a): REVOKE PUBLIC EXECUTE on the batch/recompute RPCs (keep authenticated) ─
REVOKE EXECUTE ON FUNCTION public.save_shipment_lines(text, text, text, jsonb, text[]) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.record_lot_receipt(text, numeric, text, date, numeric, text, boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.recalculate_origin_total_stock(text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.refresh_coffee_stock_par(text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.propagate_coffee_cost_for_shipment_origin(text, text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.calculate_shipment_totals_for(text, text) FROM PUBLIC;

NOTIFY pgrst, 'reload schema';
