-- A received date is a fact. Attribution follows it; it does not chase attribution.
--
-- 20260908000021 got this wrong in two ways and this migration undoes both.
--
--  1. It reported `earliest_receiptable` — "the date that goes in the received
--     field". That invites somebody to pick a receipt date that makes the FIFO
--     work instead of the date the coffee actually turned up. A shipment was
--     received when it was received; it also feeds COGS and the supplier record,
--     and those stay valid whatever a later count did to the stock arithmetic.
--     The field is gone.
--
--  2. It framed the count anchor as something to route around — "which remedy
--     works". The anchor is not a defect. A manual count RESETS what is on hand;
--     that is the entire point of taking one, and a later count outranking an
--     earlier one is the correct order of truth. Nothing here changes it.
--
-- What was actually missing is smaller and duller: when you record something
-- dated behind a count, the system quietly did half the job and said nothing.
-- So now it does the other half automatically, and says which half it did.
--
--   window OPEN  (dated after the group's last count)
--     -> stock moves AND the roasts get their lots. Unchanged, always worked.
--   window CLOSED (dated before it)
--     -> stock does not move — that count is still the truth — but the roasts
--        that drew on this coffee now get their lots named. Automatically.
--
-- Either way the user enters one true fact and the system does what follows.

begin;

-- ── 1. The engine half of the naming pass, without the permission gate ─────
-- Called both by the operator-facing RPC (which checks trace.reconcile first)
-- and by the receipt/count triggers, which have no operator to check.
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

  for v_row in
    select s.roast_log_id, s.origin_id, s.facility_id, s.lbs_unmet, rl.roast_date
      from public.roast_lot_shortfall s
      join public.roast_log rl on rl.roast_log_id = s.roast_log_id
     where s.company_id  = p_company_id
       and s.facility_id = p_facility_id
       and s.origin_id   = p_origin_id
       and s.waived_at is null
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

  if array_length(v_roasts, 1) > 0 then
    perform public.value_roasts_lot_consumption(v_roasts);
  end if;

  return jsonb_build_object(
    'roasts_repaired', coalesce(array_length(v_roasts, 1), 0),
    'lbs_named', round(v_named, 2));
end;
$$;

revoke all on function public._attribute_unsourced_for_origin(text, text, text, date) from public;
grant execute on function public._attribute_unsourced_for_origin(text, text, text, date) to authenticated;

-- The operator-facing RPC now delegates, so there is one naming implementation.
create or replace function public.attribute_unsourced_roasts(
  p_company_id  text,
  p_facility_id text default null,
  p_origin_id   text default null,
  p_roast_ids   text[] default null,
  p_from        date default null,
  p_to          date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_pair   record;
  v_res    jsonb;
  v_roasts int := 0;
  v_lbs    numeric := 0;
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'Not your company.' using errcode = 'insufficient_privilege';
  end if;
  if not public.auth_has_permission('trace.reconcile', p_company_id) then
    raise exception 'You do not have permission to reconcile lots.' using errcode = 'insufficient_privilege';
  end if;

  for v_pair in
    select distinct s.origin_id, s.facility_id
      from public.roast_lot_shortfall s
      join public.roast_log rl on rl.roast_log_id = s.roast_log_id
     where s.company_id = p_company_id
       and s.waived_at is null
       and (p_facility_id is null or s.facility_id  = p_facility_id)
       and (p_origin_id   is null or s.origin_id    = p_origin_id)
       and (p_roast_ids   is null or s.roast_log_id = any(p_roast_ids))
       and (p_from is null or rl.roast_date::date >= p_from)
       and (p_to   is null or rl.roast_date::date <= p_to)
  loop
    perform pg_advisory_xact_lock(hashtext(v_pair.origin_id), hashtext(v_pair.facility_id));
    v_res := public._attribute_unsourced_for_origin(
               p_company_id, v_pair.facility_id, v_pair.origin_id, p_from);
    v_roasts := v_roasts + (v_res->>'roasts_repaired')::int;
    v_lbs    := v_lbs    + (v_res->>'lbs_named')::numeric;
  end loop;

  return jsonb_build_object('roasts_repaired', v_roasts, 'lbs_named', round(v_lbs, 2));
end;
$$;

-- ── 2. Naming follows a receipt or a count, by itself ──────────────────────
-- Recording the shipment that actually arrived, or the count that was actually
-- taken, is the operator's whole job here. Making them then press a second
-- button called "repair" to get the consequence of the fact they just entered
-- is asking them to do the software's work.
create or replace function public.attribute_after_stock_event(
  p_company_id  text,
  p_facility_id text,
  p_origin_id   text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- Cheap guard: almost every stock event touches an origin with nothing open.
  if not exists (
    select 1 from public.roast_lot_shortfall
     where company_id = p_company_id and facility_id = p_facility_id
       and origin_id = p_origin_id and waived_at is null
     limit 1) then
    return;
  end if;
  perform public._attribute_unsourced_for_origin(p_company_id, p_facility_id, p_origin_id, null);
end;
$$;

revoke all on function public.attribute_after_stock_event(text, text, text) from public;
grant execute on function public.attribute_after_stock_event(text, text, text) to authenticated;

-- ── 3. What entering this date will actually do ────────────────────────────
-- For the count modal and the shipment editor, so the sentence they show is
-- computed from the same anchor the engine uses rather than guessed in React.
create or replace function public.trace_impact_of_date(
  p_company_id  text,
  p_facility_id text,
  p_origin_id   text,
  p_date        date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_anchor timestamptz;
  v_roasts int;
  v_lbs    numeric;
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'Not your company.' using errcode = 'insufficient_privilege';
  end if;

  select max(clc.count_at) into v_anchor
    from public.coffee_lot_count clc
    join public.coffee_inventory_purchased cip on cip.origin_purchase_id = clc.origin_purchase_id
   where cip.origin = p_origin_id and cip.facility_id = p_facility_id;

  -- Roasts on this coffee that are still missing green and that a lot dated
  -- p_date could account for (it has to have been here before they ran).
  select count(*), coalesce(sum(s.lbs_unmet), 0) into v_roasts, v_lbs
    from public.roast_lot_shortfall s
    join public.roast_log rl on rl.roast_log_id = s.roast_log_id
   where s.company_id = p_company_id and s.facility_id = p_facility_id
     and s.origin_id = p_origin_id and s.waived_at is null
     and rl.roast_date::date >= p_date;

  return jsonb_build_object(
    'anchor_at',        v_anchor,
    -- False when a later count already settled what is on hand. Not a problem
    -- to route around: that count is the physical truth and outranks this.
    'adjusts_stock',    (v_anchor is null or p_date >= v_anchor::date),
    'roasts_named',     v_roasts,
    'lbs_named',        round(v_lbs, 2));
end;
$$;

revoke all on function public.trace_impact_of_date(text, text, text, date) from public;
grant execute on function public.trace_impact_of_date(text, text, text, date) to authenticated;

-- ── 4. Drop the date suggestion from the queue ─────────────────────────────
-- Keeping `adjusts_stock` per group so a surface can EXPLAIN an outcome; the
-- prescriptive fields that told somebody what date to type are gone.
create or replace function public.unsourced_green_queue(
  p_company_id  text,
  p_facility_id text default null,
  p_include_waived boolean default false,
  p_limit_per_group int default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_start date;
  v_out   jsonb;
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'Not your company.' using errcode = 'insufficient_privilege';
  end if;
  if not public.auth_has_permission('trace.reconcile', p_company_id) then
    raise exception 'You do not have permission to see lot reconciliation.'
      using errcode = 'insufficient_privilege';
  end if;

  select trace_start_date into v_start from public.fs_settings where company_id = p_company_id;

  with anchors as (
    select cip.origin as origin_id, cip.facility_id, max(clc.count_at) as anchor_at
      from public.coffee_lot_count clc
      join public.coffee_inventory_purchased cip on cip.origin_purchase_id = clc.origin_purchase_id
     group by cip.origin, cip.facility_id
  ), scoped as (
    select s.*, rl.roast_date,
           coalesce(rl.recipe_name_snapshot, rr.recipe_name) as recipe_name,
           coalesce(rl.coffee_name_snapshot, ci.origin)      as coffee_name,
           ci.origin as group_name, f.facility_name, a.anchor_at
      from public.roast_lot_shortfall s
      join public.roast_log rl on rl.roast_log_id = s.roast_log_id
      left join public.roast_recipes rr on rr.recipe_id = rl.recipe_id
      left join public.coffee_inventory ci
             on ci.origin_id = s.origin_id and ci.facility_id = s.facility_id
      left join public.facilities f on f.facility_id = s.facility_id
      left join anchors a on a.origin_id = s.origin_id and a.facility_id = s.facility_id
     where s.company_id = p_company_id
       and (p_facility_id is null or s.facility_id = p_facility_id)
       and (p_include_waived or s.waived_at is null)
       and (v_start is null or rl.roast_date::date >= v_start)
  ), ranked as (
    select scoped.*, row_number() over (
             partition by origin_id, facility_id order by roast_date asc) as rn
      from scoped
  ), grouped as (
    select origin_id, facility_id,
           max(group_name) as group_name, max(facility_name) as facility_name,
           max(anchor_at)  as anchor_at,
           count(*) filter (where waived_at is null) as open_draws,
           round(sum(lbs_unmet) filter (where waived_at is null), 2) as lbs_unmet,
           min(roast_date)::date as earliest,
           max(roast_date)::date as latest,
           jsonb_agg(jsonb_build_object(
             'roast_log_id', roast_log_id, 'roast_date', roast_date,
             'recipe_name',  recipe_name,  'coffee_name', coffee_name,
             'lbs_needed',   lbs_needed,   'lbs_unmet',  lbs_unmet,
             'waived_at',    waived_at,    'waived_by_name', waived_by_name,
             'waive_reason', waive_reason
           ) order by roast_date asc) filter (where rn <= p_limit_per_group) as roasts
      from ranked
     group by origin_id, facility_id
  )
  select jsonb_build_object(
    'trace_start_date', v_start,
    'totals', jsonb_build_object(
       'groups',    (select count(*) from grouped),
       'roasts',    (select count(distinct roast_log_id) from scoped where waived_at is null),
       'lbs_unmet', coalesce((select round(sum(lbs_unmet), 2) from scoped where waived_at is null), 0),
       'waived',    (select count(*) from scoped where waived_at is not null)),
    'groups', coalesce((
       select jsonb_agg(to_jsonb(g) order by g.lbs_unmet desc nulls last) from grouped g), '[]'::jsonb))
  into v_out;

  return v_out;
end;
$$;

commit;
