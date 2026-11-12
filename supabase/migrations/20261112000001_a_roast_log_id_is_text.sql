-- A roast_log_id is text, so the variable that carries one is text.
--
-- Saving shipment lines died on prod with
--   function public.value_roast_lot_consumption(uuid) does not exist
-- and the function it could not find is right there, taking text:
--   value_roast_lot_consumption(p_roast_log_id text)
--
-- save_shipment_lines declared its loop variable `v_rid uuid` and then
-- PERFORMed that function with it, so the call resolved to a (uuid) signature
-- that has never existed. roast_log.roast_log_id and
-- roast_log_lot_consumption.roast_log_id are both text (information_schema,
-- read 2026-11-12), so uuid was wrong at the declaration, not at the call.
--
-- Nothing else changes. The body below is pg_get_functiondef() of the live
-- prod function with that one word replaced, so no other line is retyped.
-- The two sibling callers are already correct: trg_revalue_roasts_on_cost_change
-- takes its id straight from a SELECT, and needs no change.

begin;

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
    v_rid           text;
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

-- Verify: the declaration is text and no uuid declaration survives.
do $$
begin
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'save_shipment_lines'
       and p.prosrc ~ 'v_rid\s+text;'
       and p.prosrc !~ 'v_rid\s+uuid;'
  ) then
    raise exception 'save_shipment_lines still declares v_rid as uuid';
  end if;
end $$;

commit;
