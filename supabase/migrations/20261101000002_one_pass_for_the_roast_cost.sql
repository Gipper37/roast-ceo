-- One pass for the roast cost.
--
-- get_origin_roasted_cost_on_date answers "what did a roasted pound of this
-- origin cost, as at this date" with one aggregate over every lot consumption
-- of that origin up to that date. Measured on production for origin 6c752b40:
--
--     Aggregate  29.3 ms   Buffers: shared hit=19690   (~154 MB of traffic)
--       -> Nested Loop  rows=4514
--          -> cip bitmap scan rows=28 -> rlc index scan rows=6416
--          -> Index Scan "Roast Log_pkey" rl  (loops=6416)  hit=19248
--
-- 6,416 individual roast_log lookups, per call. p50 across the real workload
-- is 21.97 ms, and it is 22 of the 24 ms that get_product_cogs_on_date costs.
-- Re-costing one freight edit on shipment 6KKKTKnn calls it ~7,000 times:
-- 2m15s, against the 60s an authenticated session gets. So editing freight on
-- that shipment fails for a signed-in user today.
--
-- Nothing about the aggregate itself is wasteful; calling it per order line
-- is. Both its numerator and its denominator are plain cumulative sums over
-- roast_date, so the roast events and the dates being asked about can be
-- merged into ONE ordered stream and answered in a single window pass.
--
-- It has to be a merge, not a cumulative series plus a lookup per date. The
-- first draft built the series in a materialized CTE and then picked each
-- date's row out of it with a correlated subquery, and a CTE scan has no
-- index: that compiles to `CTE Scan on cum (rows=5428 loops=538)` with a
-- top-N sort per date, so the cost stayed O(dates x roast timestamps) and the
-- per-date factor the whole exercise exists to remove was still there. The
-- header claimed one pass; the plan said otherwise. Measured on a 4,514-
-- timestamp pair: 1 date 6.1 ms, 126 dates 118 ms, 538 dates 722 ms, 2,000
-- dates 3,259 ms -- strictly linear in dates. The merge below answers the same
-- 538 dates in 5-6 ms, and is flat in the date count.
--
-- THE TWO SCALARS ARE NOT TOUCHED BY THIS FILE, deliberately. An earlier draft
-- pointed them at the bulk form, and that was a regression on two counts that
-- an equality proof cannot see:
--
--   * get_origin_roasted_cost_on_date went 24.0 ms -> 52.7 ms on production
--     (same 19,690 buffers, plus a HashAggregate, a Sort and a WindowAgg over
--     6,363 rows that the single Aggregate never did), and
--     value_roast_lot_consumption calls it once per distinct origin from a FOR
--     EACH ROW trigger on roast_log_lot_consumption -- inside the roast write
--     that already holds locks for 17 s.
--   * get_product_cogs_on_date(p, f, NULL) returns a real number today. The
--     origin aggregate is NULL for a NULL date, so it falls through to
--     get_coffee_cost_on_date, whose second priority carries no date predicate
--     at all. Measured: 49 of 60 sampled (product, facility) pairs answer
--     non-NULL at a NULL date, and order_details.order_date is nullable with
--     one such row on production. Delegating turned all of those into NULL.
--     Neither production sweep could see it -- both enumerated real dates, so
--     a NULL was outside the domain they covered, not a sample they missed.
--
-- So this file only ADDS the bulk forms, for the re-cost path to use. The cost
-- of that choice is two expressions of one formula; the verify blocks below
-- turn that into an asset by cross-checking them against each other on every
-- breakpoint of the entire input domain, which a single copy cannot do.
--
-- Restructuring the aggregate in place was tried first and does nothing --
-- Postgres flattens the CTE and picks the identical plan (30.6 ms). A covering
-- index does not save it either: 19,248 of the 19,690 buffers are 6,416 index
-- DESCENTS, not heap fetches.
--
-- NOTE ON TIME OF DAY: 18,840 of 18,904 roast_log rows carry a real time, and
-- roast_date is `timestamp`, so `roast_date <= order_date` cuts at MIDNIGHT --
-- a roast on the morning of the order's own day does not count. That is the
-- existing behaviour and it is preserved exactly: a roast event and a date
-- event at the same instant are ordered roast-first, which is what `<=` means,
-- and nothing is ever bucketed by day.

begin;

-- ---------------------------------------------------------------------------
-- The bulk form: the same sums, as one ordered pass.
-- ---------------------------------------------------------------------------
create or replace function public.origin_roasted_cost_on_dates(
  p_origin_id   text,
  p_facility_id text,
  p_dates       date[]
)
returns table (order_date date, cost numeric)
language sql
as $function$
  with q as (
    select distinct u as d from unnest(p_dates) u where u is not null
  ),
  src as (
    -- Exactly the rows the per-date aggregate summed, with its date filter
    -- relaxed to the LATEST date asked about. Keeping that bound matters: it
    -- is the old aggregate's pruning, and without it a call about one early
    -- date reads the pair's whole history.
    select rl.roast_date as rd,
           rlc.lot_cost  as num_t,
           rlc.lbs_consumed
             * coalesce(rl.measured_roasted_weight, rl.roasted_weight,
                        rl.charge_weight_lbs
                          * coalesce(public.get_retention_factor(rl.facility_id, rl.recipe_id), 0.82))
             / nullif(rl.charge_weight_lbs, 0) as den_t
      from public.roast_log_lot_consumption rlc
      join public.roast_log rl
           on rl.roast_log_id = rlc.roast_log_id
      join public.coffee_inventory_purchased cip
           on cip.origin_purchase_id = rlc.origin_purchase_id
     where cip.origin        = p_origin_id
       and rl.facility_id    = p_facility_id
       and rlc.green_cost_lb is not null
       and rl.roast_date    <= (select max(q.d) from q)
  ),
  ev as (
    -- ONE stream: every roast event, and every date being asked about. At the
    -- same instant the roast sorts first (ord 0 before 1), which is precisely
    -- `roast_date <= order_date`; a date promotes to midnight as it always
    -- did. A roast with a NULL roast_date never enters, because the bound
    -- above is NULL for it -- the same rows the old `roast_date <= date`
    -- dropped.
    select rd as k, 0 as ord, num_t, den_t, null::date as qd from src
    union all
    select q.d::timestamp, 1, null::numeric, null::numeric, q.d from q
  ),
  run as (
    -- One sort, one window pass. A date row's frame holds every roast row
    -- before it in the stream, so its running sums ARE the aggregate the old
    -- function computed for that date. numeric addition is exact, so the
    -- order of the addends is irrelevant, and sum() skips NULLs, so the date
    -- rows' own null contributions do not disturb it. The roast rows' own
    -- running values are partial at a tie, and are discarded below.
    select qd,
           sum(num_t) over w as cnum,
           sum(den_t) over w as cden
      from ev
     window w as (order by k, ord rows between unbounded preceding and current row)
  )
  select qd, cnum / nullif(cden, 0)
    from run
   where qd is not null;
$function$;

comment on function public.origin_roasted_cost_on_dates(text, text, date[]) is
  'Cost of a roasted pound of this origin as at each given date, as ONE '
  'ordered pass over the roast events and the dates merged together, instead '
  'of one aggregate per date. One row per distinct non-null date; cost NULL '
  'where the aggregate had nothing to divide. '
  'get_origin_roasted_cost_on_date is the single-date form and is '
  'deliberately a separate implementation; this migration cross-checks them.';

-- ---------------------------------------------------------------------------
-- The same idea one level up: unit COGS for a whole SET of (product,
-- facility, date) keys, passed as three parallel arrays. The key set is
-- collapsed to its distinct (origin, facility) pairs, each costed once for
-- every date it needs, and the answers joined back.
--
-- The axis this scales on is the one that matters. A first cut took one
-- product at a time and made a pass per recipe component: 156 passes for a
-- workload holding only THIRTEEN distinct (origin, facility) pairs, because
-- products sharing an origin each paid for it again -- 8.3 s. Collapsing the
-- whole key set first costs 13 passes, and scales on how many origins a
-- roaster has rather than how many products. Measured end to end on
-- production for the 6KKKTKnn freight edit -- 6,644 order lines, 3,981
-- distinct keys, 106 (product, facility) groups, 495 dates, every value
-- consumed: 1.63 s, against 2m15s today.
-- ---------------------------------------------------------------------------
create or replace function public.product_cogs_for_keys(
  p_product_ids  text[],
  p_facility_ids text[],
  p_order_dates  date[]
)
returns table (product_id text, facility_id text, order_date date, cogs numeric)
language plpgsql
as $function$
-- The RETURNS TABLE columns are plpgsql variables in this body, and the query
-- below names columns product_id / facility_id / order_date of its own. Let a
-- column win: nothing here reads the output variables, it all goes out through
-- RETURN QUERY.
#variable_conflict use_column
begin
  -- The i-th element of each array is one key, so a caller building them in
  -- separate passes could silently misalign them. Refuse, rather than answer
  -- about keys nobody asked for.
  if coalesce(cardinality(p_product_ids), 0) <> coalesce(cardinality(p_facility_ids), 0)
     or coalesce(cardinality(p_product_ids), 0) <> coalesce(cardinality(p_order_dates), 0) then
    raise exception
      'product_cogs_for_keys needs three arrays of equal length, got %, %, %',
      coalesce(cardinality(p_product_ids), 0),
      coalesce(cardinality(p_facility_ids), 0),
      coalesce(cardinality(p_order_dates), 0);
  end if;

  return query
  with keys as materialized (
    -- A key with a null part gets no row here. NOTE this is NOT what
    -- get_product_cogs_on_date(p, f, NULL) does -- that returns a real number
    -- through the date-less fallbacks in get_coffee_cost_on_date, and it is
    -- untouched by this file. Nothing reaches this function with a null date
    -- (recost_order_details filters them out); the difference is deliberate.
    select distinct k.product_id, k.facility_id, k.order_date
      from unnest(p_product_ids, p_facility_ids, p_order_dates)
             as k(product_id, facility_id, order_date)
     where k.product_id  is not null
       and k.facility_id is not null
       and k.order_date  is not null
  ),
  base as materialized (
    -- Everything about the product that does not depend on the date, read
    -- once per key instead of once per date. LEFT JOIN: a key naming a
    -- product that no longer exists gets a null answer, as the scalar gives.
    select k.product_id, k.facility_id, k.order_date,
           p.recipe_id, p.weight_lbs, p.source_consumable_id,
           coalesce((select coalesce(s.units_per_case, 1)
                       from public.products p2
                       join public.size s on s.size_id = p2.size
                      where p2.product_id = k.product_id), 1) as units
      from keys k
      left join public.products p on p.product_id = k.product_id
  ),
  components as materialized (
    select b.product_id, b.facility_id, b.order_date,
           rc.coffee_item,
           coalesce(rc.percentage, 0::numeric) as pct
      from base b
      cross join lateral public.recipe_effective_green(b.recipe_id) rc
     where b.recipe_id is not null
       and coalesce(b.weight_lbs, 0) > 0
       and rc.facility_id = b.facility_id
  ),
  origin_cost as materialized (
    -- THE POINT OF THE WHOLE FILE: one ordered pass per distinct
    -- (origin, facility), answering every date that pair is asked about.
    select n.coffee_item, n.facility_id, oc.order_date, oc.cost
      from (select distinct coffee_item, facility_id from components) n
      cross join lateral public.origin_roasted_cost_on_dates(
                   n.coffee_item, n.facility_id,
                   array(select distinct c.order_date
                           from components c
                          where c.facility_id = n.facility_id)) oc
  ),
  coffee as materialized (
    -- A plain LEFT JOIN, not a lookup per component: the costs are already
    -- computed. get_coffee_cost_on_date is reached only where the roasted
    -- cost is absent or null, because COALESCE short-circuits -- the same
    -- fallback, in the same cases, as before.
    select x.product_id, x.facility_id, x.order_date,
           sum(x.comp * x.pct) as amt, count(x.comp) as n
      from (
        select c.product_id, c.facility_id, c.order_date, c.pct,
               coalesce(oc.cost,
                        public.get_coffee_cost_on_date(
                          c.coffee_item, c.facility_id, c.order_date)) as comp
          from components c
          left join origin_cost oc
                 on oc.coffee_item = c.coffee_item
                and oc.facility_id = c.facility_id
                and oc.order_date  = c.order_date
      ) x
     group by 1, 2, 3
  ),
  cons as materialized (
    select b.product_id, b.facility_id, b.order_date,
           sum(c.comp * c.qty) as amt, count(c.comp) as n
      from base b
      left join lateral (
        select coalesce(pc.quantity, 1::numeric) as qty,
               public.get_consumable_cost_on_date(
                 pc.consumable_id, b.facility_id, b.order_date) as comp
          from public.product_consumables_effective pc
         where pc.product_id  = b.product_id
           and pc.facility_id = b.facility_id

        union all

        -- RESOLD: the product IS its source consumable, at quantity = units.
        select b.units,
               public.get_consumable_cost_on_date(
                 b.source_consumable_id, b.facility_id, b.order_date)
         where b.source_consumable_id is not null
      ) c on true
     group by 1, 2, 3
  )
  select b.product_id, b.facility_id, b.order_date,
         -- Nothing contributed a cost for this key => NULL, as before. A
         -- contribution of zero is still a contribution.
         case when coalesce(cf.n, 0) + coalesce(cn.n, 0) = 0 then null
              else coalesce(cf.amt, 0) * coalesce(b.weight_lbs, 0)
                     + coalesce(cn.amt, 0)
         end
    from base b
    left join coffee cf
           on cf.product_id = b.product_id
          and cf.facility_id = b.facility_id
          and cf.order_date  = b.order_date
    left join cons cn
           on cn.product_id = b.product_id
          and cn.facility_id = b.facility_id
          and cn.order_date  = b.order_date;
end;
$function$;

comment on function public.product_cogs_for_keys(text[], text[], date[]) is
  'Unit COGS for a set of (product, facility, date) keys given as three '
  'parallel arrays of equal length. Collapses the set to its distinct '
  '(origin, facility) pairs and makes one ordered roasted-cost pass each, so '
  'the work scales on origins rather than on products. One row per distinct '
  'fully-non-null key; a key with a null part gets no row, which differs on '
  'purpose from get_product_cogs_on_date(p, f, NULL).';

-- Match the privileges the scalars already carry: no PUBLIC, no anon.
revoke all on function public.origin_roasted_cost_on_dates(text, text, date[]) from public;
revoke all on function public.product_cogs_for_keys(text[], text[], date[])      from public;
grant execute on function public.origin_roasted_cost_on_dates(text, text, date[]) to authenticated, service_role;
grant execute on function public.product_cogs_for_keys(text[], text[], date[])      to authenticated, service_role;

-- Does the merged pass answer exactly as the per-date aggregate does? The
-- aggregate is recomputed here by join-and-group -- an independent strategy,
-- not a restatement of either implementation -- and compared on EVERY
-- breakpoint of the input domain. The value is piecewise constant in its date
-- argument and can only change at a roast day or the day after one, so
-- {roast_date::date, roast_date::date + 1} per pair is exhaustive, not a
-- sample -- and the set also carries, per pair, one point BEFORE any roast,
-- where the answer must be NULL and the src bound above leaves zero rows.
-- 4,271 points across 44 pairs on production, 0 disagreements, identical
-- 4,183 non-null answers, nothing dropped or duplicated. With no roast rows
-- there is nothing to compare and this passes vacuously, so staging is safe.
do $$
declare
  v_pts integer;
  v_bad integer;
begin
  with src as (
    select cip.origin as origin_id, rl.facility_id, rl.roast_date as rd,
           rlc.lot_cost as num_t,
           rlc.lbs_consumed
             * coalesce(rl.measured_roasted_weight, rl.roasted_weight,
                        rl.charge_weight_lbs
                          * coalesce(public.get_retention_factor(rl.facility_id, rl.recipe_id), 0.82))
             / nullif(rl.charge_weight_lbs, 0) as den_t
      from public.roast_log_lot_consumption rlc
      join public.roast_log rl
           on rl.roast_log_id = rlc.roast_log_id
      join public.coffee_inventory_purchased cip
           on cip.origin_purchase_id = rlc.origin_purchase_id
     where rlc.green_cost_lb is not null
  ),
  pts as (
    select distinct origin_id, facility_id, v.d::date as d
      from src cross join lateral (values (rd::date), (rd::date + 1)) v(d)
  ),
  old as (
    select p.origin_id, p.facility_id, p.d,
           sum(s.num_t) / nullif(sum(s.den_t), 0) as cost
      from pts p
      left join src s
        on s.origin_id   = p.origin_id
       and s.facility_id = p.facility_id
       and s.rd         <= p.d
     group by 1, 2, 3
  ),
  fresh as (
    select pr.origin_id, pr.facility_id, o.order_date as d, o.cost
      from (select distinct origin_id, facility_id from pts) pr
      cross join lateral public.origin_roasted_cost_on_dates(
                   pr.origin_id, pr.facility_id,
                   array(select p.d from pts p
                          where p.origin_id   = pr.origin_id
                            and p.facility_id = pr.facility_id)) o
  )
  select count(*), count(*) filter (where o.cost is distinct from f.cost)
    into v_pts, v_bad
    from old o
    join fresh f
      on f.origin_id = o.origin_id and f.facility_id = o.facility_id and f.d = o.d;

  if v_bad > 0 then
    raise exception
      'origin_roasted_cost_on_dates disagrees with the aggregate on % of % breakpoints',
      v_bad, v_pts;
  end if;

  -- And the untouched single-date scalar must give the same answer as the
  -- bulk form, at the last breakpoint of every pair. Two independent
  -- implementations of one formula, checked against each other.
  select count(*) into v_bad
    from (select cip.origin as origin_id, rl.facility_id,
                 max(rl.roast_date::date) + 1 as d
            from public.roast_log_lot_consumption rlc
            join public.roast_log rl
                 on rl.roast_log_id = rlc.roast_log_id
            join public.coffee_inventory_purchased cip
                 on cip.origin_purchase_id = rlc.origin_purchase_id
           where rlc.green_cost_lb is not null
           group by 1, 2) k
   where public.get_origin_roasted_cost_on_date(k.origin_id, k.facility_id, k.d)
     is distinct from (select o.cost
                         from public.origin_roasted_cost_on_dates(
                                k.origin_id, k.facility_id, array[k.d]) o);
  if v_bad > 0 then
    raise exception
      'get_origin_roasted_cost_on_date and the bulk form disagree for % pairs', v_bad;
  end if;
end $$;

-- product_cogs_for_keys is new in SHAPE, not in formula, and the single-date
-- scalar it mirrors is NOT being replaced -- so compare the two directly: for
-- real keys the bulk form must answer exactly what get_product_cogs_on_date
-- answers. Bounded to 40 keys so a release does not spend minutes here; the
-- exhaustive sweep over 7,979 keys -- 388 resold, 618 with no recipe, 506 with
-- no size, 8 naming a product that no longer exists -- is run against
-- production. Vacuous with no order lines.
do $$
declare
  v_keys integer;
  v_rows integer;
  v_bad  integer;
begin
  with k as (
    select od.product_id, od.facility_id, od.order_date
      from public.order_details od
     where od.product_id  is not null
       and od.facility_id is not null
       and od.order_date  is not null
     group by 1, 2, 3
     limit 40
  ),
  packed as (
    select array_agg(k.product_id)  as pids,
           array_agg(k.facility_id) as fids,
           array_agg(k.order_date)  as ods
      from k
  ),
  bulk as (
    select c.product_id, c.facility_id, c.order_date, c.cogs
      from packed z
      cross join lateral public.product_cogs_for_keys(z.pids, z.fids, z.ods) c
  )
  select (select count(*) from k),
         (select count(*) from bulk),
         (select count(*)
            from k
            join bulk b
              on b.product_id  = k.product_id
             and b.facility_id = k.facility_id
             and b.order_date  = k.order_date
           where b.cogs is distinct from
                 public.get_product_cogs_on_date(k.product_id, k.facility_id, k.order_date))
    into v_keys, v_rows, v_bad;

  if v_rows <> v_keys then
    raise exception
      'product_cogs_for_keys returned % rows for % distinct keys', v_rows, v_keys;
  end if;
  if v_bad > 0 then
    raise exception
      'product_cogs_for_keys disagrees with get_product_cogs_on_date on % of % keys',
      v_bad, v_keys;
  end if;
end $$;

commit;
