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
-- roast_date, so ONE pass per (origin, facility) yields the answer for every
-- date at once. That is what origin_roasted_cost_on_dates does.
--
-- product_cogs_for_keys then carries the idea up a level, and the axis it
-- scales on is the one that matters. A first cut took one product at a time
-- and made a bulk pass per recipe component: 156 passes for a workload with
-- only THIRTEEN distinct (origin, facility) pairs, because products sharing an
-- origin each paid for it again -- 8.3 s. Taking the whole key set at once,
-- collapsing it to its distinct origins and joining the answers back costs 13
-- passes and 3.7 s, and it now scales on the number of origins a roaster has
-- rather than the number of products. For 6KKKTKnn: 13 passes where today
-- there are ~7,000 aggregates.
--
-- Restructuring the aggregate was tried first and does nothing -- Postgres
-- flattens the CTE and picks the identical plan (30.6 ms). A covering index
-- does not save it either: 19,248 of the 19,690 buffers are 6,416 index
-- DESCENTS, not heap fetches.
--
-- THE SCALARS KEEP THEIR SIGNATURES AND NOW DELEGATE, so there is one formula
-- with two entry points and every existing caller is unaffected. Equality with
-- the previous formula is asserted below on every breakpoint of the entire
-- input domain: the value is piecewise constant in its date argument and can
-- only change at a roast day or the day after one, so {roast_date::date,
-- roast_date::date + 1} per pair is exhaustive, not a sample. 4,271 points
-- across 44 (origin, facility) pairs, proved read-only on production first.
--
-- NOTE ON TIME OF DAY: 18,840 of 18,904 roast_log rows carry a real time, and
-- roast_date is `timestamp`, so `roast_date <= order_date` cuts at MIDNIGHT --
-- a roast on the morning of the order's own day does not count. That is the
-- existing behaviour and it is preserved exactly: the cumulative series is
-- keyed and compared on the raw timestamp, never bucketed by day.

begin;

-- ---------------------------------------------------------------------------
-- The bulk form: the same aggregate, as a cumulative series, one pass.
-- ---------------------------------------------------------------------------
create or replace function public.origin_roasted_cost_on_dates(
  p_origin_id   text,
  p_facility_id text,
  p_dates       date[]
)
returns table (order_date date, cost numeric)
language sql
as $function$
  with src as materialized (
    -- Exactly the rows the per-date aggregate summed, minus its date filter.
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
  ),
  by_rd as materialized (
    -- One row per roast timestamp. sum() skips nulls at both levels, so
    -- summing per timestamp and then cumulatively is the same set of addends
    -- the single aggregate had. numeric addition is exact, so order is
    -- irrelevant.
    select rd, sum(num_t) as num, sum(den_t) as den
      from src
     group by rd
  ),
  cum as materialized (
    select rd,
           sum(num) over (order by rd) as cnum,
           sum(den) over (order by rd) as cden
      from by_rd
  )
  select d.d,
         (select c.cnum / nullif(c.cden, 0)
            from cum c
           where c.rd <= d.d        -- date promotes to midnight, as before
           order by c.rd desc
           limit 1)
    from (select distinct u as d from unnest(p_dates) u) d;
$function$;

comment on function public.origin_roasted_cost_on_dates(text, text, date[]) is
  'Cost of a roasted pound of this origin as at each given date, as one '
  'cumulative pass instead of one aggregate per date. The scalar '
  'get_origin_roasted_cost_on_date delegates here; this is the only copy of '
  'the formula. Returns one row per distinct date, cost NULL where the '
  'aggregate had nothing to divide.';

create or replace function public.get_origin_roasted_cost_on_date(
  p_origin_id   text,
  p_facility_id text,
  p_order_date  date
)
returns numeric
language plpgsql
as $function$
begin
  -- One formula, two entry points. NULL => caller falls back to the
  -- group/shipment path, exactly as before.
  return (select o.cost
            from public.origin_roasted_cost_on_dates(
                   p_origin_id, p_facility_id, array[p_order_date]) o);
end;
$function$;

-- ---------------------------------------------------------------------------
-- The same idea one level up: unit COGS for a whole SET of (product,
-- facility, date) keys, passed as three parallel arrays. The key set is
-- collapsed to its distinct (origin, facility) pairs, each of which is costed
-- once for every date it needs, and the answers are joined back.
-- ---------------------------------------------------------------------------
create or replace function public.product_cogs_for_keys(
  p_product_ids  text[],
  p_facility_ids text[],
  p_order_dates  date[]
)
returns table (product_id text, facility_id text, order_date date, cogs numeric)
language sql
as $function$
  with keys as materialized (
    -- The i-th element of each array is one key. A short array pads with
    -- nulls, and a null key has no answer, so drop them.
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
    -- product that no longer exists gets a null answer, as the scalar gave.
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
    -- THE POINT OF THE WHOLE FILE: one cumulative pass per distinct
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
$function$;

comment on function public.product_cogs_for_keys(text[], text[], date[]) is
  'Unit COGS for a set of (product, facility, date) keys given as three '
  'parallel arrays. Collapses the set to its distinct (origin, facility) '
  'pairs and makes one cumulative roasted-cost pass each, so the work scales '
  'on origins rather than on products. The scalar get_product_cogs_on_date '
  'delegates here; this is the only copy of the formula. One row per distinct '
  'non-null key; cogs NULL where nothing contributed a cost.';

create or replace function public.get_product_cogs_on_date(
  p_product_id  text,
  p_facility_id text,
  p_order_date  date
)
returns numeric
language plpgsql
as $function$
begin
  return (select c.cogs
            from public.product_cogs_for_keys(
                   array[p_product_id], array[p_facility_id],
                   array[p_order_date]) c);
end;
$function$;

-- Match the privileges the scalars already carry: no PUBLIC, no anon.
revoke all on function public.origin_roasted_cost_on_dates(text, text, date[]) from public;
revoke all on function public.product_cogs_for_keys(text[], text[], date[])      from public;
grant execute on function public.origin_roasted_cost_on_dates(text, text, date[]) to authenticated, service_role;
grant execute on function public.product_cogs_for_keys(text[], text[], date[])      to authenticated, service_role;

-- Does the cumulative series answer exactly as the per-date aggregate did?
-- The previous formula is recomputed here by join-and-group -- an independent
-- strategy, not a restatement of the new one -- and compared on EVERY
-- breakpoint of the input domain. With no roast data there is nothing to
-- compare and this passes vacuously, so it is safe on staging.
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
      'origin_roasted_cost_on_dates disagrees with the previous formula on % of % breakpoints',
      v_bad, v_pts;
  end if;

  -- and the scalar must still agree with the bulk form it now delegates to,
  -- at the last breakpoint of every pair (self-contained: a CTE from the
  -- statement above does not reach this one).
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
      'get_origin_roasted_cost_on_date does not match the bulk form for % pairs', v_bad;
  end if;
end $$;

-- product_cogs_for_keys is new in SHAPE, not in formula. What a reshape can
-- break is the collapse to distinct origins and the joins back: a key crossed
-- with the wrong origin, a row multiplied, a date misaligned. So the whole key
-- set asked at once must answer exactly as those keys asked ONE AT A TIME,
-- which runs the identical formula at cardinality one where no collapse
-- happens. Bounded to 60 real keys so a release does not spend minutes here;
-- the exhaustive sweep over 7,979 keys -- 388 resold, 618 with no recipe, 506
-- with no size, 8 naming a product that no longer exists -- was run read-only
-- against production. Vacuous with no order lines.
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
     limit 60
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
  ),
  one as (
    select k.product_id, k.facility_id, k.order_date,
           (select c.cogs
              from public.product_cogs_for_keys(
                     array[k.product_id], array[k.facility_id],
                     array[k.order_date]) c) as cogs
      from k
  )
  select (select count(*) from k),
         (select count(*) from bulk),
         (select count(*)
            from one o
            join bulk b
              on b.product_id  = o.product_id
             and b.facility_id = o.facility_id
             and b.order_date  = o.order_date
           where o.cogs is distinct from b.cogs)
    into v_keys, v_rows, v_bad;

  if v_rows <> v_keys then
    raise exception
      'product_cogs_for_keys returned % rows for % distinct keys', v_rows, v_keys;
  end if;
  if v_bad > 0 then
    raise exception
      'product_cogs_for_keys answers % of % keys differently in bulk than one at a time',
      v_bad, v_keys;
  end if;
end $$;

commit;
