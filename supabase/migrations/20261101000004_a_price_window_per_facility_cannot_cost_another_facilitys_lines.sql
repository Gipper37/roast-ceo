-- A price window per facility cannot cost another facility's lines.
--
-- recost_orders_for_consumable_purchases picked the order lines to re-cost by
-- joining product_consumables on consumable_id ALONE:
--
--     join public.product_consumables pc on pc.consumable_id = b.consumable_inventory_item
--     join public.order_details od       on od.product_id  = pc.product_id
--                                       and od.facility_id = pc.facility_id
--
-- Nothing tied pc to the purchase's facility, so ANY product_consumables row
-- naming that consumable pulled its products' order lines in, wherever they
-- were. The price window those lines are costed against is per (consumable,
-- facility) -- bounded's next_date subquery constrains
-- `cp.facility_id = w.facility_id` -- so this was already inconsistent before
-- tenancy enters the argument: lines at facility B were being re-priced from a
-- window computed for facility A.
--
-- Because a facility belongs to exactly one company, it also crossed tenants.
-- Measured on production for shipment 6KKKTKnn (company R7CbqHmA1j):
--
--     pc.company_id = R7CbqHmA1j  facility cc844abb (the purchase's own)
--         136 rows -> 6,325 order lines                        correct
--     pc.company_id = 752af3ed-4  facility b9b37e83 (Social Hour UK)
--           1 row  ->   319 order lines                        NOT this tenant
--
-- App-wide: 1 of 239 consumable purchases reaches another facility, and it is
-- that one. The DATA is not at fault -- product_consumables.company_id agrees
-- with its facility's company on all 1,507 rows. The column exists and the
-- function never read it.
--
-- NOT a value fault: product_cogs_for_keys computes each line's cost from that
-- line's own product, facility and date, so the 319 figures were right for
-- those lines. What was wrong is that company A receiving a shipment fired
-- writes -- unit_cost_at_sale, updated_at, and order_details' four AFTER
-- UPDATE triggers -- on company B's rows.
--
-- Pre-existing: the per-line loop this replaced carried the identical join, and
-- 20261101000003 preserved it deliberately. Nothing got worse; nothing got
-- better either.
--
-- This is a CORRECTNESS change, not a speed one. It removes 319 of 6,644 lines
-- from that shipment's set -- about 5%, which is not a reason to do it.
-- ---------------------------------------------------------------------------

begin;

CREATE OR REPLACE FUNCTION public.recost_orders_for_consumable_purchases(p_consumable_purchase_ids text[])
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
declare
  v_ids text[];
begin
  if p_consumable_purchase_ids is null
     or cardinality(p_consumable_purchase_ids) = 0 then
    return 0;
  end if;

  with line as materialized (
    -- A line with no price of its own contributes nothing to look up.
    select cp.consumable_purchase_id, cp.consumable_inventory_item,
           cp.facility_id, cp.shipment_id
      from public.consumable_inventory_purchased cp
     where cp.consumable_purchase_id = any (p_consumable_purchase_ids)
       and coalesce(cp.cost_unit, 0) <> 0
  ),
  win as materialized (
    select l.consumable_purchase_id, l.consumable_inventory_item, l.facility_id,
           (select sr.date_received
              from public.shipment_received sr
             where sr.shipment_id = l.shipment_id
               and coalesce(sr.voided, false) = false
             limit 1) as this_date
      from line l
  ),
  bounded as materialized (
    -- as materialized, ALL THREE, and it is not a style choice. Plain CTEs get
    -- pulled up, and then these two target-list subqueries are copied into the
    -- join filter below and evaluated once per CANDIDATE ORDER ROW instead of
    -- once per line -- next_date seq-scans consumable_inventory_purchased, so
    -- measured on production for 6KKKTKnn: SubPlan loops 8,601 and 4,507,
    -- 1,628 ms, against loops=3 and 183 ms materialized. Same rows either way;
    -- recost_order_details above materializes all three of its CTEs for the
    -- same reason.
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
        -- The price window above is already per (consumable, FACILITY) --
        -- bounded's next_date subquery constrains cp.facility_id = w.facility_id.
        -- Joining pc on consumable_id alone then costed lines at OTHER
        -- facilities against a window computed for this one, which is
        -- incoherent on its own terms and, because a facility belongs to one
        -- company, reached other tenants' order lines. Measured on production
        -- for 6KKKTKnn: 136 product_consumables rows in the purchase's own
        -- facility -> 6,325 lines, and ONE row in Social Hour UK's facility ->
        -- 319 lines belonging to company 752af3ed-4. App-wide 1 of 239
        -- consumable purchases crossed. Making the join agree with the window
        -- closes that as a consequence rather than as a tenancy special case.
        and pc.facility_id = b.facility_id
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

-- ---------------------------------------------------------------------------
-- Verify. Both halves can fail, and the second says so when it cannot
-- discriminate rather than passing quietly.
-- ---------------------------------------------------------------------------
do $$
declare
  v_def        text;
  v_unscoped   bigint;
  v_scoped     bigint;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'recost_orders_for_consumable_purchases';

  if v_def is null then
    raise exception 'recost_orders_for_consumable_purchases is missing';
  end if;

  -- the new predicate, and the body it must still contain
  if position('pc.facility_id = b.facility_id' in v_def) = 0 then
    raise exception 'the facility predicate is not in the function body';
  end if;
  if position('recost_order_details' in v_def) = 0
     or position('next_date' in v_def) = 0
     or position('books_closed_through' in v_def) = 0 then
    raise exception 'the function body lost something: % chars', length(v_def);
  end if;

  -- Behavioural, schema-derived: for every consumable purchase, no
  -- product_consumables row outside its own facility may be reachable once
  -- the predicate applies. Count both ways so a pass means something.
  select count(*) filter (where pc.facility_id is distinct from cp.facility_id),
         count(*) filter (where pc.facility_id = cp.facility_id)
    into v_unscoped, v_scoped
    from public.consumable_inventory_purchased cp
    join public.product_consumables pc
         on pc.consumable_id = cp.consumable_inventory_item;

  if v_unscoped = 0 then
    -- Not a pass. Say so, rather than let a vacuous check read as proof.
    raise notice 'VACUOUS HERE: no consumable purchase on this database reaches a product_consumables row outside its own facility, so the behavioural half proved nothing. % in-facility pairs seen.', v_scoped;
  else
    raise notice 'the predicate excludes % cross-facility pair(s), keeping % in-facility pair(s)', v_unscoped, v_scoped;
  end if;

  if v_scoped = 0 then
    raise exception 'no in-facility product_consumables pairs at all -- the join would now match nothing, which cannot be right';
  end if;
end $$;

commit;
