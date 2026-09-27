-- Ask for a count when the estimate stops being believable.
--
-- The roasted-stock number on the Roast page is a COUNT when somebody has
-- logged one inside 28 days, and an arithmetic rebuild otherwise — 28 days of
-- roasting minus 28 days of deliveries. The rebuild is only as good as the
-- delivery record, and prod holds two logged counts in its entire history, so
-- in practice every facility is running on the rebuild.
--
-- This is the engine behind the prompt: one function that answers "should this
-- terminal ask for a count right now, and how urgently", plus somewhere to
-- record that a supervisor said not now.
--
-- 🔴 IT DOES NOT CALL roast_detail_by_blend. That view is 77% of all production
-- database time, and this runs on every page load for every terminal. It
-- recomputes the two quantities it needs directly, from the same windows.
--
-- ── WHEN THE ESTIMATE IS NOT BELIEVABLE ────────────────────────────────
-- Estimated shelf expressed as WEEKS of that facility's own roasting. Measured
-- across 30 healthy facility-weeks on prod under both delivery-date rules, the
-- highest credible reading was 1.5 weeks. The tenant whose deliveries are
-- half-unrecorded sits at 3.6-4.2 and never dropped below 1.31 — and the rule
-- did NOT fire on that tenant back when its data was healthy. So 2.0 separates
-- them with room on both sides, and is not tuned to one tenant's numbers.
--
-- The effective threshold is GREATEST(setting, 1 + backstock_buffer_pct/100):
-- a roastery deliberately holding a week of backstock is not nagged for it, and
-- nobody drops below the measured floor.
--
-- 🔴 ONE-SIDED. A LOW ratio never escalates. Under-estimating causes
-- over-roasting, which wastes green; over-estimating causes under-roasting,
-- which is a stockout against a customer order. Only one of those is worth
-- interrupting somebody's shift for.
--
-- 🔴 THE DENOMINATOR IS WEEKS OF HISTORY, NOT 12. Dividing a trailing 84-day
-- total by a flat 12 understates the rate of any facility younger than 12 weeks
-- in exact proportion to its age, which inflates weeks-of-shelf by the same
-- factor — so a three-week-old tenant would escalate to daily on its first
-- roast week no matter how clean its data was. (roast_detail_by_blend ships the
-- identical bug in avg_weekly_lbs, dividing a 42-day window by a flat 6. Not
-- fixed here; it is a different number with its own callers.) Below four weeks
-- of history the escalation cannot fire at all.

begin;

-- ── Somewhere to record "not now" ──────────────────────────────────────
-- Satisfaction is DERIVED — a count in the ledger for this period is the only
-- thing that satisfies the prompt — so the only state worth storing is a
-- deliberate dismissal, and it is scoped to the period it was given for.
create table if not exists public.stock_count_dismissal (
  facility_id   text not null references public.facilities(facility_id) on delete cascade,
  company_id    text not null,
  period_start  date not null,
  dismissed_by  text,
  dismissed_at  timestamptz not null default now(),
  primary key (facility_id, period_start)
);

comment on table public.stock_count_dismissal is
  'One row per facility per period where somebody with roast_stock.prompt_dismiss '
  'said "not now" to the roasted-stock count prompt. period_start is the roast '
  'week start for a weekly prompt and the facility-local date for a daily one. '
  'Satisfying the prompt is NOT recorded here — a count in roast_stock_log is '
  'the only thing that satisfies it.';

alter table public.stock_count_dismissal enable row level security;

drop policy if exists stock_count_dismissal_read on public.stock_count_dismissal;
create policy stock_count_dismissal_read on public.stock_count_dismissal
  for select to authenticated
  using (company_id in (select public.auth_company_ids()));

drop policy if exists stock_count_dismissal_write on public.stock_count_dismissal;
create policy stock_count_dismissal_write on public.stock_count_dismissal
  for insert to authenticated
  with check ((company_id in (select public.auth_company_ids()))
              and public.auth_has_permission('roast_stock.prompt_dismiss', company_id));

-- A dismissal is a record of a judgement call. Nobody edits or erases one.
revoke update, delete on public.stock_count_dismissal from authenticated;

-- ── The engine ─────────────────────────────────────────────────────────
create or replace function public.stock_count_status(p_facility_id text)
returns table (
  cadence            text,
  roast_week_start   date,
  local_today        date,
  period_start       date,
  estimated_shelf    numeric,
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
      from public.facilities fac
     where fac.facility_id = p_facility_id
  ),
  cal as (
    select f.facility_id, f.company_id, f.tz,
           (current_timestamp at time zone f.tz)::date as local_today,
           coalesce((select cp.value_number::integer from public.company_parameters cp
                      where cp.parameter_id = 'RF1iFWjOh7' and cp.facility_id = f.facility_id limit 1), 4)
             as roast_reset_day,
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
    select cal.*,
           (cal.local_today - (((extract(dow from cal.local_today)::int - cal.roast_reset_day) + 7) % 7)) as rws
      from cal
  ),
  -- The rebuild, per recipe, floored at zero exactly as the view floors it, then
  -- summed. Same windows as roast_detail_by_blend's recipe_is fallback.
  roasted as (
    select rlr.recipe_id, sum(rl.roasted_weight * (rlr.lbs_allocated / nullif(rl.charge_weight_lbs, 0))) lbs
      from public.roast_log rl
      join public.roast_log_recipes rlr on rlr.roast_log_id = rl.roast_log_id
      cross join wk
     where rl.facility_id = wk.facility_id and rl."charged?"
       and rl.roast_date >= (wk.rws - 28) and rl.roast_date < wk.rws
     group by rlr.recipe_id
  ),
  delivered as (
    select p.recipe_id, sum(od.roasted_weight)::numeric lbs
      from public.order_details od
      join public.orders o on o.order_id = od.order_id
      join public.products p on p.product_id = od.product_id
      cross join wk
     where o.facility_id = wk.facility_id and o.order_status = 'Delivered'
       and p.recipe_id is not null
       and coalesce(o.delivered_on, (o.status_changed_at at time zone wk.tz)::date, o.order_date) >= (wk.rws - 28)
       and coalesce(o.delivered_on, (o.status_changed_at at time zone wk.tz)::date, o.order_date) <  wk.rws
     group by p.recipe_id
  ),
  shelf as (
    select coalesce(sum(greatest(0, coalesce(r.lbs,0) - coalesce(d.lbs,0))), 0) as lbs
      from roasted r full join delivered d on d.recipe_id = r.recipe_id
  ),
  -- Rate over the trailing 12 weeks, divided by the weeks that actually exist.
  hist as (
    select coalesce(sum(rl.roasted_weight), 0) as lbs_84d,
           -- date - date yields an integer number of DAYS, not an interval.
           -- And least()/greatest() IGNORE nulls, so a facility that has never
           -- roasted would otherwise report a full 12 weeks of history and be
           -- eligible to escalate. It has none; say so.
           case when min(rl2.first_roast) is null then 0
                else greatest(1, least(12, ceil((wk.rws - min(rl2.first_roast)::date) / 7.0)))::int
           end as weeks
      from wk
      left join public.roast_log rl
        on rl.facility_id = wk.facility_id and rl."charged?"
       and rl.roast_date >= (wk.rws - 84) and rl.roast_date < wk.rws
      left join lateral (select min(x.roast_date) first_roast from public.roast_log x
                          where x.facility_id = wk.facility_id and x."charged?") rl2 on true
     group by wk.rws
  )
  select
    wk.cadence,
    wk.rws,
    wk.local_today,
    case when wk.cadence = 'daily' then wk.local_today else wk.rws end as period_start,
    round(shelf.lbs, 1),
    round(hist.lbs_84d / nullif(hist.weeks, 0), 1),
    round(shelf.lbs / nullif(hist.lbs_84d / nullif(hist.weeks, 0), 0), 2),
    round(greatest(wk.threshold_setting, 1 + wk.bs_pct / 100.0), 2),
    hist.weeks,
    -- Escalate only when the shelf is IMPLAUSIBLY HIGH, and only once there is
    -- enough history for the rate to mean anything.
    (hist.weeks >= 4
       and (hist.lbs_84d / nullif(hist.weeks, 0)) > 0
       and shelf.lbs / nullif(hist.lbs_84d / nullif(hist.weeks, 0), 0)
           >= greatest(wk.threshold_setting, 1 + wk.bs_pct / 100.0)) as escalated,
    exists (select 1 from public.roast_stock_log s
             where s.stock_type = 'blend' and s.facility_id = wk.facility_id
               and (s.created_at at time zone wk.tz)::date
                   >= case when (hist.weeks >= 4
                                 and (hist.lbs_84d / nullif(hist.weeks,0)) > 0
                                 and shelf.lbs / nullif(hist.lbs_84d / nullif(hist.weeks,0), 0)
                                     >= greatest(wk.threshold_setting, 1 + wk.bs_pct/100.0))
                               then wk.local_today else wk.rws end) as counted_this_period,
    exists (select 1 from public.stock_count_dismissal x
             where x.facility_id = wk.facility_id
               and x.period_start = case when (hist.weeks >= 4
                                 and (hist.lbs_84d / nullif(hist.weeks,0)) > 0
                                 and shelf.lbs / nullif(hist.lbs_84d / nullif(hist.weeks,0), 0)
                                     >= greatest(wk.threshold_setting, 1 + wk.bs_pct/100.0))
                               then wk.local_today else wk.rws end) as dismissed,
    false
  from wk cross join shelf cross join hist;
$fn$;

-- `due` is composed in one place rather than repeated in the body above.
create or replace function public.stock_count_due(p_facility_id text)
returns boolean
language sql
stable
security invoker
set search_path to 'public', 'pg_temp'
as $fn$
  select s.cadence <> 'off' and not s.counted_this_period and not s.dismissed
    from public.stock_count_status(p_facility_id) s;
$fn$;

do $verify$
declare r record; v_bad int;
begin
  -- The engine must answer for every facility without error, and never claim a
  -- prompt is due at a facility whose cadence is off.
  for r in select facility_id from public.facilities loop
    perform public.stock_count_status(r.facility_id);
  end loop;

  select count(*) into v_bad from public.facilities f
   cross join lateral public.stock_count_status(f.facility_id) s
   where s.cadence = 'off' and public.stock_count_due(f.facility_id);
  if v_bad > 0 then raise exception '% facility(ies) are due a prompt with the cadence off', v_bad; end if;

  -- The escalation is one-sided: an implausibly LOW shelf must never escalate.
  select count(*) into v_bad from public.facilities f
   cross join lateral public.stock_count_status(f.facility_id) s
   where s.escalated and s.weeks_of_shelf < s.threshold_weeks;
  if v_bad > 0 then raise exception '% facility(ies) escalated below their own threshold', v_bad; end if;

  -- A facility without enough history must never escalate, whatever its ratio.
  select count(*) into v_bad from public.facilities f
   cross join lateral public.stock_count_status(f.facility_id) s
   where s.escalated and s.history_weeks < 4;
  if v_bad > 0 then raise exception '% facility(ies) escalated on under four weeks of history', v_bad; end if;

  -- And nobody's threshold may fall below the measured floor.
  select count(*) into v_bad from public.facilities f
   cross join lateral public.stock_count_status(f.facility_id) s
   where s.threshold_weeks < 2.0;
  if v_bad > 0 then raise exception '% facility(ies) carry a threshold under the measured floor', v_bad; end if;

  for r in select f.facility_id, s.* from public.facilities f
            cross join lateral public.stock_count_status(f.facility_id) s loop
    raise notice 'facility % : shelf % lb over % lb/wk = % weeks (threshold %, % wk history) -> escalated=%',
      r.facility_id, r.estimated_shelf, r.weekly_roast_rate, r.weeks_of_shelf,
      r.threshold_weeks, r.history_weeks, r.escalated;
  end loop;
end $verify$;

commit;
