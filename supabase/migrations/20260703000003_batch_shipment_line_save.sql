-- Batch the shipment-line save so a multi-line edit runs the heavy inventory
-- recompute ONCE, not once per line.
--
-- Today EditShipmentModal fires N parallel server actions; each write re-runs
-- the full coffee_inventory_purchased trigger stack, so M lines x (calculate_par
-- [two 92-day scans] + per-order COGS propagation + cost + revalue + totals +
-- green) = ~20s, plus an add-then-update double-fire and an unordered race.
--
-- FIX: one RPC does all writes in ONE transaction with a transaction-local
-- defer flag set (the same set_config idiom the codebase already uses). The
-- heavy AFTER triggers no-op while deferring; the RPC then runs ONE reconcile
-- per affected origin/shipment in a STRICT order. Every deferred trigger is a
-- pure function of final committed state, so one reconcile == the sum of the
-- per-line firings (proven for add/update/delete). Shared helper functions make
-- the trigger and the reconcile use the SAME code path (zero divergence).
--
-- Deferred: update_coffee_stock_purchased (par/stock), calculate_shipment_totals,
-- propagate_coffee_purchase_to_orders (COGS), trg_coffee_purchase_cost_update
-- (latest cost), trg_revalue_roasts_on_cost_change, trg_green_metrics_from_purchased.
-- KEPT per-row: audit, compute_coffee_purchase_amount (BEFORE, sets amount/bag_size),
-- dup-receipt guard, current-shipment pointer, remaining_lbs->total refresh.

-- ── Shared helpers (called by BOTH the per-row trigger and the reconcile) ──

-- Par / stock / in_stock / to_order for one origin (extracted verbatim from
-- update_coffee_stock_purchased's per-origin block).
CREATE OR REPLACE FUNCTION public.refresh_coffee_stock_par(p_origin text, p_facility text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_bag_size NUMERIC;
    v_current_lbs NUMERIC;
    v_par NUMERIC;
BEGIN
    SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
      FROM coffee_inventory WHERE origin_id = p_origin AND facility_id = p_facility LIMIT 1;
    v_current_lbs := public.calculate_current_stock_lbs(p_origin, p_facility);
    v_par         := public.calculate_par(p_origin);
    UPDATE coffee_inventory SET
        in_stock_lbs  = v_current_lbs,
        in_stock      = v_current_lbs / NULLIF(v_bag_size, 0),
        par           = v_par,
        to_order_bags = GREATEST(0, COALESCE(v_par, 0) - (v_current_lbs / NULLIF(v_bag_size, 0))),
        restock_level = public.calculate_restock_level(p_origin)
    WHERE origin_id = p_origin AND facility_id = p_facility;
END;
$$;

-- Shipment weight + shipping_cost_unit (extracted from calculate_shipment_totals).
CREATE OR REPLACE FUNCTION public.calculate_shipment_totals_for(p_shipment_id text, p_facility_id text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_total_weight NUMERIC;
BEGIN
    v_total_weight := (
        SELECT COALESCE(SUM(amount), 0) FROM coffee_inventory_purchased
         WHERE shipment_id = p_shipment_id AND facility_id = p_facility_id
    ) + (
        SELECT COALESCE(SUM(amount), 0) FROM consumable_inventory_purchased
         WHERE shipment_id = p_shipment_id AND facility_id = p_facility_id
    );
    UPDATE shipment_received SET
        shipment_total_weight_units = v_total_weight,
        shipping_cost_unit = CASE WHEN v_total_weight > 0 THEN ROUND(shipping_cost / v_total_weight, 3) ELSE 0 END
    WHERE shipment_id = p_shipment_id AND facility_id = p_facility_id;
END;
$$;

-- COGS-to-orders for one (shipment, origin) window (extracted from
-- propagate_coffee_purchase_to_orders — same window + same per-order recompute).
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
         WHERE o.order_status != 'Canceled'
           AND od.order_date >= v_this_date
           AND (v_next_date IS NULL OR od.order_date < v_next_date)
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

-- ── Guarded trigger functions (no-op while the batch defer flag is set) ──

CREATE OR REPLACE FUNCTION public.update_coffee_stock_purchased() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF current_setting('app.defer_shipment_recompute', true) = 'true' THEN RETURN NULL; END IF;
    IF TG_OP = 'DELETE' THEN
        PERFORM public.refresh_coffee_stock_par(OLD.origin, OLD.facility_id);
    ELSIF TG_OP = 'INSERT' THEN
        PERFORM public.refresh_coffee_stock_par(NEW.origin, NEW.facility_id);
    ELSE  -- UPDATE
        IF OLD.origin IS DISTINCT FROM NEW.origin OR OLD.facility_id IS DISTINCT FROM NEW.facility_id THEN
            PERFORM public.refresh_coffee_stock_par(OLD.origin, OLD.facility_id);
        END IF;
        PERFORM public.refresh_coffee_stock_par(NEW.origin, NEW.facility_id);
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.calculate_shipment_totals() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF current_setting('app.defer_shipment_recompute', true) = 'true' THEN RETURN COALESCE(NEW, OLD); END IF;
    IF TG_OP = 'DELETE' THEN
        PERFORM public.calculate_shipment_totals_for(OLD.shipment_id, OLD.facility_id);
        RETURN OLD;
    ELSE
        PERFORM public.calculate_shipment_totals_for(NEW.shipment_id, NEW.facility_id);
        RETURN NEW;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.propagate_coffee_purchase_to_orders() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF current_setting('app.defer_shipment_recompute', true) = 'true' THEN RETURN NULL; END IF;
    IF TG_OP = 'UPDATE' AND OLD.cost_lb IS NOT DISTINCT FROM NEW.cost_lb THEN RETURN NULL; END IF;
    IF COALESCE(NEW.cost_lb, 0) = 0 THEN RETURN NULL; END IF;
    PERFORM public.propagate_coffee_cost_for_shipment_origin(NEW.shipment_id, NEW.origin, NEW.facility_id);
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_coffee_purchase_cost_update() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF current_setting('app.defer_shipment_recompute', true) = 'true' THEN RETURN NEW; END IF;
    PERFORM public.recalculate_inventory_cost(
        COALESCE(NEW.origin, OLD.origin), COALESCE(NEW.facility_id, OLD.facility_id));
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_revalue_roasts_on_cost_change() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF current_setting('app.defer_shipment_recompute', true) = 'true' THEN RETURN NEW; END IF;
    IF NEW.cost_lb IS DISTINCT FROM OLD.cost_lb THEN
        PERFORM public.value_roast_lot_consumption(rid)
        FROM (SELECT DISTINCT roast_log_id AS rid
                FROM public.roast_log_lot_consumption
               WHERE origin_purchase_id = NEW.origin_purchase_id) x;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_green_metrics_from_purchased() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF current_setting('app.defer_shipment_recompute', true) = 'true' THEN RETURN NULL; END IF;
    PERFORM public.recalculate_green_purchasing_metrics(COALESCE(NEW.facility_id, OLD.facility_id));
    RETURN NULL;
END;
$$;

-- ── The batch RPC ──
-- p_lines: jsonb array of { purchase_id?, origin_id, coffee_source_id?, lot_id?,
--   bags_ordered, cost_lb?, target_cost_lb?, bag_size?, amount_lbs? }
--   (purchase_id null => insert; amount_lbs null => clear override).
-- p_delete_ids: origin_purchase_ids to delete.
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
    PERFORM set_config('app.defer_shipment_recompute', 'true', true);

    -- Deletes (gather pre-image origins first).
    IF p_delete_ids IS NOT NULL AND array_length(p_delete_ids, 1) IS NOT NULL THEN
        FOR v_old_origin IN
            SELECT origin FROM public.coffee_inventory_purchased
             WHERE origin_purchase_id = ANY(p_delete_ids) AND origin IS NOT NULL
        LOOP
            v_affected := array_append(v_affected, v_old_origin);
        END LOOP;
        DELETE FROM public.coffee_inventory_purchased WHERE origin_purchase_id = ANY(p_delete_ids);
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
            -- UPDATE (capture pre-image cost + origin for change detection)
            SELECT cost_lb, origin INTO v_old_cost, v_old_origin
              FROM public.coffee_inventory_purchased WHERE origin_purchase_id = v_pid;
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
            WHERE origin_purchase_id = v_pid;
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
    -- 1. shipment totals (sets shipping_cost_unit, feeds cost + COGS)
    PERFORM public.calculate_shipment_totals_for(p_shipment_id, p_facility_id);
    -- 2. latest cost per affected origin (reads shipping_cost_unit)
    FOREACH v_o IN ARRAY v_affected
    LOOP PERFORM public.recalculate_inventory_cost(v_o, p_facility_id); END LOOP;
    -- 3. revalue roasts that consumed a cost-changed lot (rebuilds ledger snapshots)
    FOREACH v_pid IN ARRAY v_revalue_ids LOOP
        FOR v_rid IN SELECT DISTINCT roast_log_id FROM public.roast_log_lot_consumption
                      WHERE origin_purchase_id = v_pid
        LOOP PERFORM public.value_roast_lot_consumption(v_rid); END LOOP;
    END LOOP;
    -- 4. par / stock / to_order per affected origin
    FOREACH v_o IN ARRAY v_affected
    LOOP PERFORM public.refresh_coffee_stock_par(v_o, p_facility_id); END LOOP;
    -- 5. COGS-to-orders per cost-affected origin (reads shipping_cost_unit + ledger)
    FOREACH v_o IN ARRAY v_cogs_origins
    LOOP PERFORM public.propagate_coffee_cost_for_shipment_origin(p_shipment_id, v_o, p_facility_id); END LOOP;
    -- 6. green purchasing metrics once (reads to_order_bags from par)
    PERFORM public.recalculate_green_purchasing_metrics(p_facility_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.save_shipment_lines(text, text, text, jsonb, text[]) TO authenticated;

NOTIFY pgrst, 'reload schema';
