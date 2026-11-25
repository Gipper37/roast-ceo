-- ============================================================
-- An unpriced lot makes the roast's cost UNKNOWN, not zero.
-- ============================================================
--
-- 🔴 WHAT WAS WRONG. `roast_log_lot_consumption.lot_cost` is a GENERATED
-- column:
--     lbs_consumed * (COALESCE(green_cost_lb, 0) + COALESCE(shipping_cost_lb, 0))
-- so a lot whose purchase has no recorded `cost_lb` is valued at $0/lb rather
-- than as unknown. Both valuation functions then did a plain SUM(lot_cost),
-- which produced a perfectly plausible `green_cost`, and `roasted_cost_lb`
-- divided it by the FULL roasted weight -- including the yield of the coffee
-- just counted as free. Nothing read as missing: 0 affected roasts carried a
-- NULL cost.
--
-- Measured on prod 2026-11-25: 812 roasts, 15,942 lbs of green valued as free,
-- ~4% of all consumption. Example, roast 56b8b7eb: lots of 33.75 lb @ $4.60
-- and 33.75 lb @ $4.62 contributed $166.52 and $167.20, and a third lot of
-- 7.5 lb with no price contributed exactly 0.0000.
--
-- 🔴 THIS IS NOT A NEW RULE -- IT IS THE ONE THE READERS ALREADY FOLLOW.
-- `get_origin_roasted_cost_on_date` and `origin_roasted_cost_on_dates` both
-- filter `rlc.green_cost_lb IS NOT NULL`, and the first carries a comment
-- saying why: "was `rlc.lot_cost IS NOT NULL` -- cost-blind: generated
-- lot_cost COALESCEs a NULL green cost to 0, so uncosted lots passed the
-- guard". `recipe_actual_cost_lb` computes `bool_or(green_cost_lb is null) as
-- unpriced` and refuses to call such a roast usable. The two WRITERS were the
-- holdouts.
--
-- WHY `bool_or`, AND WHY IT IS SAFE FOR A ROAST WITH NO LEDGER ROWS.
-- Over zero rows bool_or returns NULL, which is not TRUE, so the CASE takes
-- its ELSE branch and SUM over zero rows returns NULL -- exactly the previous
-- behaviour, which the comment "NULL when no ledger rows" relies on.
--
-- NO BACKFILL HERE, DELIBERATELY. `roast_log` carries 13 UPDATE triggers
-- (lot-consumption recompute, inventory update, closed-period guard, audit);
-- re-stamping 812 rows in this transaction fires all of them and is precisely
-- the cascade that blew the 120s statement_timeout and rolled a release back
-- during the freight work. Existing rows correct themselves the next time each
-- roast is valued -- and entering a missing price does exactly that, via
-- `trg_revalue_roasts_on_cost_change`, with the REAL number rather than NULL.
--
-- Both bodies below are `pg_get_functiondef` output with ONE term changed.
-- Nothing was retyped. CREATE OR REPLACE preserves ownership and privileges,
-- and both keep their own SECURITY DEFINER and search_path settings.
--
-- No new column, no new permission key: nothing to grant.

begin;

CREATE OR REPLACE FUNCTION public.value_roast_lot_consumption(p_roast_log_id text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_total_green numeric;
    v_roasted_lbs numeric;
    v_facility    text;
    v_origin      text;
    v_new_cost    numeric;
    v_roast_date  date;
    v_closed      date;
BEGIN
    -- 🔴 A ROAST THAT NO LONGER EXISTS IS NOT SOMEBODY ELSE'S ROAST.
    -- This fires AFTER DELETE on roast_log_lot_consumption, and deleting a roast
    -- cascades to exactly those rows -- by which point the parent roast_log row
    -- is already gone. The doorman below then found no row, concluded the roast
    -- was not the caller's, and raised: so deleting any roast that had ever
    -- consumed green was impossible for every signed-in user, on every tenant.
    -- 15,536 roasts were in that state when this was found. Service role and
    -- cron carry no JWT and skipped the check, which is why nothing caught it.
    -- There is nothing to value for a row that is gone, so leave quietly.
    IF NOT EXISTS (SELECT 1 FROM public.roast_log WHERE roast_log_id = p_roast_log_id) THEN
        RETURN;
    END IF;

    -- Definer rights, so say whose roast this is. Service role and cron carry
    -- no JWT and are already trusted.
    IF auth.uid() IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.roast_log rl
         WHERE rl.roast_log_id = p_roast_log_id
           AND rl.company_id IN (SELECT public.auth_company_ids())
    ) THEN
        RAISE EXCEPTION 'That roast is not yours.' USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- Books-closed guard: freeze a roast's cost once its period is closed.
    SELECT rl.roast_date, c.books_closed_through
      INTO v_roast_date, v_closed
      FROM public.roast_log rl
      LEFT JOIN public.companies c ON c.company_id = rl.company_id
     WHERE rl.roast_log_id = p_roast_log_id;
    IF v_closed IS NOT NULL AND v_roast_date IS NOT NULL AND v_roast_date <= v_closed THEN
        RETURN;
    END IF;

    -- a. snapshot each ledger row's green + shipping cost from its lot
    UPDATE public.roast_log_lot_consumption rlc
    SET green_cost_lb    = cip.cost_lb,
        shipping_cost_lb = COALESCE(sr.shipping_cost_unit, 0)
    FROM public.coffee_inventory_purchased cip
    LEFT JOIN public.shipment_received sr ON sr.shipment_id = cip.shipment_id
    WHERE rlc.roast_log_id = p_roast_log_id
      AND cip.origin_purchase_id = rlc.origin_purchase_id;

    -- b. roll up to roast_log (NULL when no ledger rows, and NULL when ANY
    --    lot has no green price -- see the header).
    SELECT CASE WHEN bool_or(green_cost_lb IS NULL) THEN NULL ELSE SUM(lot_cost) END
      INTO v_total_green
      FROM public.roast_log_lot_consumption
     WHERE roast_log_id = p_roast_log_id;

    SELECT COALESCE(rl.measured_roasted_weight,
                    rl.roasted_weight,
                    rl.charge_weight_lbs * COALESCE(public.get_retention_factor(rl.facility_id, rl.recipe_id), 0.82)),
           rl.facility_id
      INTO v_roasted_lbs, v_facility
      FROM public.roast_log rl
     WHERE rl.roast_log_id = p_roast_log_id;

    UPDATE public.roast_log rl
    SET green_cost      = v_total_green,
        roasted_cost_lb = CASE WHEN v_total_green IS NOT NULL AND COALESCE(v_roasted_lbs,0) > 0
                               THEN v_total_green / v_roasted_lbs
                               ELSE NULL END
    WHERE rl.roast_log_id = p_roast_log_id;

    -- c. refresh cached per-origin roasted cost (once per origin)
    FOR v_origin IN
        SELECT DISTINCT cip.origin
          FROM public.roast_log_lot_consumption rlc
          JOIN public.coffee_inventory_purchased cip ON cip.origin_purchase_id = rlc.origin_purchase_id
         WHERE rlc.roast_log_id = p_roast_log_id
    LOOP
        v_new_cost := public.get_origin_roasted_cost_on_date(v_origin, v_facility, CURRENT_DATE);
        UPDATE public.coffee_inventory ci
        SET latest_roasted_cost = v_new_cost
        WHERE ci.origin_id   = v_origin
          AND ci.facility_id = v_facility
          AND ci.latest_roasted_cost IS DISTINCT FROM v_new_cost;
    END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.value_roasts_lot_consumption(p_roast_ids text[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_open text[];
    v_o record;
    v_new_cost numeric;
BEGIN
    IF p_roast_ids IS NULL OR array_length(p_roast_ids, 1) IS NULL THEN RETURN; END IF;

    -- Definer rights, so say whose roasts these are.
    IF auth.uid() IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.roast_log rl
         WHERE rl.roast_log_id = ANY(p_roast_ids)
           AND rl.company_id NOT IN (SELECT public.auth_company_ids())
    ) THEN
        RAISE EXCEPTION 'Those roasts are not all yours.' USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- Books-closed guard, set-based: only open-period roasts get revalued.
    SELECT COALESCE(array_agg(rl.roast_log_id), ARRAY[]::text[]) INTO v_open
      FROM public.roast_log rl
      LEFT JOIN public.companies c ON c.company_id = rl.company_id
     WHERE rl.roast_log_id = ANY(p_roast_ids)
       AND NOT (c.books_closed_through IS NOT NULL
                AND rl.roast_date IS NOT NULL
                AND rl.roast_date::date <= c.books_closed_through);
    IF array_length(v_open, 1) IS NULL THEN RETURN; END IF;

    -- a. snapshot each ledger row's green + shipping cost from its lot
    --    (lot_cost is GENERATED from these, so it follows automatically).
    UPDATE public.roast_log_lot_consumption rlc
       SET green_cost_lb    = cip.cost_lb,
           shipping_cost_lb = COALESCE(sr.shipping_cost_unit, 0)
      FROM public.coffee_inventory_purchased cip
      LEFT JOIN public.shipment_received sr ON sr.shipment_id = cip.shipment_id
     WHERE rlc.roast_log_id = ANY(v_open)
       AND cip.origin_purchase_id = rlc.origin_purchase_id;

    -- b. roll up to roast_log (green_cost NULL when a roast has no rows left)
    UPDATE public.roast_log rl
       SET green_cost      = agg.total_green,
           roasted_cost_lb = CASE WHEN agg.total_green IS NOT NULL AND COALESCE(agg.roasted_lbs, 0) > 0
                                  THEN agg.total_green / agg.roasted_lbs
                                  ELSE NULL END
      FROM (
        SELECT rl2.roast_log_id,
               (SELECT CASE WHEN bool_or(x.green_cost_lb IS NULL) THEN NULL
                            ELSE SUM(x.lot_cost) END
                  FROM public.roast_log_lot_consumption x
                 WHERE x.roast_log_id = rl2.roast_log_id) AS total_green,
               COALESCE(rl2.measured_roasted_weight,
                        rl2.roasted_weight,
                        rl2.charge_weight_lbs * COALESCE(public.get_retention_factor(rl2.facility_id, rl2.recipe_id), 0.82)) AS roasted_lbs
          FROM public.roast_log rl2
         WHERE rl2.roast_log_id = ANY(v_open)
      ) agg
     WHERE rl.roast_log_id = agg.roast_log_id;

    -- c. refresh cached per-origin roasted cost once per distinct (origin, facility)
    FOR v_o IN
        SELECT DISTINCT cip.origin, rl.facility_id
          FROM public.roast_log_lot_consumption rlc
          JOIN public.coffee_inventory_purchased cip ON cip.origin_purchase_id = rlc.origin_purchase_id
          JOIN public.roast_log rl ON rl.roast_log_id = rlc.roast_log_id
         WHERE rlc.roast_log_id = ANY(v_open)
           AND cip.origin IS NOT NULL AND rl.facility_id IS NOT NULL
    LOOP
        v_new_cost := public.get_origin_roasted_cost_on_date(v_o.origin, v_o.facility_id, CURRENT_DATE);
        UPDATE public.coffee_inventory ci
           SET latest_roasted_cost = v_new_cost
         WHERE ci.origin_id = v_o.origin
           AND ci.facility_id = v_o.facility_id
           AND ci.latest_roasted_cost IS DISTINCT FROM v_new_cost;
    END LOOP;
END;
$function$;

-- ============================================================
-- Verify. Can raise, and can pass.
-- ============================================================
do $verify$
declare
    v_singular text := pg_get_functiondef('public.value_roast_lot_consumption(text)'::regprocedure);
    v_plural   text := pg_get_functiondef('public.value_roasts_lot_consumption(text[])'::regprocedure);
    v_probe    text;
    v_result   numeric;
begin
    -- 1. the guard is present in both
    IF v_singular !~ 'bool_or\(green_cost_lb IS NULL\)' THEN
        RAISE EXCEPTION 'value_roast_lot_consumption did not get the unpriced guard';
    END IF;
    IF v_plural !~ 'bool_or\(x\.green_cost_lb IS NULL\)' THEN
        RAISE EXCEPTION 'value_roasts_lot_consumption did not get the unpriced guard';
    END IF;

    -- 2. the unguarded shape is gone from both
    IF v_singular ~ 'SELECT SUM\(lot_cost\)' THEN
        RAISE EXCEPTION 'value_roast_lot_consumption still sums lot_cost unguarded';
    END IF;
    IF v_plural ~ 'SELECT SUM\(x\.lot_cost\) FROM' THEN
        RAISE EXCEPTION 'value_roasts_lot_consumption still sums lot_cost unguarded';
    END IF;

    -- 3. behavioural, where the data allows it. NEGATIVE control: a roast with
    --    an unpriced lot must roll up to NULL.
    SELECT roast_log_id INTO v_probe
      FROM public.roast_log_lot_consumption
     WHERE green_cost_lb IS NULL
     LIMIT 1;
    IF v_probe IS NOT NULL THEN
        SELECT CASE WHEN bool_or(green_cost_lb IS NULL) THEN NULL ELSE SUM(lot_cost) END
          INTO v_result
          FROM public.roast_log_lot_consumption WHERE roast_log_id = v_probe;
        IF v_result IS NOT NULL THEN
            RAISE EXCEPTION 'the new rollup still returns a number for unpriced roast %', v_probe;
        END IF;
    END IF;

    -- 4. POSITIVE control: a fully priced roast must still roll up to a number.
    --    Without this, a rollup that returned NULL for EVERYTHING would pass.
    SELECT roast_log_id INTO v_probe
      FROM public.roast_log_lot_consumption
     GROUP BY roast_log_id
    HAVING bool_or(green_cost_lb IS NULL) IS NOT TRUE
       AND SUM(lot_cost) > 0
     LIMIT 1;
    IF v_probe IS NOT NULL THEN
        SELECT CASE WHEN bool_or(green_cost_lb IS NULL) THEN NULL ELSE SUM(lot_cost) END
          INTO v_result
          FROM public.roast_log_lot_consumption WHERE roast_log_id = v_probe;
        IF v_result IS NULL THEN
            RAISE EXCEPTION 'the new rollup returns NULL for fully priced roast %', v_probe;
        END IF;
    END IF;
end
$verify$;

commit;
