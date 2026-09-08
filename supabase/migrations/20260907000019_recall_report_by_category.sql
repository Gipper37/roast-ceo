-- One recall report, grouped the way a person thinks about it.
--
-- Owner, 2026-09-07: "wouldn't a recall just spit out a report of all possibly
-- affected elements separated by their category, green coffee, product out/bag,
-- etc".
--
-- Yes, and that is not what the last two migrations produced. They returned a
-- trace: a nested walk outward from one bag, with `back`, `forward` and
-- `affected` branches that a reader has to reassemble in their head. It is the
-- right data in the shape of the query rather than the shape of the answer.
--
-- What somebody actually needs, standing in front of an auditor or on the phone
-- to a customer, is a list per category. So there is now ONE function returning
-- ONE report, in sections:
--
--   green_coffee    the lots, their suppliers, contacts, shipments
--   roast_batches   the roasts that used them, who roasted, when
--   packed_lots     every lot code affected, product, bags, where it is
--   packaging       the bag and label lots that went into those runs
--   customers       everyone holding affected product, with phone and address
--   deliveries      the orders it went out on, with dates and tracking
--   totals          the arithmetic an auditor checks first
--
-- Two doors into the same report, because 3.5.4 names both incidents: a bag came
-- back (by lot code), or a supplier says a green lot is bad (by purchase). Same
-- output either way — which door you came in should not change what a recall is.
--
-- Supersedes recall_trace() and recall_trace_from_green(), both dropped. Two
-- names for one question is how a floor gets confused at the worst moment.

begin;

drop function if exists public.recall_trace(text);
drop function if exists public.recall_trace_from_green(text);

create or replace function public.recall_report(
  p_lot_code           text default null,
  p_origin_purchase_id text default null
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
  v_trigger jsonb;
  v_report  jsonb;
begin
  if p_lot_code is null and p_origin_purchase_id is null then
    raise exception 'Give me a lot code or a green purchase to start from.'
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
  else
    select cip.company_id,
           jsonb_build_object('kind','green lot','origin', cip.origin,
             'supplier_lot', cip.lot_id, 'harvest_year', cip.harvest_year,
             'received_lbs', cip.amount, 'supplier', sup.supplier)
      into v_company, v_trigger
      from public.coffee_inventory_purchased cip
      left join public.supplier sup on sup.supplier_id = cip.supplier_id
     where cip.origin_purchase_id = p_origin_purchase_id
       and cip.company_id in (select auth_company_ids());
    if v_company is null then
      return jsonb_build_object('found', false, 'looked_for', p_origin_purchase_id);
    end if;
    v_green := array[p_origin_purchase_id];
  end if;

  -- Everything below is scoped by the green lots, whichever door was used.
  with roasts as (
    select distinct rl.roast_log_id, rl.roast_date, rl.charge_weight_lbs, rl.session_id
      from public.roast_log_lot_consumption c
      join public.roast_log rl on rl.roast_log_id = c.roast_log_id
     where c.origin_purchase_id = any (v_green) and rl.company_id = v_company
  ), runs as (
    select distinct pr.pack_run_id, pr.lot_code, pr.packed_on, pr.bags, pr.location,
           pr.best_before, pr.coffee_prep, pr.bag_purchase_id, pr.label_purchase_id,
           coalesce(pr.product_name_snapshot, p.product_name) as product,
           (p_lot_code is not null and pr.lot_code = p_lot_code) as is_the_trigger
      from roasts r
      join public.pack_run_source s on s.roast_log_id = r.roast_log_id
      join public.pack_run pr on pr.pack_run_id = s.pack_run_id
      left join public.products p on p.product_id = pr.product_id
     where pr.voided_at is null
  ), allocs as (
    select a.*, o.order_id, o.order_number, o.order_date, o.delivery_date,
           o.shipped_at, o.carrier, o.tracking_number,
           coalesce(a.customer_id, o.customer_id) as cust
      from runs rn
      join public.pack_run_allocation a on a.pack_run_id = rn.pack_run_id
      left join public.order_details od on od.order_detail_id = a.order_detail_id
      left join public.orders o on o.order_id = od.order_id
  )
  select jsonb_build_object(
    'found', true,
    'run_at', now(),
    'triggered_by', v_trigger,

    'green_coffee', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'origin', cip.origin, 'supplier_lot', cip.lot_id,
               'harvest_year', cip.harvest_year, 'received_lbs', cip.amount,
               'supplier', sup.supplier, 'contact', sup.contact_name,
               'email', sup.contact_email, 'phone', sup.contact_phone,
               'received_on', sr.date_received, 'invoice_number', sr.invoice_number
             ) order by cip.origin), '[]'::jsonb)
        from public.coffee_inventory_purchased cip
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
               -- Reported, never hidden: the ledger is routinely short while a
               -- roastery catches up on entry, and a recall that quietly showed
               -- less green than was charged would be the real audit failure.
               'unattributed_lbs', greatest(coalesce(r.charge_weight_lbs,0)
                 - (select coalesce(sum(c2.lbs_consumed),0) from public.roast_log_lot_consumption c2
                     where c2.roast_log_id = r.roast_log_id), 0)
             ) order by r.roast_date desc), '[]'::jsonb)
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
               'supplier', sup.supplier, 'received_on', sr.date_received)), '[]'::jsonb)
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
             ) order by a.order_date desc), '[]'::jsonb)
        from allocs a left join public.customers cu on cu.customer_id = a.cust),

    'totals', jsonb_build_object(
      'green_lots',    coalesce(array_length(v_green,1), 0),
      'roast_batches', (select count(*) from roasts),
      'packed_lots',   (select count(*) from runs),
      'bags_packed',   (select coalesce(sum(bags),0) from runs),
      'bags_shipped',  (select coalesce(sum(bags),0) from allocs),
      -- What was made but never allocated to anybody: still on your shelf, or
      -- unrecorded. Either way it is the first thing an auditor asks about.
      'bags_unaccounted', (select coalesce(sum(bags),0) from runs)
                          - (select coalesce(sum(bags),0) from allocs),
      'customers',     (select count(distinct cust) from allocs where cust is not null))
  ) into v_report;

  return v_report;
end;
$$;

comment on function public.recall_report(text, text) is
  'One recall report, in sections a person can read: green coffee, roast batches, packed lots, packaging, customers, deliveries, totals. Two doors — a returned bag or a bad green lot — and the same report either way.';

revoke all on function public.recall_report(text, text) from public;
grant execute on function public.recall_report(text, text) to authenticated;

commit;
