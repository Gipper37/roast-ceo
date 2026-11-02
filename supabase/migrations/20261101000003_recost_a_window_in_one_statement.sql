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
-- reach it. 6,644 aggregates becomes 13 ordered passes: the 6,644 lines hold
-- 106 (product, facility) groups over 495 dates, but only THIRTEEN distinct
-- (origin, facility) pairs, and it is the origins that cost anything.
-- Measured on production with every value consumed: 2m15s -> 1.63 s.
--
-- 13 only if the shipment's lines are costed TOGETHER. An earlier draft left
-- refresh_consumables_for_shipment's per-line loop alone, reasoning that the
-- lines' order sets are disjoint -- which is true by (product, facility, date)
-- and irrelevant, because each call collapses only ITS OWN key set to distinct
-- origins. Measured on production: the three lines of 6KKKTKnn hold 2,550 +
-- 1,707 + 2,387 = 6,644 order lines and 3,981 distinct triples, disjoint as
-- claimed -- but 27 distinct (origin, facility) pairs across the three calls
-- against 13 for the union (measured on production: 13 batched, 27 per line),
-- with the hot origin (6,416 rows) in all three.
-- Disjoint order lines do not make disjoint origins. So the per-line window is
-- unchanged and still its own price period, but the lines are now costed in
-- one call: recost_orders_for_consumable_purchases takes the set.
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
-- 1 of 5 -- a SET of consumable lines' price windows, unioned.
--
-- Each line keeps its own window: this receipt's date up to the next receipt
-- of the same item at the same facility, exactly as the single-line form built
-- it. They are only costed together, so an origin two lines share is passed
-- over once instead of once per line.
-- ---------------------------------------------------------------------------
create or replace function public.recost_orders_for_consumable_purchases(
  p_consumable_purchase_ids text[]
)
returns integer
language plpgsql
as $function$
declare
  v_ids text[];
begin
  if p_consumable_purchase_ids is null
     or cardinality(p_consumable_purchase_ids) = 0 then
    return 0;
  end if;

  with line as (
    -- A line with no price of its own contributes nothing to look up.
    select cp.consumable_purchase_id, cp.consumable_inventory_item,
           cp.facility_id, cp.shipment_id
      from public.consumable_inventory_purchased cp
     where cp.consumable_purchase_id = any (p_consumable_purchase_ids)
       and coalesce(cp.cost_unit, 0) <> 0
  ),
  win as (
    select l.consumable_purchase_id, l.consumable_inventory_item, l.facility_id,
           (select sr.date_received
              from public.shipment_received sr
             where sr.shipment_id = l.shipment_id
               and coalesce(sr.voided, false) = false
             limit 1) as this_date
      from line l
  ),
  bounded as (
    -- Never received means it was never the price of record for anything.
    select w.consumable_purchase_id, w.consumable_inventory_item, w.facility_id,
           w.this_date,
           (select sr.date_received
              from public.consumable_inventory_purchased cp
              join public.shipment_received sr on sr.shipment_id = cp.shipment_id
             where cp.consumable_inventory_item = w.consumable_inventory_item
               and cp.facility_id               = w.facility_id
               and sr.date_received            is not null
               and sr.date_received             > w.this_date
               and cp.consumable_purchase_id   <> w.consumable_purchase_id
               and coalesce(sr.voided, false) = false
             order by sr.date_received asc
             limit 1) as next_date
      from win w
     where w.this_date is not null
  )
  select coalesce(array_agg(distinct od.order_detail_id), '{}')
    into v_ids
    from bounded b
    join public.product_consumables pc
         on pc.consumable_id = b.consumable_inventory_item
    join public.order_details od
         on od.product_id  = pc.product_id
        and od.facility_id = pc.facility_id
    join public.orders o on o.order_id = od.order_id
    join public.companies cmp on cmp.company_id = od.company_id
   where o.order_status  <> 'Canceled'
     and od.order_date   >= b.this_date
     and (b.next_date is null or od.order_date < b.next_date)
     and od.order_date    > coalesce(cmp.books_closed_through, '-infinity'::date)
     and coalesce(o.is_legacy_import, false) = false
     and coalesce(od.quantity, 0) > 0;

  return public.recost_order_details(v_ids);
end;
$function$;

comment on function public.recost_orders_for_consumable_purchases(text[]) is
  'Re-cost the order lines in these consumable lines'' price windows, in one '
  'call, and return how many CHANGED. One window per line as before; costed '
  'together so a shared origin is passed over once.';

revoke all on function public.recost_orders_for_consumable_purchases(text[]) from public;
grant execute on function public.recost_orders_for_consumable_purchases(text[]) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2 of 5 -- one consumable line. Signature kept; it is called from the
-- shipment-line trigger and from propagate_shipping_to_consumable_orders.
-- ---------------------------------------------------------------------------
create or replace function public.recost_orders_for_consumable_purchase(
  p_consumable_purchase_id text
)
returns integer
language plpgsql
as $function$
begin
  return public.recost_orders_for_consumable_purchases(
           array[p_consumable_purchase_id]);
end;
$function$;

-- ---------------------------------------------------------------------------
-- 3 of 5 -- a coffee shipment's origin window. The same user-visible bug as
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
-- 4 of 5 -- the lot-recompute drain's window.
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
-- 5 of 5 -- the manual backfill. Returns lines CHANGED now, not lines costed.
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

-- ---------------------------------------------------------------------------
-- And the shipment trigger that drives them: one call, not one per line.
-- Body taken verbatim from production with only that loop replaced.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.refresh_consumables_for_shipment()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare
  r record;
begin
  -- Two things make a shipment's consumables worth recomputing: the per-unit
  -- shipping moved (a shipping edit, or a units correction re-deriving it), or
  -- the delivery finally landed and started counting at all.
  if old.shipping_cost_unit is not distinct from new.shipping_cost_unit
     and old.date_received is not distinct from new.date_received then
    return null;
  end if;

  -- Cached figures first, so anything reading them afterwards is current.
  -- Stock belongs here and not only on the line trigger: that trigger runs
  -- while the header is still undated, so its recount cannot see these rows.
  --
  -- Cost and stock are per ITEM, so a shipment carrying four lines of the same
  -- box recomputes it once, not four times. The order re-cost stays per LINE
  -- because that is what it keys on. Splitting the loops also means every cost
  -- is current before the first re-cost reads one.
  for r in
    select distinct consumable_inventory_item, facility_id
      from public.consumable_inventory_purchased
     where shipment_id = new.shipment_id
       and facility_id is not distinct from new.facility_id
  loop
    perform public.refresh_last_consumable_cost(r.consumable_inventory_item, r.facility_id);
    perform public.refresh_consumable_stock(r.consumable_inventory_item, r.facility_id);
  end loop;

  -- ONE call for the whole shipment. Each line still gets its own price
  -- window; costing them together is what makes an origin shared between two
  -- lines a single pass instead of one per line.
  perform public.recost_orders_for_consumable_purchases(
    array(select cp.consumable_purchase_id
            from public.consumable_inventory_purchased cp
           where cp.shipment_id = new.shipment_id
             and cp.facility_id is not distinct from new.facility_id));
  return null;
end;
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
     and p.proname in ('recost_orders_for_consumable_purchases',
                       'recost_orders_for_consumable_purchase',
                       'propagate_coffee_cost_for_shipment_origin',
                       'propagate_origin_cogs_window',
                       'backfill_order_unit_costs');
  if v_found <> 5 then
    raise exception 'expected 5 order-line re-cost callers in public, found %', v_found;
  end if;

  select string_agg(distinct p.proname, ', ' order by p.proname) into v_missing
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('recost_orders_for_consumable_purchases',
                       'propagate_coffee_cost_for_shipment_origin',
                       'propagate_origin_cogs_window',
                       'backfill_order_unit_costs')
     and (p.prosrc not like '%recost_order_details%'
          or p.prosrc like '%get_product_cogs_on_date%');
  if v_missing is not null then
    raise exception 'these still cost order lines one at a time: %', v_missing;
  end if;

  -- and the shipment trigger must drive the SET, not loop the lines
  select string_agg(distinct p.proname, ', ') into v_missing
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('refresh_consumables_for_shipment',
                       'recost_orders_for_consumable_purchase')
     and p.prosrc not like '%recost_orders_for_consumable_purchases%';
  if v_missing is not null then
    raise exception 'these still re-cost a shipment one line at a time: %', v_missing;
  end if;
end $$;

commit;
