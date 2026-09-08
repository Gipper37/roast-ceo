-- The two-hour exercise, as one question.
--
-- Costco 3.5.4 is an automatic failure and it is timed: 100% of a lot accounted
-- for within TWO HOURS, proved twice a year by the roastery and a third time by
-- the auditor on the day (3.5.5). It also names the two directions explicitly —
-- "a finished product incident AND an ingredient supplier incident" — so one
-- function is not enough. There are two here.
--
--   recall_trace(lot_code)          a bag came back. What is in it, and who else
--                                   has a bag from the same run?
--   recall_trace_from_green(lot)    a supplier told us a green lot is bad. Which
--                                   lot codes did it reach, and which customers?
--
-- Both answer in one round trip and return the whole bundle, because two hours
-- is not long and the failure mode is a person clicking through screens copying
-- numbers into a spreadsheet.
--
-- ── Honest about what is not there ──────────────────────────────────────────
-- The green attribution comes from the FROZEN snapshot on the pack run when it
-- has one, and only falls back to the live ledger when it does not — the live
-- one is a FIFO projection that replay_lot_consumption deletes and rebuilds, so
-- asking twice could otherwise give two answers. Either way the reply says
-- which source it used and reports `unattributed_lbs`, because on this data the
-- ledger is routinely short while a roastery catches up on entry (owner: that
-- is onboarding, not a bug). A trace that quietly showed less green than was
-- charged, with no note, would be the actual audit failure.
--
-- `supplier` has contact details but no street address, and orders carry
-- carrier/tracking that almost nobody fills in. Those fields are returned as
-- they are rather than promised and printed empty.

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
  v_allocated numeric;
begin
  select * into v_run from public.pack_run
   where lot_code = p_lot_code
     and company_id in (select auth_company_ids());
  if v_run.pack_run_id is null then
    return jsonb_build_object('found', false, 'lot_code', p_lot_code);
  end if;

  -- ── one step back: batches, green, supplier ───────────────────────────────
  select coalesce(jsonb_agg(jsonb_build_object(
           'roast_log_id', s.roast_log_id,
           'roast_date',   rl.roast_date,
           'roasted_by',   rs.roasted_by_name,
           'charged_lbs',  rl.charge_weight_lbs,
           'lbs_used',     s.lbs_used,
           'green', (
             select coalesce(jsonb_agg(jsonb_build_object(
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
              where c.roast_log_id = s.roast_log_id
           ),
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

  -- ── one step forward: who has a bag ───────────────────────────────────────
  select coalesce(jsonb_agg(jsonb_build_object(
           'bags',          a.bags,
           'order_id',      o.order_id,
           'order_number',  o.order_number,
           'order_date',    o.order_date,
           'delivery_date', o.delivery_date,
           'shipped_at',    o.shipped_at,
           'carrier',       o.carrier,
           'tracking',      o.tracking_number,
           'customer_id',   coalesce(a.customer_id, o.customer_id),
           'customer',      cu.name_company,
           'email',         cu.email,
           'phone',         cu.phone,
           'address',       concat_ws(', ', nullif(cu.street,''), nullif(cu.city,''), nullif(cu.state,''), nullif(cu.zip,''))
         ) order by o.order_date), '[]'::jsonb),
         coalesce(sum(a.bags), 0)
    into v_fwd, v_allocated
    from public.pack_run_allocation a
    left join public.order_details od on od.order_detail_id = a.order_detail_id
    left join public.orders o on o.order_id = od.order_id
    left join public.customers cu on cu.customer_id = coalesce(a.customer_id, o.customer_id)
   where a.pack_run_id = v_run.pack_run_id;

  -- ── the bag and the label are inputs too (5.2.8 names primary packaging) ──
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

  return jsonb_build_object(
    'found', true,
    'traced_at', now(),
    'run', jsonb_build_object(
      'lot_code',    v_run.lot_code,
      'product',     coalesce(v_run.product_name_snapshot, (select product_name from public.products where product_id = v_run.product_id)),
      'coffee_prep', v_run.coffee_prep,
      'packed_on',   v_run.packed_on,
      'packed_by',   v_run.packed_by_name,
      'location',    v_run.location,
      'best_before', v_run.best_before,
      'bags',        v_run.bags,
      'total_lbs',   v_run.total_lbs,
      'voided_at',   v_run.voided_at
    ),
    -- The number an auditor checks first: does what went out match what was made.
    'reconciliation', jsonb_build_object(
      'bags_packed',      v_run.bags,
      'bags_allocated',   v_allocated,
      'bags_unaccounted', v_run.bags - v_allocated
    ),
    'green_source', case when v_run.green_snapshot is not null then 'snapshot at pack time' else 'live ledger' end,
    'back',      coalesce(v_run.green_snapshot, v_back),
    'forward',   v_fwd,
    'packaging', v_pkg
  );
end;
$$;

comment on function public.recall_trace(text) is
  'A bag came back: what is in it, and who else has one from the same run. One round trip, because the exercise is timed at two hours.';

-- ── The other direction the audit asks for ──────────────────────────────────
create or replace function public.recall_trace_from_green(p_origin_purchase_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare v_cip public.coffee_inventory_purchased; v_runs jsonb;
begin
  select * into v_cip from public.coffee_inventory_purchased
   where origin_purchase_id = p_origin_purchase_id
     and company_id in (select auth_company_ids());
  if v_cip.origin_purchase_id is null then
    return jsonb_build_object('found', false);
  end if;

  select coalesce(jsonb_agg(distinct jsonb_build_object(
           'lot_code',  pr.lot_code,
           'packed_on', pr.packed_on,
           'bags',      pr.bags,
           'product',   coalesce(pr.product_name_snapshot, p.product_name),
           'location',  pr.location
         )), '[]'::jsonb)
    into v_runs
    from public.roast_log_lot_consumption c
    join public.pack_run_source s on s.roast_log_id = c.roast_log_id
    join public.pack_run pr on pr.pack_run_id = s.pack_run_id
    left join public.products p on p.product_id = pr.product_id
   where c.origin_purchase_id = p_origin_purchase_id;

  return jsonb_build_object(
    'found', true,
    'traced_at', now(),
    'green', jsonb_build_object(
      'origin', v_cip.origin, 'supplier_lot', v_cip.lot_id,
      'harvest_year', v_cip.harvest_year, 'received_lbs', v_cip.amount
    ),
    'reached_lot_codes', v_runs,
    -- Every customer holding a bag that touched this green, deduplicated: the
    -- list somebody actually has to ring.
    'customers', (
      select coalesce(jsonb_agg(distinct jsonb_build_object(
               'customer', cu.name_company, 'email', cu.email, 'phone', cu.phone)), '[]'::jsonb)
        from public.roast_log_lot_consumption c
        join public.pack_run_source s on s.roast_log_id = c.roast_log_id
        join public.pack_run_allocation a on a.pack_run_id = s.pack_run_id
        left join public.order_details od on od.order_detail_id = a.order_detail_id
        left join public.orders o on o.order_id = od.order_id
        left join public.customers cu on cu.customer_id = coalesce(a.customer_id, o.customer_id)
       where c.origin_purchase_id = p_origin_purchase_id
         and cu.customer_id is not null
    )
  );
end;
$$;

comment on function public.recall_trace_from_green(text) is
  'A supplier says a green lot is bad: which lot codes it reached and which customers to ring. The ingredient-supplier half of 3.5.4, which the finished-product trace does not answer.';

revoke all on function public.recall_trace(text)            from public;
revoke all on function public.recall_trace_from_green(text) from public;
grant execute on function public.recall_trace(text)            to authenticated;
grant execute on function public.recall_trace_from_green(text) to authenticated;

commit;
