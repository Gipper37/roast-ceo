-- Bags that left the shelf BEFORE the count are not subtracted from it again.
--
-- Finding 4 of the 24-hour audit, and PRE-EXISTING -- it arrived with
-- 20261029000004 and was carried forward unchanged into 20261123000005.
--
-- The shipped-since subquery compared CALENDAR DAYS:
--
--   coalesce((op.status_changed_at at time zone tz)::date, op.order_date)
--     >= (l.counted_at at time zone tz)::date
--
-- so every qualifying order whose status changed on the count's own day was
-- subtracted from the count, including the ones that shipped hours before the
-- operator walked the shelf. Those bags were already gone when the shelf was
-- counted, so counted_bags never included them, and subtracting them deducts
-- the same bags twice.
--
-- 🔴 IT IS IN BOTH TERMS, NOT ONE. The audit named pack_counted_remaining,
-- which feeds the count sheet. recipe_bagged_applied carries the identical
-- predicate and is what the ROAST PLAN reads, so the same phantom shortage
-- reached the plan. Read out of pg_proc on production, not out of the
-- migration that wrote it.
--
-- Measured on prod 2026-11-24: 80 counts in the 28-day window, 447 order
-- lines currently subtracted, and ZERO of them wrong -- every count in the
-- window was taken between 17:19 and 18:12 local, after the day's last
-- shipment. The error is one ordinary count away: MCR ships roughly
-- 07:00-15:30 (2026-11-18: 2249 bags, 07:33-15:22), so a 16:00 count on that
-- day would have deducted all 2249 a second time and floored every product
-- whose shipments exceeded its counted bags at zero -- under the label 'your
-- count', and stored in pack_stock_count.variance, the generated column that
-- exists so somebody can act on a discrepancy a month later.
--
-- Both bodies below are pg_get_functiondef output from production with ONLY
-- that predicate replaced. Nothing else is retyped. Both keep LANGUAGE sql,
-- STABLE, SET search_path and security invoker (the default, which is why
-- pg_get_functiondef does not print it), and CREATE OR REPLACE keeps the oid,
-- so the EXECUTE grants and the comments survive -- asserted below rather
-- than assumed.
--
-- No new permission key and no new column: this replaces two function bodies.

begin;

-- ──────────────────────────────────────────────────────────────────────
-- 1. The count sheet's figure.
-- ──────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.pack_counted_remaining(p_facility_id text)
 RETURNS TABLE(product_id text, counted_at timestamp with time zone, counted_bags numeric, bags_still_there numeric)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with w as (
    select ws.roast_week_start,
           coalesce(nullif(f.time_zone, ''::text), 'Pacific/Honolulu'::text) as timezone
      from facilities f
      cross join lateral public.facility_week_starts(f.facility_id) ws
     where f.facility_id = p_facility_id
  ),
  latest as (
    -- 🔴 NEWEST PER PRODUCT, NEVER A SUM. pack_stock_count is append-only, so
    -- the older rows are history; adding them would double count.
    select distinct on (psc.product_id) psc.product_id, psc.counted_bags, psc.counted_at
      from pack_stock_count psc
      cross join w
     where psc.facility_id = p_facility_id
       and (psc.counted_at at time zone w.timezone)::date >= (w.roast_week_start - interval '28 days')
     order by psc.product_id, psc.counted_at desc
  )
  -- The bags that are STILL THERE: counted, less what has shipped since the
  -- count. The window moves on the ROAST WEEK, not on today, so the cutoff
  -- jumps a week at a time on the facility's own reset day -- which is why a
  -- count can stop counting without anybody touching it.
  select l.product_id,
         l.counted_at,
         l.counted_bags,
         greatest(0::numeric, l.counted_bags - coalesce((
                 select sum(odp.quantity)::numeric
                   from order_details odp
                   join orders op on op.order_id = odp.order_id
                  where odp.product_id = l.product_id
                    and op.facility_id = p_facility_id
                    and op.order_status = ANY (ARRAY['Packed'::text, 'Delivered'::text, 'Shipped'::text])
                    -- 🔴 A TIMESTAMP, NOT A DATE. Comparing calendar days
                    -- subtracted every qualifying order that shipped on the
                    -- count's OWN day, including the ones that left hours
                    -- BEFORE the operator walked the shelf -- bags the count
                    -- never saw, deducted a second time.
                    and case
                          when op.status_changed_at is not null
                            then op.status_changed_at >= l.counted_at
                          -- No timestamp: a whole day is all that compares, so
                          -- a LATER day counts and the count's own day does
                          -- not. Erring the other way invents a shortage, and
                          -- the operator has just measured the shelf.
                          else op.order_date > (l.counted_at at time zone w.timezone)::date
                        end), 0::numeric)) as bags_still_there
    from latest l
    cross join w;
$function$;

-- ──────────────────────────────────────────────────────────────────────
-- 2. The same sum, aggregated to a recipe, which the roast plan reads.
-- ──────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.recipe_bagged_applied(p_facility_id text)
 RETURNS TABLE(recipe_id text, applied_lbs numeric)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with w as (
    select ws.roast_week_start,
           coalesce(nullif(f.time_zone, ''::text), 'Pacific/Honolulu'::text) as timezone
      from facilities f
      cross join lateral public.facility_week_starts(f.facility_id) ws
     where f.facility_id = p_facility_id
  ),
  latest as (
    select distinct on (psc.product_id) psc.product_id, psc.counted_bags, psc.counted_at
      from pack_stock_count psc
      cross join w
     where psc.facility_id = p_facility_id
       and (psc.counted_at at time zone w.timezone)::date >= (w.roast_week_start - interval '28 days')
     order by psc.product_id, psc.counted_at desc
  )
  select ds.recipe_id,
         -- The bags that are STILL THERE: counted, less what has shipped
         -- since the count. NOT capped at this variant's own demand -- a bag
         -- with no matching order is still finished coffee on a shelf, which
         -- is exactly what the backstock buffer is made of. See
         -- 20261029000006 for the arithmetic that settles it.
         sum(greatest(0::numeric, l.counted_bags - coalesce((
                 select sum(odp.quantity)::numeric
                   from order_details odp
                   join orders op on op.order_id = odp.order_id
                  where odp.product_id = l.product_id
                    and op.facility_id = p_facility_id
                    and op.order_status = ANY (ARRAY['Packed'::text, 'Delivered'::text, 'Shipped'::text])
                    -- 🔴 A TIMESTAMP, NOT A DATE. Comparing calendar days
                    -- subtracted every qualifying order that shipped on the
                    -- count's OWN day, including the ones that left hours
                    -- BEFORE the operator walked the shelf -- bags the count
                    -- never saw, deducted a second time.
                    and case
                          when op.status_changed_at is not null
                            then op.status_changed_at >= l.counted_at
                          -- No timestamp: a whole day is all that compares, so
                          -- a LATER day counts and the count's own day does
                          -- not. Erring the other way invents a shortage, and
                          -- the operator has just measured the shelf.
                          else op.order_date > (l.counted_at at time zone w.timezone)::date
                        end), 0::numeric))
                 * (coalesce(p.weight_lbs, 0::numeric)
                    / coalesce(nullif((select sz.units_per_case from size sz where sz.size_id = p.size), 0), 1))
             * ds.share) as applied_lbs
    from latest l
    cross join w
    join products p on p.product_id = l.product_id
    join recipe_demand_source ds on ds.source_recipe_id = p.recipe_id
   where ds.share > 0::numeric
   group by ds.recipe_id;
$function$;

-- ──────────────────────────────────────────────────────────────────────
-- What this leaves behind, asserted rather than assumed.
--
-- Can pass and can fail: the first counts a predicate that was in both bodies
-- and must now be in neither, the second counts the replacement that was in
-- neither and must now be in both, and the third re-checks the EXECUTE grant
-- CREATE OR REPLACE is supposed to have preserved.
--
-- It does NOT prove the new predicate changes an answer. That needs rows, and
-- a migration is the wrong place to invent them on a live database; it is
-- proven on a local cluster instead, against the real bodies, with a shipment
-- before the count and one after it.
-- ──────────────────────────────────────────────────────────────────────
do $verify$
declare
  v_old int;
  v_new int;
  v_exec int;
begin
  -- 🔴 COUNT THE CODE, NOT THE COMMENTS. prosrc carries the notes written
  -- above, and they name the old shape, so match the predicate's own text.
  select count(*) into v_old
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('pack_counted_remaining', 'recipe_bagged_applied')
     and p.prosrc ~ 'and coalesce\(\(op\.status_changed_at at time zone';
  if v_old <> 0 then
    raise exception 'the day-granular predicate is still in % function body(ies)', v_old;
  end if;

  select count(*) into v_new
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('pack_counted_remaining', 'recipe_bagged_applied')
     and p.prosrc like '%then op.status_changed_at >= l.counted_at%';
  if v_new <> 2 then
    raise exception 'expected the timestamp comparison in both bodies, found %', v_new;
  end if;

  select count(*) into v_exec
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('pack_counted_remaining', 'recipe_bagged_applied')
     and has_function_privilege('authenticated', p.oid, 'EXECUTE');
  if v_exec <> 2 then
    raise exception 'authenticated lost EXECUTE on % of the two functions', 2 - v_exec;
  end if;
end
$verify$;

commit;
