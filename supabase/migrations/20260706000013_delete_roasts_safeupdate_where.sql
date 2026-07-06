-- Fix: delete_roasts failed on EVERY real call via PostgREST with
-- "21000: UPDATE requires a WHERE clause". Supabase's REST connection enables
-- pg_safeupdate, which rejects any UPDATE lacking a WHERE clause. The
-- needs_replay UPDATE intentionally rewrites every row of the temp table, so it
-- had no WHERE — fine under a direct psql connection (no guard), but rejected
-- through the REST API, so delete_roasts (single + bulk) errored in the app even
-- though it passed every psql-based test.
--
-- Only change vs 20260706000011: add an explicit WHERE to that one UPDATE.
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
       )
     WHERE true;  -- update every row; explicit WHERE satisfies pg_safeupdate (REST)

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

    PERFORM set_config('app.defer_lot_recompute', 'true', true);
    DELETE FROM public.roast_log WHERE roast_log_id = ANY(p_roast_log_ids);
    PERFORM set_config('app.defer_lot_recompute', 'false', true);

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

NOTIFY pgrst, 'reload schema';
