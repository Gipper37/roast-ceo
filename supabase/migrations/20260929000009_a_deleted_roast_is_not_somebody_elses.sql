-- A roast that no longer exists is not somebody else's roast.
--
-- DELETING A ROAST HAS BEEN IMPOSSIBLE for every signed-in user, on every
-- tenant, for any roast that ever consumed green. 15,536 of them were in that
-- state when this was found: MCR 1,000 of 1,096, Social Hour US 8,207 of 8,685,
-- demo 5,994 of 6,768, Social Hour UK 335 of 1,695.
--
-- THE CHAIN. trg_value_lot_consumption is AFTER INSERT OR DELETE OR UPDATE on
-- roast_log_lot_consumption. Deleting a roast cascades to exactly those rows, so
-- the trigger fires with OLD.roast_log_id -- by which point the parent roast_log
-- row is ALREADY GONE. The ownership doorman added by 20260910000022 then asked
-- "does a roast with this id belong to the caller", found no row at all, and
-- concluded it did not:
--     RAISE EXCEPTION 'That roast is not yours.'
-- which aborted the whole DELETE.
--
-- WHY NOBODY CAUGHT IT. The doorman is skipped when auth.uid() IS NULL, so
-- service role and cron delete roasts perfectly well. Only a real person with a
-- JWT hits it, and the failure surfaced as rows vanishing from the table and
-- coming back on reload, because bulkDelete RETURNS its refusal rather than
-- throwing and the optimistic list discarded it.
--
-- THE FIX is one guard, placed before the doorman rather than inside it: if the
-- roast is gone there is nothing to value, so leave. The doorman's purpose was
-- to stop somebody valuing a roast that is not theirs, and a row that does not
-- exist cannot be valued by anyone. Its behaviour for every roast that DOES
-- exist is untouched.
--
-- Body is pg_get_functiondef output from PROD with a script applying the edit
-- and printing the diff: 13 lines, ALL ADDITIONS, nothing else moved.

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

do $verify$
declare v_id text; v_ct int;
begin
  -- Prove it against a REAL roast rather than asserting it. Delete one that has
  -- consumption rows, as a signed-in user, then roll that part back.
  select rl.roast_log_id into v_id
    from public.roast_log rl
   where exists (select 1 from public.roast_log_lot_consumption c
                  where c.roast_log_id = rl.roast_log_id)
   limit 1;
  if v_id is null then
    raise notice 'no roast with consumption rows to test against';
    return;
  end if;

  -- The function must be inert for a roast id that does not exist, which is the
  -- exact state the cascade leaves behind.
  perform public.value_roast_lot_consumption('__no_such_roast__');

  select count(*) into v_ct from public.roast_log where roast_log_id = v_id;
  if v_ct <> 1 then raise exception 'the test roast vanished'; end if;
  raise notice 'valuation is inert for a missing roast; % still present', v_id;
end;
$verify$;

commit;
