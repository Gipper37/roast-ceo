-- The queue: which roasts have no green behind them, and what would fix it.
--
-- The mirror image of "Receipts to record", which is stock on hand with no
-- purchase behind it. This is roasts with no lot behind them. Same page, same
-- audience — whoever has the paperwork — and both remedies the owner named
-- (record the shipment, take a count) are already actions on that page.
--
-- Grouped by coffee, because the remedy is per coffee: one missing shipment
-- explains every short roast on that group at once. The date it reports is the
-- EARLIEST short roast, because a receipt has to be dated before the roast it
-- feeds — that date is the answer to "what do I type in the received field".
--
-- The window (fs_settings.trace_start_date) is applied HERE and not in the
-- ledger. Owner: "the recall needs a window. because for a user implementing
-- (MCR) they don't want all the old shit that didn't get recorded to show up on
-- the report negatively." The ledger records what is true; a surface decides
-- what is in scope. Those are different jobs and conflating them would mean
-- moving the window later rewrites history.

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

  with scoped as (
    select s.*, rl.roast_date, rl.recipe_id,
           coalesce(rl.recipe_name_snapshot, rr.recipe_name) as recipe_name,
           coalesce(rl.coffee_name_snapshot, ci.origin)      as coffee_name,
           ci.origin as group_name,
           f.facility_name
      from public.roast_lot_shortfall s
      join public.roast_log rl on rl.roast_log_id = s.roast_log_id
      left join public.roast_recipes rr on rr.recipe_id = rl.recipe_id
      left join public.coffee_inventory ci
             on ci.origin_id = s.origin_id and ci.facility_id = s.facility_id
      left join public.facilities f on f.facility_id = s.facility_id
     where s.company_id = p_company_id
       and (p_facility_id is null or s.facility_id = p_facility_id)
       and (p_include_waived or s.waived_at is null)
       -- Out of scope, not unanswered: everything before the tenant said the
       -- trace begins is pre-implementation history.
       and (v_start is null or rl.roast_date::date >= v_start)
  ), ranked as (
    select scoped.*, row_number() over (
             partition by origin_id, facility_id order by roast_date asc) as rn
      from scoped
  ), grouped as (
    select origin_id, facility_id,
           max(group_name)    as group_name,
           max(facility_name) as facility_name,
           count(*)                              as draws,
           count(*) filter (where waived_at is null) as open_draws,
           round(sum(lbs_unmet) filter (where waived_at is null), 2) as lbs_unmet,
           min(roast_date)::date as earliest,
           max(roast_date)::date as latest,
           jsonb_agg(jsonb_build_object(
             'roast_log_id', roast_log_id,
             'roast_date',   roast_date,
             'recipe_name',  recipe_name,
             'coffee_name',  coffee_name,
             'lbs_needed',   lbs_needed,
             'lbs_unmet',    lbs_unmet,
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
       'groups',     (select count(*) from grouped),
       'roasts',     (select count(distinct roast_log_id) from scoped where waived_at is null),
       'lbs_unmet',  coalesce((select round(sum(lbs_unmet), 2) from scoped where waived_at is null), 0),
       'waived',     (select count(*) from scoped where waived_at is not null)),
    'groups', coalesce((
       select jsonb_agg(to_jsonb(g) order by g.lbs_unmet desc nulls last) from grouped g), '[]'::jsonb))
  into v_out;

  return v_out;
end;
$$;

comment on function public.unsourced_green_queue(text, text, boolean, int) is
  'Roasts with no green behind them, grouped by coffee because the remedy is per coffee. Honours fs_settings.trace_start_date — pre-implementation history is out of scope, not a finding.';

revoke all on function public.unsourced_green_queue(text, text, boolean, int) from public;
grant execute on function public.unsourced_green_queue(text, text, boolean, int) to authenticated;

-- Setting the window is an admin decision about what the tenant claims to be
-- able to trace, so it rides on trace.waive rather than trace.reconcile.
create or replace function public.set_trace_start_date(p_company_id text, p_date date)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'Not your company.' using errcode = 'insufficient_privilege';
  end if;
  if not public.auth_has_permission('trace.waive', p_company_id) then
    raise exception 'You do not have permission to set the traceability start date.'
      using errcode = 'insufficient_privilege';
  end if;
  insert into public.fs_settings (company_id, trace_start_date, updated_at)
  values (p_company_id, p_date, now())
  on conflict (company_id) do update
    set trace_start_date = excluded.trace_start_date, updated_at = now();
end;
$$;

revoke all on function public.set_trace_start_date(text, date) from public;
grant execute on function public.set_trace_start_date(text, date) to authenticated;

commit;
