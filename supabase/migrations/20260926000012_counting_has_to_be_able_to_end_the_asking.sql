-- Counting has to be able to end the asking.
--
-- Three defects in 20260926000011, found by review before it reached prod.
--
-- 1. 🔴 COUNTING NEVER CLEARED THE ESCALATION. estimated_shelf was a pure
--    roasted-minus-delivered rebuild; roast_stock_log did not appear in it at
--    all. So recording a count did not move the number that triggered the
--    escalation. Under daily cadence period_start is today, so the count
--    satisfied today and the prompt returned tomorrow — unchanged, forever. A
--    prompt that cannot be answered is not a prompt, it is a nag.
--
--    Fixed properly rather than cheaply: estimated_shelf now gets the same
--    count-anchor treatment roast_detail_by_blend.recipe_is has. A count inside
--    the current roast week IS the shelf; an older count is the baseline that
--    roasting is added to and deliveries taken from; only with no count at all
--    does it fall back to the 28-day rebuild. So a count lowers weeks_of_shelf
--    on its own and the escalation ends because the facility answered it.
--
-- 2. 🔴 `due` WAS THE LITERAL false. The function declared the column and the
--    body returned a constant, so the natural frontend call — one RPC, read
--    .due off the row — would have shown the prompt to nobody, silently, for
--    ever. It now carries the same expression stock_count_due() uses.
--
-- 3. 🔴 ONE TENANT COULD SILENCE ANOTHER'S PROMPT. stock_count_dismissal.company_id
--    had no relationship to the facility it named. The INSERT policy checked
--    the writer's permission against the company_id THEY supplied, so a member
--    of company A could insert (facility_id = company B's facility,
--    company_id = A) and silence B for that period — and with UPDATE and DELETE
--    revoked, B could not undo it. The policy now derives the company from the
--    facility, so the row cannot name one company's facility under another's
--    banner.
--
--    Also reconsidered: revoking DELETE outright meant an accidental dismissal
--    could not be lifted by anybody, including a company admin, until the
--    period rolled over. Deleting one is now allowed to the same people who may
--    delete a count.

begin;

-- ── 1. A dismissal cannot name someone else's facility ─────────────────
drop policy if exists stock_count_dismissal_write on public.stock_count_dismissal;
create policy stock_count_dismissal_write on public.stock_count_dismissal
  for insert to authenticated
  with check (
    company_id = (select f.company_id from public.facilities f
                   where f.facility_id = stock_count_dismissal.facility_id)
    and company_id in (select public.auth_company_ids())
    and public.auth_has_permission('roast_stock.prompt_dismiss', company_id));

-- 🔴 NOT enforced as a composite foreign key, deliberately. Doing that needs a
-- UNIQUE (facility_id, company_id) on `facilities`, and ADD CONSTRAINT takes an
-- ACCESS EXCLUSIVE lock on a table every request reads. Rehearsing it against
-- prod DEADLOCKED against live traffic — which is exactly what it would do to
-- the app mid-release. The policy above is the enforcement; there is no
-- SECURITY DEFINER path that writes this table, so nothing bypasses it.

-- An accidental "not now" has to be liftable by somebody.
grant delete on public.stock_count_dismissal to authenticated;
drop policy if exists stock_count_dismissal_undo on public.stock_count_dismissal;
create policy stock_count_dismissal_undo on public.stock_count_dismissal
  for delete to authenticated
  using ((company_id in (select public.auth_company_ids()))
         and public.auth_has_permission('roast_stock.delete', company_id));

-- ── 2. The shelf respects a count, so counting ends the asking ─────────
-- The return table gains shelf_is_counted, and CREATE OR REPLACE cannot change
-- a function's return type — so both are dropped and rebuilt. stock_count_due
-- goes first because it depends on stock_count_status. Supabase's default ACL
-- re-grants EXECUTE to `authenticated` on creation, which is what the frontend
-- calls them as; the gate is RLS on the tables they read, not the grant.
drop function if exists public.stock_count_due(text);
drop function if exists public.stock_count_status(text);

create function public.stock_count_status(p_facility_id text)
returns table (
  cadence            text,
  roast_week_start   date,
  local_today        date,
  period_start       date,
  estimated_shelf    numeric,
  shelf_is_counted   boolean,
  weekly_roast_rate  numeric,
  weeks_of_shelf     numeric,
  threshold_weeks    numeric,
  history_weeks      integer,
  escalated          boolean,
  counted_this_period boolean,
  dismissed          boolean,
  due                boolean
)
language sql
stable
security invoker
set search_path to 'public', 'pg_temp'
as $fn$
  with f as (
    select fac.facility_id, fac.company_id,
           coalesce(nullif(fac.time_zone, ''), 'Pacific/Honolulu') as tz
      from public.facilities fac where fac.facility_id = p_facility_id
  ),
  cal as (
    select f.facility_id, f.company_id, f.tz,
           (current_timestamp at time zone f.tz)::date as local_today,
           coalesce((select cp.value_number::integer from public.company_parameters cp
                      where cp.parameter_id = 'RF1iFWjOh7' and cp.facility_id = f.facility_id limit 1), 4) as roast_reset_day,
           coalesce((select cp.value_number from public.company_parameters cp
                      where cp.parameter_id = 'backstock_buffer_pct' and cp.facility_id = f.facility_id limit 1),
                    (select sp.amount from public.standard_parameters sp
                      where sp.parameters_id = 'backstock_buffer_pct' limit 1), 0) as bs_pct,
           coalesce((select cp.value from public.company_parameters cp
                      where cp.parameter_id = 'stock_count_prompt' and cp.facility_id = f.facility_id limit 1),
                    (select sp.text_value from public.standard_parameters sp
                      where sp.parameters_id = 'stock_count_prompt' limit 1), 'weekly') as cadence,
           coalesce((select cp.value_number from public.company_parameters cp
                      where cp.parameter_id = 'stock_count_threshold_weeks' and cp.facility_id = f.facility_id limit 1),
                    (select sp.amount from public.standard_parameters sp
                      where sp.parameters_id = 'stock_count_threshold_weeks' limit 1), 2.0) as threshold_setting
      from f
  ),
  wk as (
    select cal.*, (cal.local_today - (((extract(dow from cal.local_today)::int - cal.roast_reset_day) + 7) % 7)) as rws
      from cal
  ),
  -- Every recipe the facility could hold stock of, with its most recent count
  -- inside the window the view would honour. Mirrors roast_detail_by_blend's
  -- recipe_anchor: 28 days back from the ROAST WEEK START, not from today.
  anch as (
    select rr.recipe_id, wk.*, a.anchor_stock, a.anchor_ts,
           (a.anchor_ts is not null and a.anchor_ts::date >= wk.rws) as in_current_week
      from wk
      join public.roast_recipes rr on rr.company_id = wk.company_id
      left join lateral (
        select s.lbs_in_stock as anchor_stock, (s.created_at at time zone wk.tz) as anchor_ts
          from public.roast_stock_log s
         where s.stock_type = 'blend' and s.blend_id = rr.recipe_id
           and s.facility_id = wk.facility_id
           and (s.created_at at time zone wk.tz)::date >= (wk.rws - 28)
         order by s.created_at desc limit 1) a on true
  ),
  per_recipe as (
    select anch.recipe_id, anch.anchor_stock is not null as counted,
      case
        -- A count taken this roast week IS the shelf.
        when anch.in_current_week then greatest(0, anch.anchor_stock)
        else greatest(0,
               coalesce(anch.anchor_stock, 0)
             + coalesce((select sum(rl.roasted_weight * (rlr.lbs_allocated / nullif(rl.charge_weight_lbs,0)))
                           from public.roast_log rl
                           join public.roast_log_recipes rlr on rlr.roast_log_id = rl.roast_log_id
                          where rlr.recipe_id = anch.recipe_id and rl.facility_id = anch.facility_id
                            and rl."charged?"
                            and rl.roast_date >= coalesce(anch.anchor_ts, (anch.rws - 28)::timestamp)
                            and rl.roast_date <  anch.rws), 0)
             - coalesce((select sum(od.roasted_weight)::numeric
                           from public.order_details od
                           join public.orders o on o.order_id = od.order_id
                           join public.products p on p.product_id = od.product_id
                          where p.recipe_id = anch.recipe_id and o.facility_id = anch.facility_id
                            and o.order_status = 'Delivered'
                            and coalesce(o.delivered_on, (o.status_changed_at at time zone anch.tz)::date, o.order_date)
                                >= coalesce(anch.anchor_ts::date, anch.rws - 28)
                            and coalesce(o.delivered_on, (o.status_changed_at at time zone anch.tz)::date, o.order_date)
                                <  anch.rws), 0))
      end as lbs
      from anch
  ),
  shelf as (
    select coalesce(sum(lbs), 0) as lbs, bool_or(counted) as any_counted from per_recipe
  ),
  hist as (
    select coalesce(sum(rl.roasted_weight), 0) as lbs_84d,
           case when min(rl2.first_roast) is null then 0
                else greatest(1, least(12, ceil((wk.rws - min(rl2.first_roast)::date) / 7.0)))::int end as weeks
      from wk
      left join public.roast_log rl
        on rl.facility_id = wk.facility_id and rl."charged?"
       and rl.roast_date >= (wk.rws - 84) and rl.roast_date < wk.rws
      left join lateral (select min(x.roast_date) first_roast from public.roast_log x
                          where x.facility_id = wk.facility_id and x."charged?") rl2 on true
     group by wk.rws
  ),
  calc2 as (
    select wk.*, shelf.lbs as shelf_lbs, shelf.any_counted, hist.weeks as hweeks,
           (hist.lbs_84d / nullif(hist.weeks, 0)) as rate,
           greatest(wk.threshold_setting, 1 + wk.bs_pct / 100.0) as threshold
      from wk cross join shelf cross join hist
  ),
  flags as (
    select calc2.*,
           (calc2.hweeks >= 4 and calc2.rate > 0
            and calc2.shelf_lbs / nullif(calc2.rate, 0) >= calc2.threshold) as escalated
      from calc2
  ),
  final as (
    select flags.*,
           case when flags.escalated then flags.local_today else flags.rws end as pstart
      from flags
  )
  select
    final.cadence, final.rws, final.local_today, final.pstart,
    round(final.shelf_lbs, 1), final.any_counted,
    round(final.rate, 1),
    round(final.shelf_lbs / nullif(final.rate, 0), 2),
    round(final.threshold, 2),
    final.hweeks,
    final.escalated,
    exists (select 1 from public.roast_stock_log s
             where s.stock_type = 'blend' and s.facility_id = final.facility_id
               and (s.created_at at time zone final.tz)::date >= final.pstart),
    exists (select 1 from public.stock_count_dismissal x
             where x.facility_id = final.facility_id and x.period_start = final.pstart),
    (final.cadence <> 'off'
     and not exists (select 1 from public.roast_stock_log s
                      where s.stock_type = 'blend' and s.facility_id = final.facility_id
                        and (s.created_at at time zone final.tz)::date >= final.pstart)
     and not exists (select 1 from public.stock_count_dismissal x
                      where x.facility_id = final.facility_id and x.period_start = final.pstart))
  from final;
$fn$;

create function public.stock_count_due(p_facility_id text)
returns boolean
language sql
stable
security invoker
set search_path to 'public', 'pg_temp'
as $fn$
  select s.due from public.stock_count_status(p_facility_id) s;
$fn$;

do $verify$
declare v_bad int; r record;
begin
  -- `due` must agree with the standalone helper, or one of them is lying.
  select count(*) into v_bad from public.facilities f
   cross join lateral public.stock_count_status(f.facility_id) s
   where s.due is distinct from public.stock_count_due(f.facility_id);
  if v_bad > 0 then raise exception 'due disagrees with stock_count_due at % facility(ies)', v_bad; end if;

  -- And it must not be a constant.
  select count(*) into v_bad from public.facilities f
   cross join lateral public.stock_count_status(f.facility_id) s where s.due;
  if v_bad = 0 then
    raise notice 'no facility is currently due a count — check this is really true rather than a stuck false';
  end if;

  -- The escalation stays one-sided and history-guarded.
  select count(*) into v_bad from public.facilities f
   cross join lateral public.stock_count_status(f.facility_id) s
   where s.escalated and (s.weeks_of_shelf < s.threshold_weeks or s.history_weeks < 4);
  if v_bad > 0 then raise exception '% facility(ies) escalated against their own rule', v_bad; end if;

  -- 🔴 THE POINT OF THIS MIGRATION: a count must be able to end the asking.
  -- Prove it rather than assert it — count every recipe at an escalated
  -- facility at zero, inside a rolled-back savepoint, and require that the
  -- escalation clears.
  for r in select f.facility_id, f.company_id from public.facilities f
            cross join lateral public.stock_count_status(f.facility_id) s
           where s.escalated limit 1 loop
    begin
      insert into public.roast_stock_log (stock_type, blend_id, facility_id, company_id, lbs_in_stock, created_by, updated_by)
      select 'blend', rr.recipe_id, r.facility_id, r.company_id, 0, 'verify', 'verify'
        from public.roast_recipes rr where rr.company_id = r.company_id;
      select count(*) into v_bad from public.stock_count_status(r.facility_id) s where s.escalated;
      if v_bad > 0 then
        raise exception 'counting every recipe did not clear the escalation at %', r.facility_id;
      end if;
      select count(*) into v_bad from public.stock_count_status(r.facility_id) s where s.due;
      if v_bad > 0 then
        raise exception 'counting every recipe did not satisfy the prompt at %', r.facility_id;
      end if;
      raise notice 'verified: counting every recipe clears both the escalation and the prompt at %', r.facility_id;
      raise exception 'rollback_probe';
    exception when others then
      if sqlerrm <> 'rollback_probe' then raise; end if;
    end;
  end loop;

  for r in select f.facility_id, s.* from public.facilities f
            cross join lateral public.stock_count_status(f.facility_id) s loop
    raise notice 'facility % : shelf % lb (counted=%) over % lb/wk = % wk, threshold % -> escalated=%, due=%',
      r.facility_id, r.estimated_shelf, r.shelf_is_counted, r.weekly_roast_rate,
      r.weeks_of_shelf, r.threshold_weeks, r.escalated, r.due;
  end loop;
end $verify$;

commit;
