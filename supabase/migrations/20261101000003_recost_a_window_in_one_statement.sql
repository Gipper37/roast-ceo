-- Re-cost a window in one statement.
--
-- Four functions re-cost order lines, and all four had the identical shape:
--
--     FOR v_rec IN <lines in the affected window> LOOP
--       v_new_cost := public.get_product_cogs_on_date(product, facility, date);
--       IF v_new_cost IS NOT NULL AND v_new_cost > 0 THEN UPDATE one row; END IF;
--     END LOOP;
--
-- One COGS aggregate per order line. For shipment 6KKKTKnn that is 6,644 of
-- them at 24 ms -- 2m15s, past the 60s an authenticated session gets -- and
-- backfill_order_unit_costs with no arguments would do it for all 44,828 lines.
-- The previous migration gave COGS a bulk form; this one lets these callers
-- reach it. 6,644 aggregates becomes 13 cumulative passes: the 6,644 lines
-- hold 119 (product, facility) groups over 538 dates, but only THIRTEEN
-- distinct (origin, facility) pairs, and it is the origins that cost anything.
-- Measured end to end on production: 2m15s becomes ~4s.
--
-- The costing itself is unchanged -- product_cogs_for_keys is the same formula
-- the scalar now delegates to, proved equal to the previous one across every
-- product shape in production.
--
-- TWO DELIBERATE BEHAVIOUR CHANGES, both narrowing writes, never values:
--
--  1. recost_orders_for_consumable_purchase already skipped a row whose cost
--     had not moved (`unit_cost_at_sale is distinct from`). The other three did
--     not: they rewrote every row, bumping updated_at and firing all four of
--     order_details' AFTER UPDATE triggers -- order totals and consumable
--     stock both recompute per row -- to store the number already there. The
--     guard now applies to all four.
--  2. Consequently backfill_order_unit_costs returns the number of lines
--     CHANGED, where it used to return the number costed. It is a manual
--     maintenance function: no trigger, no database caller, no frontend
--     reference.
--
-- refresh_consumables_for_shipment and propagate_shipping_to_consumable_orders
-- are deliberately NOT touched. They loop a shipment's consumable lines
-- calling recost_orders_for_consumable_purchase, which is batched below, and
-- the lines' order sets are disjoint by (product, facility, date) -- measured:
-- 3,981 distinct triples whether deduplicated per line or across the shipment
-- -- so there is nothing further to win by merging their windows.

begin;

-- ---------------------------------------------------------------------------
-- The one place that re-costs order lines.
-- ---------------------------------------------------------------------------
create or replace function public.recost_order_details(p_order_detail_ids text[])
returns integer
language plpgsql
as $function$
declare
  v_touched integer := 0;
begin
  if p_order_detail_ids is null or cardinality(p_order_detail_ids) = 0 then
    return 0;
  end if;

  with lines as materialized (
    -- A line with no product, facility or date could never be costed: the
    -- scalar returned NULL for it and the loop skipped it.
    select od.order_detail_id, od.product_id, od.facility_id,
           od.order_date, od.quantity
      from public.order_details od
     where od.order_detail_id = any (p_order_detail_ids)
       and od.product_id  is not null
       and od.facility_id is not null
       and od.order_date  is not null
  ),
  keyset as materialized (
    -- Three parallel arrays, aggregated in ONE pass so the i-th elements are
    -- the same row. Three separate array() subqueries would not guarantee
    -- that. Duplicates are fine; the function takes the key set distinct.
    select array_agg(l.product_id)  as product_ids,
           array_agg(l.facility_id) as facility_ids,
           array_agg(l.order_date)  as order_dates
      from lines l
  ),
  costs as materialized (
    -- ONE bulk call for the whole window: it collapses the key set to its
    -- distinct origins, so the roasted-cost passes scale on how many origins
    -- the roaster has, not on how many products or lines are in the window.
    select c.product_id, c.facility_id, c.order_date, c.cogs
      from keyset k
      cross join lateral public.product_cogs_for_keys(
                   k.product_ids, k.facility_ids, k.order_dates) c
  )
  update public.order_details od
     set unit_cost_at_sale = c.cogs * l.quantity,
         updated_at        = now()
    from lines l
    join costs c
      on c.product_id  = l.product_id
     and c.facility_id = l.facility_id
     and c.order_date  = l.order_date
   where od.order_detail_id = l.order_detail_id
     and c.cogs is not null
     and c.cogs > 0
     and od.unit_cost_at_sale is distinct from (c.cogs * l.quantity);

  get diagnostics v_touched = row_count;
  return v_touched;
end;
$function$;

comment on function public.recost_order_details(text[]) is
  'Re-cost these order lines from product_cogs_for_keys and return how many '
  'CHANGED. One bulk COGS call for the whole window rather than one aggregate '
  'per line. The only place order_details.unit_cost_at_sale is recomputed in '
  'bulk.';

revoke all on function public.recost_order_details(text[]) from public;
grant execute on function public.recost_order_details(text[]) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 1 of 4 -- a consumable line's price window.
-- ---------------------------------------------------------------------------
create or replace function public.recost_orders_for_consumable_purchase(
  p_consumable_purchase_id text
)
returns integer
language plpgsql
as $function$
declare
  v_row        record;
  v_this_date  date;
  v_next_date  date;
  v_ids        text[];
begin
  select cp.consumable_purchase_id, cp.consumable_inventory_item, cp.facility_id,
         cp.cost_unit, cp.shipment_id
    into v_row
    from public.consumable_inventory_purchased cp
   where cp.consumable_purchase_id = p_consumable_purchase_id;
  if v_row.consumable_purchase_id is null then return 0; end if;

  -- A line with no price of its own contributes nothing to look up.
  if coalesce(v_row.cost_unit, 0) = 0 then return 0; end if;

  select sr.date_received into v_this_date
    from public.shipment_received sr
   where sr.shipment_id = v_row.shipment_id
     and coalesce(sr.voided, false) = false
   limit 1;
  -- Never received means it was never the price of record for anything.
  if v_this_date is null then return 0; end if;

  select sr.date_received into v_next_date
    from public.consumable_inventory_purchased cp
    join public.shipment_received sr on sr.shipment_id = cp.shipment_id
   where cp.consumable_inventory_item = v_row.consumable_inventory_item
     and cp.facility_id               = v_row.facility_id
     and sr.date_received            is not null
     and sr.date_received             > v_this_date
     and cp.consumable_purchase_id   <> v_row.consumable_purchase_id
     and coalesce(sr.voided, false) = false
   order by sr.date_received asc
   limit 1;

  select coalesce(array_agg(distinct od.order_detail_id), '{}')
    into v_ids
    from public.order_details od
    join public.orders o on o.order_id = od.order_id
    join public.product_consumables pc
         on pc.product_id = od.product_id and pc.facility_id = od.facility_id
    join public.companies cmp on cmp.company_id = od.company_id
   where o.order_status  <> 'Canceled'
     and od.order_date   >= v_this_date
     and (v_next_date is null or od.order_date < v_next_date)
     and od.order_date    > coalesce(cmp.books_closed_through, '-infinity'::date)
     and coalesce(o.is_legacy_import, false) = false
     and pc.consumable_id = v_row.consumable_inventory_item
     and coalesce(od.quantity, 0) > 0;

  return public.recost_order_details(v_ids);
end;
$function$;

-- ---------------------------------------------------------------------------
-- 2 of 4 -- a coffee shipment's origin window. The same user-visible bug as
-- the consumable path, on coffee shipments.
-- ---------------------------------------------------------------------------
create or replace function public.propagate_coffee_cost_for_shipment_origin(
  p_shipment_id text,
  p_origin      text,
  p_facility    text
)
returns void
language plpgsql
as $function$
DECLARE
    v_this_date date;
    v_next_date date;
    v_ids       text[];
BEGIN
    SELECT sr.date_received INTO v_this_date
      FROM public.shipment_received sr
     WHERE sr.shipment_id = p_shipment_id AND COALESCE(sr.voided, false) = false
     LIMIT 1;
    IF v_this_date IS NULL THEN RETURN; END IF;

    SELECT sr.date_received INTO v_next_date
      FROM public.coffee_inventory_purchased cp
      JOIN public.shipment_received sr ON sr.shipment_id = cp.shipment_id
     WHERE cp.origin = p_origin AND cp.facility_id = p_facility
       AND sr.date_received IS NOT NULL AND sr.date_received > v_this_date
       AND cp.shipment_id != p_shipment_id AND COALESCE(sr.voided, false) = false
     ORDER BY sr.date_received ASC LIMIT 1;

    SELECT COALESCE(array_agg(DISTINCT od.order_detail_id), '{}') INTO v_ids
      FROM public.order_details od
      JOIN public.orders o    ON o.order_id   = od.order_id
      JOIN public.products p  ON p.product_id = od.product_id
      JOIN public.recipe_components rc ON rc.recipe_id = p.recipe_id AND rc.facility_id = od.facility_id
      JOIN public.companies cmp ON cmp.company_id = od.company_id
     WHERE o.order_status != 'Canceled'
       AND od.order_date >= v_this_date
       AND (v_next_date IS NULL OR od.order_date < v_next_date)
       AND od.order_date  > COALESCE(cmp.books_closed_through, '-infinity'::date)  -- books-closed guard (restored)
       AND rc.coffee_item = p_origin
       AND COALESCE(od.quantity, 0) > 0;

    PERFORM public.recost_order_details(v_ids);
END;
$function$;

-- ---------------------------------------------------------------------------
-- 3 of 4 -- the lot-recompute drain's window.
-- ---------------------------------------------------------------------------
create or replace function public.propagate_origin_cogs_window(
  p_origin   text,
  p_facility text
)
returns void
language plpgsql
as $function$
DECLARE
    v_from   date;
    v_closed date;
    v_ids    text[];
BEGIN
    IF p_origin IS NULL OR p_facility IS NULL THEN RETURN; END IF;

    SELECT MAX(clc.count_at)::date INTO v_from
      FROM public.coffee_lot_count clc
      JOIN public.coffee_inventory_purchased cip ON cip.origin_purchase_id = clc.origin_purchase_id
     WHERE cip.origin = p_origin AND cip.facility_id = p_facility;
    v_from := COALESCE(v_from, (now() - interval '30 days')::date);

    SELECT c.books_closed_through INTO v_closed
      FROM public.coffee_inventory ci
      JOIN public.companies c ON c.company_id = ci.company_id
     WHERE ci.origin_id = p_origin AND ci.facility_id = p_facility
     LIMIT 1;
    IF v_closed IS NOT NULL AND v_closed >= v_from THEN
        v_from := v_closed + 1;   -- closed periods keep their booked COGS
    END IF;

    SELECT COALESCE(array_agg(DISTINCT od.order_detail_id), '{}') INTO v_ids
      FROM public.order_details od
      JOIN public.orders o   ON o.order_id   = od.order_id
      JOIN public.products p ON p.product_id = od.product_id
      JOIN public.recipe_components rc ON rc.recipe_id = p.recipe_id AND rc.facility_id = od.facility_id
     WHERE o.order_status != 'Canceled'
       AND od.facility_id = p_facility
       AND od.order_date >= v_from
       AND rc.coffee_item = p_origin
       AND COALESCE(od.quantity, 0) > 0;

    PERFORM public.recost_order_details(v_ids);
END;
$function$;

-- ---------------------------------------------------------------------------
-- 4 of 4 -- the manual backfill. Returns lines CHANGED now, not lines costed.
-- ---------------------------------------------------------------------------
create or replace function public.backfill_order_unit_costs(
  p_from_date   date default null::date,
  p_to_date     date default null::date,
  p_facility_id text default null::text
)
returns integer
language plpgsql
as $function$
DECLARE
    v_ids text[];
BEGIN
    SELECT COALESCE(array_agg(od.order_detail_id), '{}') INTO v_ids
      FROM public.order_details od
      JOIN public.orders o      ON o.order_id    = od.order_id
      JOIN public.companies cmp ON cmp.company_id = od.company_id
     WHERE o.order_status    != 'Canceled'
       AND COALESCE(od.quantity, 0) > 0
       AND od.order_date      > COALESCE(cmp.books_closed_through, '-infinity'::date)  -- books-closed guard
       AND (p_from_date   IS NULL OR od.order_date >= p_from_date)
       AND (p_to_date     IS NULL OR od.order_date <= p_to_date)
       AND (p_facility_id IS NULL OR od.facility_id = p_facility_id);

    RETURN public.recost_order_details(v_ids);
END;
$function$;

-- Did every caller actually get rewritten? Asserted on the STORED BODIES, so
-- a function I left behind fails the release instead of shipping the old
-- per-line loop. The previous verify block here compared the bulk function
-- against the scalar that now delegates to it: it could only pass.
do $$
declare
  v_found   integer;
  v_missing text;
begin
  select count(distinct p.proname) into v_found
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('recost_orders_for_consumable_purchase',
                       'propagate_coffee_cost_for_shipment_origin',
                       'propagate_origin_cogs_window',
                       'backfill_order_unit_costs');
  if v_found <> 4 then
    raise exception 'expected 4 order-line re-cost callers in public, found %', v_found;
  end if;

  select string_agg(distinct p.proname, ', ' order by p.proname) into v_missing
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('recost_orders_for_consumable_purchase',
                       'propagate_coffee_cost_for_shipment_origin',
                       'propagate_origin_cogs_window',
                       'backfill_order_unit_costs')
     and (p.prosrc not like '%recost_order_details%'
          or p.prosrc like '%get_product_cogs_on_date%');
  if v_missing is not null then
    raise exception 'these still cost order lines one at a time: %', v_missing;
  end if;
end $$;

commit;
