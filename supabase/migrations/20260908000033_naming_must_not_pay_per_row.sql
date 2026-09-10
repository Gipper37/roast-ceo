-- Naming a lot must not re-value the whole product catalogue, once per row.
--
-- Found by constructing the case prod will actually hit — a count landing on an
-- origin with a real backlog of pre-anchor gaps — which timed out with this
-- stack:
--
--   coffee_lot_count_recompute
--    -> recompute_origin_lot_consumption
--      -> attribute_after_stock_event            (the naming pass)
--        -> INSERT roast_log_lot_consumption
--          -> trg_value_lot_consumption          (per ROW)
--            -> value_roast_lot_consumption
--              -> UPDATE coffee_inventory.latest_roasted_cost
--                -> propagate_roasted_cost_change
--                  -> UPDATE products ...        <- statement timeout
--
-- The replay itself has always known this: recompute_origin_lot_consumption
-- sets app.defer_lot_valuation, does its work, values ONCE over the affected
-- roasts, then reconciles. The naming pass is invoked at the END of that
-- function, after those flags are cleared, so every row it inserted paid the
-- full cascade. On Maui Coffee Roasters that is 273 rows inside an operator's
-- count — the same hang the weekly anchor checkpoint exists to prevent, put
-- back by me in a different place.
--
-- The fix is the pattern that was already there: defer, insert, value once,
-- reconcile. Nothing about WHAT is named changes.

begin;

create or replace function public._attribute_unsourced_for_origin(
  p_company_id  text,
  p_facility_id text,
  p_origin_id   text,
  p_not_before  date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_anchor timestamptz;
  v_row    record;
  v_lot    record;
  v_take   numeric;
  v_left   numeric;
  v_named  numeric := 0;
  v_roasts text[] := '{}';
begin
  if p_company_id is null or p_facility_id is null or p_origin_id is null then
    return jsonb_build_object('roasts_repaired', 0, 'lbs_named', 0);
  end if;

  select max(clc.count_at) into v_anchor
    from public.coffee_lot_count clc
    join public.coffee_inventory_purchased cip on cip.origin_purchase_id = clc.origin_purchase_id
   where cip.origin = p_origin_id and cip.facility_id = p_facility_id;

  -- Never counted: nothing sealed, nothing unknowable, nothing to name.
  if v_anchor is null then
    return jsonb_build_object('roasts_repaired', 0, 'lbs_named', 0);
  end if;

  -- 🔴 Silence the per-row valuation for the duration. Every insert below
  -- otherwise fires trg_value_lot_consumption -> coffee_inventory ->
  -- propagate_roasted_cost_change -> UPDATE products, which is a whole-catalogue
  -- write per named lot. Same flag, same reason, as the replay above us.
  perform set_config('app.defer_lot_valuation', 'true', true);
  perform set_config('app.defer_shipment_recompute', 'true', true);

  for v_row in
    select s.roast_log_id, s.origin_id, s.facility_id, s.lbs_unmet, rl.roast_date
      from public.roast_lot_shortfall s
      join public.roast_log rl on rl.roast_log_id = s.roast_log_id
     where s.company_id  = p_company_id
       and s.facility_id = p_facility_id
       and s.origin_id   = p_origin_id
       and s.waived_at is null
       -- A post-anchor gap is a real finding, not a gap to fill.
       and coalesce(rl.roast_date_utc, rl.roast_date::timestamptz) <= v_anchor
       and (p_not_before is null or rl.roast_date::date >= p_not_before)
     order by rl.roast_date asc
  loop
    v_left := v_row.lbs_unmet;

    for v_lot in
      select cip.origin_purchase_id,
             cip.amount - coalesce((
               select sum(c.lbs_consumed) from public.roast_log_lot_consumption c
                where c.origin_purchase_id = cip.origin_purchase_id), 0) as headroom
        from public.coffee_inventory_purchased cip
        left join public.shipment_received sr on sr.shipment_id = cip.shipment_id
       where cip.facility_id = v_row.facility_id
         and cip.origin = v_row.origin_id
         and coalesce(cip.amount, 0) > 0
         and coalesce(sr.date_received, cip.created_at::date) <= v_row.roast_date::date
         and coalesce(sr.voided, false) = false
       order by coalesce(sr.date_received, cip.created_at::date) asc, cip.created_at asc
    loop
      exit when v_left <= 0.01;
      if coalesce(v_lot.headroom, 0) <= 0.01 then continue; end if;
      v_take := least(v_lot.headroom, v_left);
      insert into public.roast_log_lot_consumption
        (roast_log_id, origin_purchase_id, lbs_consumed, attribution_only)
      values (v_row.roast_log_id, v_lot.origin_purchase_id, round(v_take, 4), true);
      v_left  := v_left - v_take;
      v_named := v_named + v_take;
    end loop;

    if v_left < v_row.lbs_unmet then
      if not (v_row.roast_log_id = any(v_roasts)) then
        v_roasts := v_roasts || v_row.roast_log_id;
      end if;
      if v_left <= 0.01 then
        delete from public.roast_lot_shortfall
         where roast_log_id = v_row.roast_log_id and origin_id = v_row.origin_id
           and facility_id = v_row.facility_id;
      else
        update public.roast_lot_shortfall set lbs_unmet = round(v_left, 4), as_of = now()
         where roast_log_id = v_row.roast_log_id and origin_id = v_row.origin_id
           and facility_id = v_row.facility_id;
      end if;
    end if;
  end loop;

  -- Value ONCE over everything named, with the flags still set so the roast_log
  -- cost writes do not fire the per-roast triggers either — exactly the order
  -- recompute_origin_lot_consumption uses.
  if array_length(v_roasts, 1) > 0 then
    perform public.value_roasts_lot_consumption(v_roasts);
  end if;

  perform set_config('app.defer_lot_valuation', 'false', true);
  perform set_config('app.defer_shipment_recompute', 'false', true);

  -- One reconcile per origin, for what the deferred triggers would have done
  -- row by row.
  if array_length(v_roasts, 1) > 0 then
    perform public.recalculate_inventory_cost(p_origin_id, p_facility_id);
  end if;

  return jsonb_build_object(
    'roasts_repaired', coalesce(array_length(v_roasts, 1), 0),
    'lbs_named', round(v_named, 2));
end;
$$;

commit;
