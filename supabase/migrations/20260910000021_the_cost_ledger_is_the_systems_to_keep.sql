-- The cost ledger is the system's to keep, not the operator's to be refused.
--
-- Owner, 2026-09-11, asked whether it matters which identity the revaluation
-- runs as. It does, and this is the case that shows why.
--
-- When a green purchase's cost is corrected, trg_revalue_roasts_on_cost_change
-- fires value_roast_lot_consumption, which rewrites roast_log_lot_consumption
-- and roast_log so every affected roast carries its true cost. That chain is
-- SECURITY INVOKER, so it ran with the correcting operator's rights — and since
-- 20260910000017 gates those tables on roast.log, an accounting_admin (who
-- holds inventory.purchase and not roast.log) had the purchase price saved and
-- the cost ledger silently skipped. Not an error: RLS turns a refused UPDATE
-- into zero rows, so nothing was raised and nothing was logged. The books just
-- quietly stopped agreeing with the purchase.
--
-- Derived data should be maintained by the system regardless of who tripped the
-- recompute. Permission belongs on the ACT — correcting a cost needs
-- inventory.purchase, logging a roast needs roast.log — not on the bookkeeping
-- that follows from it. So the two functions that write the ledger become
-- SECURITY DEFINER.
--
-- The safety that makes that sound: neither is reachable as an RPC any more.
-- Nothing in either repo calls them (checked: 0 call sites each); they exist to
-- be fired by triggers, and a trigger only fires on a row the caller's own RLS
-- already let them write. Revoking EXECUTE from authenticated closes the
-- PostgREST surface that would otherwise come with definer rights, so there is
-- no argument-controlled entry point to reach another tenant through.

begin;

revoke execute on function public.value_roast_lot_consumption(text)  from authenticated, anon, public;
revoke execute on function public.value_roasts_lot_consumption(text[]) from authenticated, anon, public;

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
$function$

;

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
$function$

;

comment on function public.value_roast_lot_consumption(text) is
  'Rewrites a roast''s cost ledger after a green cost changes. SECURITY DEFINER since 20260910000021: it is system bookkeeping fired by a trigger, and the operator who corrected the cost need not also hold roast.log. Not granted to authenticated — there is no RPC surface.';

commit;
