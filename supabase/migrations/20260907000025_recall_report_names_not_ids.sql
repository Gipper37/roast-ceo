-- The report has to name things the way a person says them out loud.
--
-- Found by using it: the green coffee section printed `demo-org-13`. That column
-- is `coffee_inventory_purchased.origin`, which is a foreign key to
-- `coffee_inventory.origin_id` — the key, not the name. Every recall report and
-- every frozen scope produced so far names its green lots by internal id.
--
-- It reads as cosmetic and is not. This report is what somebody reads down a
-- phone line to a supplier at seven in the morning, and hands to an auditor
-- afterwards. An identifier nobody outside the database recognises is the same
-- as no answer. The name is resolved through the join and the raw key is kept as
-- a fallback, so a purchase whose origin row was deleted still says something
-- rather than nothing.

begin;

create or replace function public.recall_report(
  p_lot_code           text default null,
  p_origin_purchase_id text default null,
  p_packaging_lot_code text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_company text;
  v_green   text[];
  v_roasts  text[];
  v_runs    text[];
  v_trigger jsonb;
  v_report  jsonb;
  v_doors   int;
begin
  v_doors := (p_lot_code is not null)::int
           + (p_origin_purchase_id is not null)::int
           + (p_packaging_lot_code is not null)::int;
  if v_doors <> 1 then
    raise exception 'Give exactly one starting point: a bag lot code, a green purchase, or a packaging lot.'
      using errcode = 'invalid_parameter_value';
  end if;

  -- ── Door 1: a bag came back ───────────────────────────────────────────────
  if p_lot_code is not null then
    select pr.company_id,
           jsonb_build_object('kind','packed bag','lot_code',pr.lot_code,
             'product', coalesce(pr.product_name_snapshot, p.product_name),
             'packed_on', pr.packed_on, 'packed_by', pr.packed_by_name,
             'location', pr.location, 'best_before', pr.best_before)
      into v_company, v_trigger
      from public.pack_run pr
      left join public.products p on p.product_id = pr.product_id
     where pr.lot_code = p_lot_code
       and pr.company_id in (select auth_company_ids());
    if v_company is null then
      return jsonb_build_object('found', false, 'looked_for', p_lot_code);
    end if;

    select coalesce(array_agg(distinct c.origin_purchase_id), '{}')
      into v_green
      from public.pack_run pr
      join public.pack_run_source s on s.pack_run_id = pr.pack_run_id
      join public.roast_log_lot_consumption c on c.roast_log_id = s.roast_log_id
     where pr.lot_code = p_lot_code and pr.company_id = v_company;

  -- ── Door 2: a supplier says a green lot is bad ────────────────────────────
  elsif p_origin_purchase_id is not null then
    select cip.company_id,
           jsonb_build_object('kind','green lot',
             -- The NAME, not the key. See the header.
             'origin', coalesce(ci.origin, cip.origin),
             'supplier_lot', cip.lot_id, 'harvest_year', cip.harvest_year,
             'received_lbs', cip.amount, 'supplier', sup.supplier)
      into v_company, v_trigger
      from public.coffee_inventory_purchased cip
      left join public.coffee_inventory ci on ci.origin_id = cip.origin
      left join public.supplier sup on sup.supplier_id = cip.supplier_id
     where cip.origin_purchase_id = p_origin_purchase_id
       and cip.company_id in (select auth_company_ids());
    if v_company is null then
      return jsonb_build_object('found', false, 'looked_for', p_origin_purchase_id);
    end if;
    v_green := array[p_origin_purchase_id];

  -- ── Door 3: a run of bags or labels is bad ────────────────────────────────
  else
    select cp.company_id,
           jsonb_build_object('kind','packaging lot','lot_code', cp.lot_code,
             'item', ci.consumable_inventory_item, 'supplier', sup.supplier,
             'received_on', sr.date_received, 'quantity', cp.amount)
      into v_company, v_trigger
      from public.consumable_inventory_purchased cp
      left join public.consumable_inventory ci on ci.consumable_inventory_id = cp.consumable_inventory_item
      left join public.shipment_received sr on sr.shipment_id = cp.shipment_id
      left join public.supplier sup on sup.supplier_id = sr.supplier_id
     where cp.lot_code = p_packaging_lot_code
       and cp.company_id in (select auth_company_ids())
     limit 1;
    if v_company is null then
      return jsonb_build_object('found', false, 'looked_for', p_packaging_lot_code);
    end if;

    select coalesce(array_agg(distinct pr.pack_run_id), '{}')
      into v_runs
      from public.pack_run pr
      join public.consumable_inventory_purchased cp
        on cp.consumable_purchase_id in (pr.bag_purchase_id, pr.label_purchase_id)
     where cp.lot_code = p_packaging_lot_code
       and cp.company_id = v_company
       and pr.company_id = v_company
       and pr.voided_at is null;
  end if;

  -- ── Resolve the other two arrays, whichever end we started from ───────────
  if v_runs is null then
    select coalesce(array_agg(distinct c.roast_log_id), '{}')
      into v_roasts
      from public.roast_log_lot_consumption c
      join public.roast_log rl on rl.roast_log_id = c.roast_log_id
     where c.origin_purchase_id = any (v_green) and rl.company_id = v_company;

    select coalesce(array_agg(distinct pr.pack_run_id), '{}')
      into v_runs
      from public.pack_run_source s
      join public.pack_run pr on pr.pack_run_id = s.pack_run_id
     where s.roast_log_id = any (v_roasts)
       and pr.company_id = v_company
       and pr.voided_at is null;

    if p_lot_code is not null then
      select coalesce(array_agg(distinct r), '{}') into v_runs
        from unnest(v_runs || array(
          select pr.pack_run_id from public.pack_run pr
           where pr.lot_code = p_lot_code and pr.company_id = v_company
             and pr.voided_at is null)) r;
    end if;
  else
    select coalesce(array_agg(distinct s.roast_log_id), '{}')
      into v_roasts
      from public.pack_run_source s
     where s.pack_run_id = any (v_runs);

    select coalesce(array_agg(distinct c.origin_purchase_id), '{}')
      into v_green
      from public.roast_log_lot_consumption c
     where c.roast_log_id = any (v_roasts);
  end if;

  with roasts as (
    select rl.roast_log_id, rl.roast_date, rl.charge_weight_lbs, rl.session_id
      from public.roast_log rl
     where rl.roast_log_id = any (v_roasts)
  ), runs as (
    select pr.pack_run_id, pr.lot_code, pr.packed_on, pr.bags, pr.location,
           pr.best_before, pr.coffee_prep, pr.bag_purchase_id, pr.label_purchase_id,
           coalesce(pr.product_name_snapshot, p.product_name) as product,
           (p_lot_code is not null and pr.lot_code = p_lot_code) as is_the_trigger
      from public.pack_run pr
      left join public.products p on p.product_id = pr.product_id
     where pr.pack_run_id = any (v_runs)
  ), allocs as (
    select a.*, o.order_id, o.order_number, o.order_date, o.delivery_date,
           o.shipped_at, o.carrier, o.tracking_number,
           coalesce(a.customer_id, o.customer_id) as cust
      from public.pack_run_allocation a
      left join public.order_details od on od.order_detail_id = a.order_detail_id
      left join public.orders o on o.order_id = od.order_id
     where a.pack_run_id = any (v_runs)
  )
  select jsonb_build_object(
    'found', true,
    'run_at', now(),
    'triggered_by', v_trigger,

    'green_coffee', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'origin', coalesce(ci.origin, cip.origin),
               'supplier_lot', cip.lot_id,
               'harvest_year', cip.harvest_year, 'received_lbs', cip.amount,
               'supplier', sup.supplier, 'contact', sup.contact_name,
               'email', sup.contact_email, 'phone', sup.contact_phone,
               'received_on', sr.date_received, 'invoice_number', sr.invoice_number
             ) order by coalesce(ci.origin, cip.origin)), '[]'::jsonb)
        from public.coffee_inventory_purchased cip
        left join public.coffee_inventory ci on ci.origin_id = cip.origin
        left join public.supplier sup on sup.supplier_id = cip.supplier_id
        left join public.shipment_received sr on sr.shipment_id = cip.shipment_id
       where cip.origin_purchase_id = any (v_green)),

    'roast_batches', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'roast_log_id', r.roast_log_id, 'roast_date', r.roast_date,
               'charged_lbs', r.charge_weight_lbs,
               'roasted_by', rs.roasted_by_name,
               'green_attributed_lbs', (select coalesce(sum(c2.lbs_consumed),0)
                                          from public.roast_log_lot_consumption c2
                                         where c2.roast_log_id = r.roast_log_id),
               'unattributed_lbs', greatest(coalesce(r.charge_weight_lbs,0)
                 - (select coalesce(sum(c2.lbs_consumed),0) from public.roast_log_lot_consumption c2
                     where c2.roast_log_id = r.roast_log_id), 0)
             ) order by r.roast_date desc nulls last), '[]'::jsonb)
        from roasts r left join public.roast_sessions rs on rs.session_id = r.session_id),

    'packed_lots', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'lot_code', lot_code, 'product', product, 'coffee_prep', coffee_prep,
               'packed_on', packed_on, 'bags', bags, 'location', location,
               'best_before', best_before, 'is_the_trigger', is_the_trigger
             ) order by packed_on desc), '[]'::jsonb) from runs),

    'packaging', (
      select coalesce(jsonb_agg(distinct jsonb_build_object(
               'lot_code', cp.lot_code, 'item', ci.consumable_inventory_item,
               'supplier', sup.supplier, 'received_on', sr.date_received,
               'is_the_trigger', p_packaging_lot_code is not null
                                 and cp.lot_code = p_packaging_lot_code)), '[]'::jsonb)
        from runs rn
        join public.consumable_inventory_purchased cp
          on cp.consumable_purchase_id in (rn.bag_purchase_id, rn.label_purchase_id)
        left join public.consumable_inventory ci on ci.consumable_inventory_id = cp.consumable_inventory_item
        left join public.shipment_received sr on sr.shipment_id = cp.shipment_id
        left join public.supplier sup on sup.supplier_id = sr.supplier_id),

    'customers', (
      select coalesce(jsonb_agg(x order by x->>'customer'), '[]'::jsonb) from (
        select distinct jsonb_build_object(
                 'customer', cu.name_company, 'email', cu.email, 'phone', cu.phone,
                 'address', concat_ws(', ', nullif(cu.street,''), nullif(cu.city,''),
                                            nullif(cu.state,''), nullif(cu.zip,''))) as x
          from allocs a join public.customers cu on cu.customer_id = a.cust) c),

    'deliveries', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'order_number', a.order_number, 'order_date', a.order_date,
               'delivery_date', a.delivery_date, 'shipped_at', a.shipped_at,
               'carrier', a.carrier, 'tracking', a.tracking_number,
               'customer', cu.name_company, 'bags', a.bags
             ) order by a.order_date desc nulls last), '[]'::jsonb)
        from allocs a left join public.customers cu on cu.customer_id = a.cust),

    'totals', jsonb_build_object(
      'green_lots',    coalesce(array_length(v_green,1), 0),
      'roast_batches', (select count(*) from roasts),
      'packed_lots',   (select count(*) from runs),
      'bags_packed',   (select coalesce(sum(bags),0) from runs),
      'bags_shipped',  (select coalesce(sum(bags),0) from allocs),
      'bags_unaccounted', (select coalesce(sum(bags),0) from runs)
                          - (select coalesce(sum(bags),0) from allocs),
      'customers',     (select count(distinct cust) from allocs where cust is not null))
  ) into v_report;

  return v_report;
end;
$$;

commit;
