-- Two gaps that look identical need opposite remedies. Say which is which.
--
-- Owner: "so does that mean if a roaster roasts all day and then goes back to
-- fix any out of stock mistakes that day or at the end of the week that doesn't
-- adjust the inventory". It does adjust it — and the dividing line is not the
-- calendar, it is the group's count anchor. Both cases measured on staging:
--
--   AFTER the anchor (the normal case — record the shipment you forgot)
--     roast needs 200, group holds 150.5  ->  shortfall 49.5
--     record a lot dated yesterday, 80 lb
--     -> shortfall 0, consumed 200.0, that lot's remaining 80 -> 30.5
--     Stock deducted. Trace restored. Nothing here needed building.
--
--   BEFORE the anchor
--     same setup, lot dated 5 days ago (the last count was 2 days ago)
--     -> that lot is re-seeded to 0 by the replay; shortfall stays 49.5
--     Recording the shipment achieves NOTHING, silently.
--
-- So the queue must never offer "record the shipment" for a pre-anchor gap: the
-- person would type it in, watch nothing happen, and have no way to know why.
-- Pre-anchor gaps get the naming remedy instead, whose honest promise is
-- narrower — it restores the trace and deliberately leaves the stock alone,
-- because a count already settled the stock.

begin;

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
           ci.origin as group_name,
           f.facility_name,
           a.anchor_at,
           -- The whole question, in one boolean: can a receipt still reach it?
           (a.anchor_at is not null
            and coalesce(rl.roast_date_utc, rl.roast_date::timestamptz) <= a.anchor_at) as pre_anchor
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
           max(group_name)    as group_name,
           max(facility_name) as facility_name,
           max(anchor_at)     as anchor_at,
           count(*) filter (where waived_at is null) as open_draws,
           round(sum(lbs_unmet) filter (where waived_at is null), 2) as lbs_unmet,
           -- Split by which remedy actually works.
           count(*) filter (where waived_at is null and not pre_anchor) as receipt_draws,
           round(coalesce(sum(lbs_unmet) filter (where waived_at is null and not pre_anchor), 0), 2) as receipt_lbs,
           count(*) filter (where waived_at is null and pre_anchor) as name_only_draws,
           round(coalesce(sum(lbs_unmet) filter (where waived_at is null and pre_anchor), 0), 2) as name_only_lbs,
           -- The date that goes in the received field: a receipt has to predate
           -- the roast it feeds, and postdate the anchor to survive the replay.
           min(roast_date) filter (where waived_at is null and not pre_anchor)::date as earliest_receiptable,
           min(roast_date)::date as earliest,
           max(roast_date)::date as latest,
           jsonb_agg(jsonb_build_object(
             'roast_log_id', roast_log_id,
             'roast_date',   roast_date,
             'recipe_name',  recipe_name,
             'coffee_name',  coffee_name,
             'lbs_needed',   lbs_needed,
             'lbs_unmet',    lbs_unmet,
             'pre_anchor',   pre_anchor,
             'waived_at',    waived_at,
             'waived_by_name', waived_by_name,
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
       'receipt_lbs',   coalesce((select round(sum(lbs_unmet), 2) from scoped where waived_at is null and not pre_anchor), 0),
       'name_only_lbs', coalesce((select round(sum(lbs_unmet), 2) from scoped where waived_at is null and pre_anchor), 0),
       'waived',    (select count(*) from scoped where waived_at is not null)),
    'groups', coalesce((
       select jsonb_agg(to_jsonb(g) order by g.lbs_unmet desc nulls last) from grouped g), '[]'::jsonb))
  into v_out;

  return v_out;
end;
$$;

comment on function public.unsourced_green_queue(text, text, boolean, int) is
  'Roasts with no green behind them, grouped by coffee and split by which remedy works: a receipt still reaches a post-anchor gap (and adjusts stock); a pre-anchor gap can only be named (trace restored, stock deliberately untouched).';

-- A repair must not silently do nothing. attribute_unsourced_roasts is the
-- naming path and stays available for both, but a caller that meant "record the
-- shipment" needs to know when that was never going to work.
commit;
