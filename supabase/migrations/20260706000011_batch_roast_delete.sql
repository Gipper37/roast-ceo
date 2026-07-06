-- Fast roast deletion (single + bulk) — kills the ~15-25s completed-roast delete
-- and the bulk-delete timeout/rollback.
--
-- ROOT CAUSE (measured on prod, EXPLAIN ANALYZE rolled back): the AFTER-DELETE
-- trigger roast_log_lot_recompute runs recompute_origin_lot_consumption — a FULL
-- FIFO replay of the ENTIRE origin (wipe all consumption, re-loop every charged
-- roast for the facility+origin) — on EVERY single-row delete. Dominant origin
-- had 5,645 roasts → 24.5s of the 24.6s delete. A .in() bulk delete fires the
-- trigger once PER row, so 4 completed roasts ≈ 4×24s in one atomic statement,
-- blowing the authenticated role's statement_timeout=60s → the whole batch rolls
-- back → "deleted nothing". A staged delete no-ops the trigger → ~50ms.
--
-- FIX: a batch RPC that DEFERS the heavy trigger (same set_config idiom as
-- save_shipment_lines) and reconciles ONCE per affected origin. Deleting one
-- roast only frees that roast's own consumed lbs, so the common case (deleting
-- recent roasts) takes an incremental reversal — O(rows-for-this-roast), instant.
-- A full replay is run ONLY when a surviving charged roast is ordered at/after a
-- deleted one for the origin (mid-history delete → FIFO could re-order), so the
-- result is ALWAYS exactly FIFO-correct; worst case it is merely slow, never wrong.

-- ── 1. Defer guard on the heavy trigger ─────────────────────────────────────
-- One added line vs the live definition: no-op while the batch RPC holds the
-- transaction-local defer flag. Every other branch is unchanged.
CREATE OR REPLACE FUNCTION public.roast_log_lot_recompute()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    o text;
    v_lender text;
BEGIN
    -- Batch delete_roasts() suppresses this per-row recompute and reconciles
    -- once per origin itself. Transaction-local, so it cannot leak to other
    -- sessions or the normal single-charge path.
    IF current_setting('app.defer_lot_recompute', true) = 'true' THEN RETURN NULL; END IF;

    IF TG_OP = 'INSERT' THEN
        IF NEW."charged?" = true THEN
            PERFORM public.deduct_one_roast(NEW.roast_log_id);
        END IF;
        RETURN NULL;
    END IF;

    IF TG_OP = 'DELETE' THEN
        IF OLD."charged?" = true AND OLD.facility_id IS NOT NULL THEN
            FOREACH o IN ARRAY public._roast_affected_origins(OLD.recipe_id, OLD.origin_id) LOOP
                PERFORM public.recompute_origin_lot_consumption(o, OLD.facility_id);
            END LOOP;
            IF OLD.borrow_origin_purchase_id IS NOT NULL THEN
                SELECT origin INTO v_lender FROM public.coffee_inventory_purchased
                 WHERE origin_purchase_id = OLD.borrow_origin_purchase_id;
                IF v_lender IS NOT NULL THEN
                    PERFORM public.recompute_origin_lot_consumption(v_lender, OLD.facility_id);
                END IF;
            END IF;
        END IF;
        RETURN NULL;
    END IF;

    -- UPDATE: fresh charge (false→true) → fast incremental deduct.
    IF COALESCE(OLD."charged?", false) = false AND NEW."charged?" = true THEN
        PERFORM public.deduct_one_roast(NEW.roast_log_id);
        RETURN NULL;
    END IF;

    -- Retroactive change to a charged roast (or un-charge) → full replay.
    IF (COALESCE(OLD."charged?", false) = true AND COALESCE(NEW."charged?", false) = false)
       OR (NEW."charged?" = true AND (
              NEW.charge_weight_lbs IS DISTINCT FROM OLD.charge_weight_lbs OR
              NEW.charge_weight     IS DISTINCT FROM OLD.charge_weight OR
              NEW.origin_id         IS DISTINCT FROM OLD.origin_id OR
              NEW.recipe_id         IS DISTINCT FROM OLD.recipe_id OR
              NEW.coffee_source_id  IS DISTINCT FROM OLD.coffee_source_id OR
              NEW.planned_lots      IS DISTINCT FROM OLD.planned_lots OR
              NEW.borrow_origin_purchase_id IS DISTINCT FROM OLD.borrow_origin_purchase_id))
    THEN
        IF NEW.facility_id IS NOT NULL THEN
            FOREACH o IN ARRAY public._roast_affected_origins(NEW.recipe_id, NEW.origin_id) LOOP
                PERFORM public.recompute_origin_lot_consumption(o, NEW.facility_id);
            END LOOP;
            IF NEW.borrow_origin_purchase_id IS NOT NULL THEN
                SELECT origin INTO v_lender FROM public.coffee_inventory_purchased
                 WHERE origin_purchase_id = NEW.borrow_origin_purchase_id;
                IF v_lender IS NOT NULL THEN
                    PERFORM public.recompute_origin_lot_consumption(v_lender, NEW.facility_id);
                END IF;
            END IF;
        END IF;
        IF OLD.facility_id IS NOT NULL THEN
            FOREACH o IN ARRAY public._roast_affected_origins(OLD.recipe_id, OLD.origin_id) LOOP
                PERFORM public.recompute_origin_lot_consumption(o, OLD.facility_id);
            END LOOP;
            -- OLD lender (covers re-pointing the borrow to a different lot/group)
            IF OLD.borrow_origin_purchase_id IS NOT NULL
               AND OLD.borrow_origin_purchase_id IS DISTINCT FROM NEW.borrow_origin_purchase_id THEN
                SELECT origin INTO v_lender FROM public.coffee_inventory_purchased
                 WHERE origin_purchase_id = OLD.borrow_origin_purchase_id;
                IF v_lender IS NOT NULL THEN
                    PERFORM public.recompute_origin_lot_consumption(v_lender, OLD.facility_id);
                END IF;
            END IF;
        END IF;
    END IF;
    RETURN NULL;
END;
$function$;

-- ── 2. Batch delete RPC ─────────────────────────────────────────────────────
-- SECURITY INVOKER (default): RLS (tenant_company_access) scopes every read +
-- the DELETE to the caller's company, exactly like the current .delete().in().
CREATE OR REPLACE FUNCTION public.delete_roasts(p_roast_log_ids text[])
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_o record;
BEGIN
    IF p_roast_log_ids IS NULL OR array_length(p_roast_log_ids, 1) IS NULL THEN
        RETURN;
    END IF;

    -- What the targeted roasts consumed, per lot, with each roast's FIFO ordering
    -- key (identical COALESCE to recompute_origin_lot_consumption). A consumed
    -- lot's cip.origin is the physical home group — for a BORROW roast that is the
    -- LENDER's group — so this is exactly the set of origins whose stock changes.
    CREATE TEMP TABLE _del_cons ON COMMIT DROP AS
    SELECT rlc.origin_purchase_id,
           cip.origin        AS origin,
           rl.facility_id     AS facility_id,
           rlc.lbs_consumed   AS lbs_consumed,
           COALESCE(rl.roast_date_utc,
                    (rl.roast_date AT TIME ZONE COALESCE(NULLIF(f.time_zone, ''), 'UTC'))) AS roast_utc
      FROM public.roast_log_lot_consumption rlc
      JOIN public.coffee_inventory_purchased cip ON cip.origin_purchase_id = rlc.origin_purchase_id
      JOIN public.roast_log rl ON rl.roast_log_id = rlc.roast_log_id
      LEFT JOIN public.facilities f ON f.facility_id = rl.facility_id
     WHERE rlc.roast_log_id = ANY(p_roast_log_ids)
       AND cip.origin IS NOT NULL
       AND rl.facility_id IS NOT NULL;

    -- One row per affected (origin, facility): earliest freed point + whether a
    -- full replay is required. Replay iff a SURVIVING charged roast that targets
    -- this origin is ordered at/after the earliest deleted roast for it — only
    -- then can freeing an earlier lot re-order a later roast's FIFO allocation.
    -- Deleting the most-recent roast(s) has no such survivor → fast path. A NULL
    -- ordering key (legacy row missing both date columns) conservatively replays.
    CREATE TEMP TABLE _del_origin ON COMMIT DROP AS
    SELECT origin, facility_id,
           MIN(roast_utc)             AS min_utc,
           bool_or(roast_utc IS NULL) AS has_null_utc
      FROM _del_cons
     GROUP BY origin, facility_id;

    ALTER TABLE _del_origin ADD COLUMN needs_replay boolean;

    UPDATE _del_origin d
       SET needs_replay = d.has_null_utc OR d.min_utc IS NULL OR EXISTS (
            SELECT 1
              FROM public.roast_log rl2
              LEFT JOIN public.roast_recipes rr2 ON rr2.recipe_id = rl2.recipe_id
              LEFT JOIN public.facilities f2 ON f2.facility_id = rl2.facility_id
             WHERE rl2.facility_id = d.facility_id
               AND rl2."charged?" = true
               AND COALESCE(rl2.charge_weight_lbs, 0) > 0
               AND NOT (rl2.roast_log_id = ANY(p_roast_log_ids))
               AND (rl2.external_roast_id IS NOT NULL
                    OR rl2.roast_date >= (rl2.created_at::date - interval '1 day'))
               AND COALESCE(rl2.roast_date_utc,
                            (rl2.roast_date AT TIME ZONE COALESCE(NULLIF(f2.time_zone, ''), 'UTC'))) >= d.min_utc
               AND (
                    (rl2.borrow_origin_purchase_id IS NULL AND (
                        (rr2.roast_type = 'Pre-Blend'
                           AND EXISTS (SELECT 1 FROM public.recipe_components rc
                                        WHERE rc.recipe_id = rl2.recipe_id
                                          AND rc.coffee_item = d.origin
                                          AND COALESCE(rc.percentage, 0) > 0))
                        OR ((rr2.roast_type IS NULL OR rr2.roast_type <> 'Pre-Blend')
                              AND rl2.origin_id = d.origin)))
                    OR (rl2.borrow_origin_purchase_id IS NOT NULL
                          AND EXISTS (SELECT 1 FROM public.coffee_inventory_purchased b
                                       WHERE b.origin_purchase_id = rl2.borrow_origin_purchase_id
                                         AND b.origin = d.origin))
               )
       );

    -- FAST path: return each deleted roast's own consumed lbs to its lots — the
    -- exact inverse of _deduct_origin_fifo. Only for non-replay origins (a replay
    -- rebuilds remaining_lbs from scratch and would overwrite this anyway).
    UPDATE public.coffee_inventory_purchased cip
       SET remaining_lbs = COALESCE(cip.remaining_lbs, 0) + agg.lbs
      FROM (
        SELECT c.origin_purchase_id, SUM(c.lbs_consumed) AS lbs
          FROM _del_cons c
          JOIN _del_origin d ON d.origin = c.origin AND d.facility_id = c.facility_id
         WHERE d.needs_replay = false
         GROUP BY c.origin_purchase_id
      ) agg
     WHERE cip.origin_purchase_id = agg.origin_purchase_id;

    -- Delete the roasts with the O(n) lot-recompute suppressed. Cheap per-row
    -- triggers still fire (session cascade, inventory par-refresh, chaff);
    -- consumption rows + sessions/temp_nodes/events cascade away.
    PERFORM set_config('app.defer_lot_recompute', 'true', true);
    DELETE FROM public.roast_log WHERE roast_log_id = ANY(p_roast_log_ids);
    PERFORM set_config('app.defer_lot_recompute', 'false', true);

    -- Reconcile ONCE per affected origin. Replay origins rebuild lot truth; fast
    -- origins just refresh the total from the reversed remaining_lbs. Then
    -- refresh_coffee_stock_par gets the final say on in_stock/par/to_order/
    -- restock — same last-writer as the normal trg_roast_log_inventory_update.
    FOR v_o IN SELECT origin, facility_id, needs_replay FROM _del_origin LOOP
        IF v_o.needs_replay THEN
            PERFORM public.recompute_origin_lot_consumption(v_o.origin, v_o.facility_id);
        ELSE
            PERFORM public.recalculate_origin_total_stock(v_o.origin, v_o.facility_id);
        END IF;
        PERFORM public.refresh_coffee_stock_par(v_o.origin, v_o.facility_id);
    END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_roasts(text[]) TO authenticated;

NOTIFY pgrst, 'reload schema';
