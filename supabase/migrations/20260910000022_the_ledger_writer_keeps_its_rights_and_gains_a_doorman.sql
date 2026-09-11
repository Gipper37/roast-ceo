-- The ledger writer keeps its rights and gains a doorman.
--
-- 20260910000021 made the two cost-ledger writers SECURITY DEFINER and revoked
-- EXECUTE from authenticated, on the reasoning that nothing calls them directly
-- so no RPC surface was needed. That was wrong in a way the test caught
-- immediately: four of their five callers are SECURITY INVOKER triggers
-- (trg_revalue_roasts_on_cost_change, trg_value_lot_consumption,
-- _recompute_origin_lot_consumption_core, save_shipment_lines). A trigger
-- FUNCTION runs without its invoker holding EXECUTE, but a function it calls in
-- turn does not — so the revoke turned an accounting_admin's cost correction
-- from "silently skips the ledger" into "permission denied for function
-- value_roast_lot_consumption", which is louder but no more correct.
--
-- EXECUTE goes back, and the entry point gets the guard it should have had with
-- definer rights in the first place: with a JWT present, every roast named must
-- belong to a company the caller is in. Triggers pass it (they act on rows RLS
-- already let the caller write); a crafted RPC against another tenant does not.

begin;

grant execute on function public.value_roast_lot_consumption(text)    to authenticated, service_role;
grant execute on function public.value_roasts_lot_consumption(text[]) to authenticated, service_role;

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

    -- b. roll up to roast_log (NULL when no ledger rows)
    SELECT SUM(lot_cost)
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
               (SELECT SUM(x.lot_cost) FROM public.roast_log_lot_consumption x
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

comment on function public.value_roast_lot_consumption(text) is
  'Rewrites a roast''s cost ledger after a green cost changes. SECURITY DEFINER because it is system bookkeeping fired by a trigger — the operator correcting the cost need not also hold roast.log — with an explicit tenancy test standing in for the RLS it no longer runs under.';

commit;
