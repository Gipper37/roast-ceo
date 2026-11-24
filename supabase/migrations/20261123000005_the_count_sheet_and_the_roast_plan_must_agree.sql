-- ─────────────────────────────────────────────────────────────────────────────
-- A manual count takes precedence, and both screens must say the same number.
--
-- Owner, 2026-11-23: *"manual counts take precedence. i dont get what you did
-- when you set this up if its set up that way."*
--
-- WHERE IT ALREADY DOES. `recipe_bagged_applied` and `roast_detail_by_blend`
-- have read `pack_stock_count` since 20261029000004: the newest count per
-- product inside the 28-day window, less whatever shipped since the count,
-- floored at zero. So the ROAST PLAN is built on the count.
--
-- WHERE IT DOES NOT. The count sheet's own "On shelf" column comes from
-- `pack_run_remaining` -- the bagging records -- and nothing else does. That is
-- the figure the operator is looking at while typing, and the figure stored as
-- `system_bags` on the next count. So a count saves, changes the plan, and
-- appears to have done nothing, which is exactly what was reported.
--
-- WHY A FUNCTION AND NOT A SECOND COPY OF THE ARITHMETIC. The rule exists once
-- today, buried inside `recipe_bagged_applied`, where it is aggregated to a
-- RECIPE and multiplied by weight and share. The sheet needs it per PRODUCT,
-- in bags. Writing that again in TypeScript on the page would be a second
-- definition in a second language, and the day they disagree is the day the
-- sheet and the plan show two different shelves -- which is the bug being
-- fixed here, not a new one to introduce.
--
-- PROVEN BEFORE THIS FILE WAS WRITTEN, on prod, read-only. The body below was
-- taken from the live `recipe_bagged_applied` source, then its per-product
-- output was multiplied back out by the same weight-and-share arithmetic and
-- compared recipe by recipe against `recipe_bagged_applied` itself:
--
--     37 recipes, rolled up from 80 counted products, ZERO differences
--     (full outer join, rounded to 10dp, only non-zero rows selected).
--
-- 🔴 WHAT THAT PROOF COULD NOT CATCH, stated rather than left implied: a
-- counted product whose recipe has no `recipe_demand_source` row with
-- `share > 0` is excluded from BOTH sides, so its figure was not graded. The
-- per-product expression is the same for those rows, so the exposure is the
-- expression being wrong in a way that happens to cancel -- not possible here,
-- because the two sides compute the window and the shipped-since subquery from
-- independent copies.
--
-- ADDITIVE. Nothing existing is altered: `recipe_bagged_applied` keeps its own
-- body and the plan keeps behaving exactly as it does today. Making that
-- function call this one, so the rule lives in ONE place, is a separate change
-- that rewrites a function the roast plan depends on, and it is not worth
-- bundling with a display fix.
-- ─────────────────────────────────────────────────────────────────────────────

begin;

create or replace function public.pack_counted_remaining(p_facility_id text)
returns table (
  product_id       text,
  counted_at       timestamptz,
  counted_bags     numeric,
  bags_still_there numeric
)
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
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
                    and coalesce((op.status_changed_at at time zone w.timezone)::date, op.order_date)
                        >= (l.counted_at at time zone w.timezone)::date), 0::numeric)) as bags_still_there
    from latest l
    cross join w;
$$;

comment on function public.pack_counted_remaining(text) is
  'Bags still on the shelf per product for a facility: the newest pack_stock_count inside the 28-day roast-week window, less what has shipped since it, floored at zero. The per-product form of the rule recipe_bagged_applied aggregates to a recipe; the count sheet reads this so the sheet and the roast plan cannot show two different shelves.';

-- 🔴 A NEW FUNCTION INHERITS NO EXECUTE GRANT. Matched to its sibling
-- recipe_bagged_applied, which is authenticated / postgres / service_role.
grant execute on function public.pack_counted_remaining(text) to authenticated;
grant execute on function public.pack_counted_remaining(text) to service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- Verify. Can pass and can fail: it compares this function's row set against
-- the count rows it is supposed to pick, for EVERY facility that has any count,
-- and says how many it checked so a vacuous run on an empty database is
-- visible rather than silently green.
-- ─────────────────────────────────────────────────────────────────────────────
do $verify$
declare
  f            record;
  checked      int := 0;
  expected     int;
  got          int;
  over_counted int;
begin
  for f in
    select distinct psc.facility_id,
           coalesce(nullif(fa.time_zone, ''::text), 'Pacific/Honolulu'::text) as tz
      from public.pack_stock_count psc
      join public.facilities fa on fa.facility_id = psc.facility_id
  loop
    select count(*) into got from public.pack_counted_remaining(f.facility_id);

    select count(distinct psc.product_id) into expected
      from public.pack_stock_count psc
      cross join lateral public.facility_week_starts(f.facility_id) ws
     where psc.facility_id = f.facility_id
       and (psc.counted_at at time zone f.tz)::date >= (ws.roast_week_start - interval '28 days');

    if got <> expected then
      raise exception 'pack_counted_remaining(%) returned % row(s); % product(s) have a count inside the window',
        f.facility_id, got, expected;
    end if;

    -- Shipments can only reduce the figure, and it can never go negative.
    select count(*) into over_counted
      from public.pack_counted_remaining(f.facility_id)
     where bags_still_there > counted_bags or bags_still_there < 0;

    if over_counted > 0 then
      raise exception 'pack_counted_remaining(%): % row(s) outside [0, counted_bags]',
        f.facility_id, over_counted;
    end if;

    checked := checked + 1;
  end loop;

  raise notice 'pack_counted_remaining verified against % facility/facilities holding counts', checked;
end
$verify$;

commit;
