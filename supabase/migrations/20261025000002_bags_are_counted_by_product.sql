-- Bags are counted by PRODUCT, and the prompt notices all three counts.
--
-- Two corrections from the owner, 2026-10-25, both of which say the same
-- thing: *"theyre all supposed to work on both food safety and not."*
--
-- ── 1. COUNTING BY LOT ONLY WORKS WITH FOOD SAFETY ────────────────────────
--
-- *"nope, not counted by lot. that would only apply to food safety."*
--
-- I built the bagged count keyed to `pack_run`, and `pack_run` is written by
-- `pack.run`, which carries feature_key='haccp'. So a roastery WITHOUT the
-- module has no pack runs, no lot codes and nothing to count -- which is
-- precisely the tenant the un-gated `pack.count` key exists for. The one
-- destination that had to work without the module was built entirely on it.
--
-- PRODUCT is the unit of counting now. The lot stays as OPTIONAL attribution,
-- so a roastery that does track lots can still say which one a variance
-- belongs to, and one that does not is never asked. That is what "works for
-- both" means here: not two code paths, one unit that everybody has.
--
-- ── 2. THE PROMPT ONLY NOTICED ONE OF THE THREE COUNTS ────────────────────
--
-- *"make sure that that is where the due expression looks to confirm its been
-- done."*
--
-- `due` asked only whether a `stock_type='blend'` row existed this period. So
-- an operator who counted their bins-by-coffee and their bags was prompted
-- again as though they had done nothing -- the exact nagging-after-the-work
-- failure. It now asks whether ANY of the three counts happened: blend,
-- origin or component rows in roast_stock_log, or a bagged count.
--
-- 🔴 ANY, not ALL. Requiring all three would leave a roastery that bags
-- nothing permanently due, because it has no bags to count. The threshold
-- stays what it was -- one count clears the period -- it just stops being
-- blind to two thirds of the ways to do it.
--
-- 🔴 APPEND-ONLY DOES NOT DOUBLE COUNT, since the owner asked: every reader
-- takes the NEWEST row per key and older rows are history, never addends. The
-- rule to hold is that nothing ever SUMS them. Overwriting instead would
-- destroy the evidence that the shelf and the system disagreed, and that
-- disagreement is how a roastery learns a bagging session went unrecorded.
--
-- 🔴 20261025000001 is already applied to staging, so this is a NEW migration.
-- Never edit an applied one.

begin;

-- ── Product becomes the unit of counting ──────────────────────────────────

alter table public.pack_stock_count
  add column if not exists product_id text references public.products(product_id) on delete cascade;

-- Empty on staging and never applied to prod, so there is nothing to backfill.
-- Asserted rather than assumed, below.
do $$
begin
  if exists (select 1 from public.pack_stock_count where product_id is null) then
    raise exception 'pack_stock_count has rows with no product: backfill before making it required';
  end if;
end $$;

alter table public.pack_stock_count alter column product_id set not null;

comment on column public.pack_stock_count.product_id is
  'What was counted. PRODUCT, not lot: lot codes only exist where Food safety is on, and this count has to work for every roastery.';
comment on column public.pack_stock_count.pack_run_id is
  'OPTIONAL attribution. Where a roastery records bagging runs, a count can name the lot the variance belongs to. Never required.';

create index if not exists pack_stock_count_product_time_idx
  on public.pack_stock_count (facility_id, product_id, counted_at desc);

-- ── The prompt notices all three counts ───────────────────────────────────

CREATE OR REPLACE FUNCTION public.stock_count_status(p_facility_id text)
 RETURNS TABLE(cadence text, roast_week_start date, local_today date, period_start date, estimated_shelf numeric, shelf_is_counted boolean, weekly_roast_rate numeric, weeks_of_shelf numeric, threshold_weeks numeric, history_weeks integer, escalated boolean, counted_this_period boolean, dismissed boolean, due boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
    (exists (select 1 from public.roast_stock_log s
             where s.stock_type in ('blend','origin','component') and s.facility_id = final.facility_id
               and (s.created_at at time zone final.tz)::date >= final.pstart)
      or exists (select 1 from public.pack_stock_count b
             where b.facility_id = final.facility_id
               and (b.counted_at at time zone final.tz)::date >= final.pstart)),
    exists (select 1 from public.stock_count_dismissal x
             where x.facility_id = final.facility_id and x.period_start = final.pstart),
    (final.cadence <> 'off'
     and not (exists (select 1 from public.roast_stock_log s
             where s.stock_type in ('blend','origin','component') and s.facility_id = final.facility_id
               and (s.created_at at time zone final.tz)::date >= final.pstart)
      or exists (select 1 from public.pack_stock_count b
             where b.facility_id = final.facility_id
               and (b.counted_at at time zone final.tz)::date >= final.pstart))
     and not exists (select 1 from public.stock_count_dismissal x
                      where x.facility_id = final.facility_id and x.period_start = final.pstart))
  from final;
$function$;


-- Prove both halves rather than assuming them.
do $$
declare
  n_prod int;
  n_due  int;
begin
  select count(*) into n_prod from information_schema.columns
   where table_name = 'pack_stock_count' and column_name = 'product_id' and is_nullable = 'NO';
  if n_prod <> 1 then raise exception 'product_id must exist and be required'; end if;

  select count(*) into n_due from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'stock_count_status'
     and pg_get_functiondef(p.oid) like '%pack_stock_count%';
  if n_due <> 1 then raise exception 'stock_count_status still ignores the bagged count'; end if;
end $$;

commit;
