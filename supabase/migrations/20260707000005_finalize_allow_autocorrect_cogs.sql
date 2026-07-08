-- Phase 3 correction: operator meant (b), not (a) — invoice finalization must
-- NEVER be blocked by pending inventory recalculation. COGS doesn't change what
-- the customer owes (invoice totals come from prices; unit_cost_at_sale is
-- internal margin data), so the right behavior is: finalize freely, and when a
-- deep async replay converges, auto-correct the affected window's COGS — the
-- same retro-propagation the codebase already does for shipment cost changes
-- (propagate_coffee_purchase_to_orders / 20260703000003).
--
-- Note: only the QUEUE window can produce a mid-recalc finalize at all — inline
-- replays (the common case) complete synchronously inside the edit before any
-- finalize could read. So correcting after each drain covers the entire exposure.

-- ── 1. Remove the hard block (shipped a few minutes ago as 20260707000004) ──
DROP TRIGGER IF EXISTS trg_guard_invoice_finalize_recalc ON public.orders;
DROP FUNCTION IF EXISTS public.guard_invoice_finalize_during_recalc();

-- ── 2. Retro COGS propagation for an origin's replay window ─────────────────
-- Modeled on propagate_coffee_cost_for_shipment_origin (same per-line recompute
-- via get_product_cogs_on_date; same unit_cost_at_sale = cost × quantity).
-- Window = the origin's replay window (post-last-count; 30-day fallback),
-- clamped to stay out of closed books.
CREATE OR REPLACE FUNCTION public.propagate_origin_cogs_window(p_origin text, p_facility text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_from   date;
    v_closed date;
    v_rec    record;
    v_new_cost numeric;
BEGIN
    IF p_origin IS NULL OR p_facility IS NULL THEN RETURN; END IF;

    SELECT MAX(clc.count_at)::date INTO v_from
      FROM public.coffee_lot_count clc
      JOIN public.coffee_inventory_purchased cip ON cip.origin_purchase_id = clc.origin_purchase_id
     WHERE cip.origin = p_origin AND cip.facility_id = p_facility;
    v_from := COALESCE(v_from, (now() - interval '30 days')::date);

    SELECT c.books_closed_through INTO v_closed
      FROM public.coffee_inventory ci
      JOIN public.companies c ON c.company_id = ci.company_id
     WHERE ci.origin_id = p_origin AND ci.facility_id = p_facility
     LIMIT 1;
    IF v_closed IS NOT NULL AND v_closed >= v_from THEN
        v_from := v_closed + 1;   -- closed periods keep their booked COGS
    END IF;

    FOR v_rec IN
        SELECT DISTINCT od.order_detail_id, od.product_id, od.facility_id, od.order_date, od.quantity
          FROM public.order_details od
          JOIN public.orders o   ON o.order_id   = od.order_id
          JOIN public.products p ON p.product_id = od.product_id
          JOIN public.recipe_components rc ON rc.recipe_id = p.recipe_id AND rc.facility_id = od.facility_id
         WHERE o.order_status != 'Canceled'
           AND od.facility_id = p_facility
           AND od.order_date >= v_from
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

-- ── 3. Drainer: auto-correct COGS after each origin converges ───────────────
CREATE OR REPLACE PROCEDURE public.drain_lot_recompute_queue(p_max int DEFAULT 10)
LANGUAGE plpgsql AS $$
DECLARE
    r record;
BEGIN
    -- Only one drainer at a time (pg_cron does not serialize same-job runs).
    IF NOT pg_try_advisory_lock(hashtext('lot_recompute_drainer'), 0) THEN RETURN; END IF;
    PERFORM set_config('lock_timeout', '10s', false);

    FOR i IN 1..p_max LOOP
        SELECT id, origin_id, facility_id INTO r
          FROM public.lot_recompute_queue
         WHERE status = 'pending' AND scheduled_at <= now()
         ORDER BY scheduled_at ASC
         FOR UPDATE SKIP LOCKED
         LIMIT 1;
        EXIT WHEN NOT FOUND;

        BEGIN
            PERFORM public.recompute_origin_lot_consumption(r.origin_id, r.facility_id);
            -- (b) auto-correct: any order line in the replay window (invoiced or
            -- not) gets its COGS refreshed from the converged state. Invoice
            -- totals are price-based and unaffected.
            PERFORM public.propagate_origin_cogs_window(r.origin_id, r.facility_id);
            DELETE FROM public.lot_recompute_queue WHERE id = r.id;
        EXCEPTION WHEN OTHERS THEN
            UPDATE public.lot_recompute_queue
               SET attempts   = attempts + 1,
                   last_error = SQLERRM,
                   status     = CASE WHEN attempts + 1 >= 3 THEN 'failed' ELSE 'pending' END,
                   scheduled_at = now() + interval '60 seconds'
             WHERE id = r.id;
        END;
        COMMIT;
    END LOOP;

    PERFORM pg_advisory_unlock(hashtext('lot_recompute_drainer'), 0);
END;
$$;
