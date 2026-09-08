-- A bag comes back, and the answer is every bag that shares its green.
--
-- Owner, 2026-09-07: "if a bag comes back it would be able to trace to green lot
-- and then from green lot down the line back to all bags affected by that green
-- lot, correct?"
--
-- Not yet, and that was the gap. recall_trace() walked back to the green and
-- stopped; recall_trace_from_green() walked forward from a green lot. Getting
-- from one to the other meant reading a lot id off the first answer and feeding
-- it to the second by hand — the clicking-between-screens the two-hour limit
-- exists to prevent, and worse, a judgement call about which lot to widen on
-- made by whoever happens to be at the keyboard.
--
-- The widening is the recall. One customer complaint is not a recall; the
-- question is always "what else did that green touch". So recall_trace now
-- answers it in the same call:
--
--   run        the bag in front of you
--   back       its roast batches, green lots, suppliers, packaging
--   forward    who else has a bag FROM THIS RUN
--   affected   every OTHER run that shares any of those green lots, every
--              customer holding one, and the totals — the actual scope
--
-- Deliberately not capped or paginated. A recall is complete or it is not, and a
-- roastery's green lots reach tens of runs, not millions. If that ever stops
-- being true the answer is a background job, not a truncated list that looks
-- complete.

begin;

create or replace function public.recall_trace(p_lot_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_run public.pack_run;
  v_back jsonb;
  v_fwd  jsonb;
  v_pkg  jsonb;
  v_affected jsonb;
  v_allocated numeric;
  v_green text[];
begin
  select * into v_run from public.pack_run
   where lot_code = p_lot_code
     and company_id in (select auth_company_ids());
  if v_run.pack_run_id is null then
    return jsonb_build_object('found', false, 'lot_code', p_lot_code);
  end if;

  -- The green lots this bag touched. Everything downstream widens from here.
  select coalesce(array_agg(distinct c.origin_purchase_id), '{}')
    into v_green
    from public.pack_run_source s
    join public.roast_log_lot_consumption c on c.roast_log_id = s.roast_log_id
   where s.pack_run_id = v_run.pack_run_id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'roast_log_id', s.roast_log_id,
           'roast_date',   rl.roast_date,
           'roasted_by',   rs.roasted_by_name,
           'charged_lbs',  rl.charge_weight_lbs,
           'lbs_used',     s.lbs_used,
           'green', (
             select coalesce(jsonb_agg(jsonb_build_object(
                      'origin_purchase_id', cip.origin_purchase_id,
                      'origin',        cip.origin,
                      'supplier_lot',  cip.lot_id,
                      'harvest_year',  cip.harvest_year,
                      'lbs_consumed',  c.lbs_consumed,
                      'supplier',      sup.supplier,
                      'supplier_contact', sup.contact_name,
                      'supplier_email', sup.contact_email,
                      'supplier_phone', sup.contact_phone,
                      'shipment_id',   sr.shipment_id,
                      'received_on',   sr.date_received,
                      'invoice_number', sr.invoice_number
                    )), '[]'::jsonb)
               from public.roast_log_lot_consumption c
               join public.coffee_inventory_purchased cip on cip.origin_purchase_id = c.origin_purchase_id
               left join public.supplier sup on sup.supplier_id = cip.supplier_id
               left join public.shipment_received sr on sr.shipment_id = cip.shipment_id
              where c.roast_log_id = s.roast_log_id
           ),
           'green_attributed_lbs', (
             select coalesce(sum(c.lbs_consumed), 0) from public.roast_log_lot_consumption c
              where c.roast_log_id = s.roast_log_id),
           'unattributed_lbs', greatest(
             coalesce(rl.charge_weight_lbs, 0)
             - (select coalesce(sum(c.lbs_consumed), 0) from public.roast_log_lot_consumption c
                 where c.roast_log_id = s.roast_log_id), 0)
         )), '[]'::jsonb)
    into v_back
    from public.pack_run_source s
    join public.roast_log rl on rl.roast_log_id = s.roast_log_id
    left join public.roast_sessions rs on rs.session_id = rl.session_id
   where s.pack_run_id = v_run.pack_run_id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'bags', a.bags, 'order_id', o.order_id, 'order_number', o.order_number,
           'order_date', o.order_date, 'delivery_date', o.delivery_date,
           'shipped_at', o.shipped_at, 'carrier', o.carrier, 'tracking', o.tracking_number,
           'customer_id', coalesce(a.customer_id, o.customer_id),
           'customer', cu.name_company, 'email', cu.email, 'phone', cu.phone,
           'address', concat_ws(', ', nullif(cu.street,''), nullif(cu.city,''), nullif(cu.state,''), nullif(cu.zip,''))
         ) order by o.order_date), '[]'::jsonb),
         coalesce(sum(a.bags), 0)
    into v_fwd, v_allocated
    from public.pack_run_allocation a
    left join public.order_details od on od.order_detail_id = a.order_detail_id
    left join public.orders o on o.order_id = od.order_id
    left join public.customers cu on cu.customer_id = coalesce(a.customer_id, o.customer_id)
   where a.pack_run_id = v_run.pack_run_id;

  select jsonb_build_object(
           'bag',   (select jsonb_build_object('lot_code', cp.lot_code, 'item', ci.consumable_inventory_item,
                                               'supplier', sup.supplier, 'received_on', sr.date_received)
                       from public.consumable_inventory_purchased cp
                       left join public.consumable_inventory ci on ci.consumable_inventory_id = cp.consumable_inventory_item
                       left join public.shipment_received sr on sr.shipment_id = cp.shipment_id
                       left join public.supplier sup on sup.supplier_id = sr.supplier_id
                      where cp.consumable_purchase_id = v_run.bag_purchase_id),
           'label', (select jsonb_build_object('lot_code', cp.lot_code, 'item', ci.consumable_inventory_item,
                                               'supplier', sup.supplier, 'received_on', sr.date_received)
                       from public.consumable_inventory_purchased cp
                       left join public.consumable_inventory ci on ci.consumable_inventory_id = cp.consumable_inventory_item
                       left join public.shipment_received sr on sr.shipment_id = cp.shipment_id
                       left join public.supplier sup on sup.supplier_id = sr.supplier_id
                      where cp.consumable_purchase_id = v_run.label_purchase_id)
         ) into v_pkg;

  -- ── The widening: everything else that green touched ──────────────────────
  with runs as (
    select distinct pr.pack_run_id, pr.lot_code, pr.packed_on, pr.bags, pr.location,
           coalesce(pr.product_name_snapshot, p.product_name) as product,
           (pr.pack_run_id = v_run.pack_run_id) as is_this_bag
      from public.roast_log_lot_consumption c
      join public.pack_run_source s on s.roast_log_id = c.roast_log_id
      join public.pack_run pr on pr.pack_run_id = s.pack_run_id
      left join public.products p on p.product_id = pr.product_id
     where c.origin_purchase_id = any (v_green)
       and pr.company_id = v_run.company_id
       and pr.voided_at is null
  ), holders as (
    select distinct cu.customer_id, cu.name_company, cu.email, cu.phone,
           concat_ws(', ', nullif(cu.street,''), nullif(cu.city,''), nullif(cu.state,''), nullif(cu.zip,'')) as address
      from runs r
      join public.pack_run_allocation a on a.pack_run_id = r.pack_run_id
      left join public.order_details od on od.order_detail_id = a.order_detail_id
      left join public.orders o on o.order_id = od.order_id
      join public.customers cu on cu.customer_id = coalesce(a.customer_id, o.customer_id)
  )
  select jsonb_build_object(
           'green_lots_involved', coalesce(array_length(v_green, 1), 0),
           'lot_codes', (select coalesce(jsonb_agg(jsonb_build_object(
                                  'lot_code', lot_code, 'product', product, 'packed_on', packed_on,
                                  'bags', bags, 'location', location, 'is_this_bag', is_this_bag
                                ) order by packed_on desc), '[]'::jsonb) from runs),
           'runs_affected', (select count(*) from runs),
           'bags_affected', (select coalesce(sum(bags), 0) from runs),
           'customers', (select coalesce(jsonb_agg(jsonb_build_object(
                                  'customer_id', customer_id, 'customer', name_company,
                                  'email', email, 'phone', phone, 'address', address
                                ) order by name_company), '[]'::jsonb) from holders),
           'customers_affected', (select count(*) from holders)
         ) into v_affected;

  return jsonb_build_object(
    'found', true,
    'traced_at', now(),
    'run', jsonb_build_object(
      'lot_code', v_run.lot_code,
      'product', coalesce(v_run.product_name_snapshot, (select product_name from public.products where product_id = v_run.product_id)),
      'coffee_prep', v_run.coffee_prep, 'packed_on', v_run.packed_on,
      'packed_by', v_run.packed_by_name, 'location', v_run.location,
      'best_before', v_run.best_before, 'bags', v_run.bags,
      'total_lbs', v_run.total_lbs, 'voided_at', v_run.voided_at
    ),
    'reconciliation', jsonb_build_object(
      'bags_packed', v_run.bags, 'bags_allocated', v_allocated,
      'bags_unaccounted', v_run.bags - v_allocated
    ),
    'green_source', case when v_run.green_snapshot is not null then 'snapshot at pack time' else 'live ledger' end,
    'back', coalesce(v_run.green_snapshot, v_back),
    'forward', v_fwd,
    'packaging', v_pkg,
    -- The scope. One complaint is not a recall; this is.
    'affected', v_affected
  );
end;
$$;

comment on function public.recall_trace(text) is
  'A bag came back: what is in it, who else has one from the same run, and — the part that makes it a recall — every other lot code and customer its green lots reached.';

commit;
