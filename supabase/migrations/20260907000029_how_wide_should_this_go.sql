-- How wide should a recall be drawn? It depends where the problem got in.
--
-- Owner, 2026-09-07: *"in your email you used an example of plastic in the
-- coffee. that is the common case outside a green coffee recall. so in that case
-- the recall would just be linked to the roast or packing session… we wouldn't
-- need to recall all green from a green lot in that case."*
--
-- He is right and the report was wrong. Door one always widened to every bag
-- sharing the green, which is correct for a hazard that came IN the coffee —
-- mould, OTA, a supplier's problem — and badly over-broad for the far more
-- common one. A plastic fragment enters at the roaster or the bagger. The green
-- is fine. So is every other bag made from it.
--
-- Recalling four months of production when the answer is one afternoon's bagging
-- is not caution, it is a different kind of failure: it costs a roastery its
-- customers and it teaches an auditor that the trace cannot discriminate.
--
-- So the scope is now asked rather than assumed, narrow to wide, and each one
-- matches a way a problem actually gets in:
--
--   lot    just this bagging run          a one-off — a single bag, a seal
--   roast  everything off the same roasts  something in the roaster: metal, smoke
--   day    everything bagged that day      the bagger or the line shed something
--   green  everything sharing the green    the coffee itself is the problem
--
-- The chosen scope is recorded on the recall and printed in the report, because
-- "why did you only recall these twelve lots" is a question with a good answer
-- and it needs to be on the record at the time, not reconstructed later.

begin;

alter table public.recall
  add column if not exists trigger_scope text not null default 'green';

alter table public.recall drop constraint if exists recall_trigger_scope_check;
alter table public.recall add constraint recall_trigger_scope_check
  check (trigger_scope in ('lot','roast','day','green'));

comment on column public.recall.trigger_scope is
  'How wide the recall was drawn from a returned bag: lot | roast | day | green. Recorded because "why did you only recall these twelve lots" needs an answer given at the time.';

create or replace function public.recall_report(
  p_lot_code           text default null,
  p_origin_purchase_id text default null,
  p_packaging_lot_code text default null,
  p_scope              text default 'green'
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
  v_scope   text := coalesce(p_scope, 'green');
  v_day     date;
  v_scope_label text;
begin
  v_doors := (p_lot_code is not null)::int
           + (p_origin_purchase_id is not null)::int
           + (p_packaging_lot_code is not null)::int;
  if v_doors <> 1 then
    raise exception 'Give exactly one starting point: a bag lot code, a green purchase, or a packaging lot.'
      using errcode = 'invalid_parameter_value';
  end if;
  if v_scope not in ('lot','roast','day','green') then
    raise exception 'Unknown scope.' using errcode = 'invalid_parameter_value';
  end if;

  -- ── Door 1: a bag came back ───────────────────────────────────────────────
  if p_lot_code is not null then
    select pr.company_id, pr.packed_on,
           jsonb_build_object('kind','packed bag','lot_code',pr.lot_code,
             'product', coalesce(pr.product_name_snapshot, p.product_name),
             'packed_on', pr.packed_on, 'packed_by', pr.packed_by_name,
             'location', pr.location, 'best_before', pr.best_before)
      into v_company, v_day, v_trigger
      from public.pack_run pr
      left join public.products p on p.product_id = pr.product_id
     where pr.lot_code = p_lot_code
       and pr.company_id in (select auth_company_ids());
    if v_company is null then
      return jsonb_build_object('found', false, 'looked_for', p_lot_code);
    end if;

    -- The roasts that fed the returned bag. Every scope but 'green' is measured
    -- from here rather than from the green lot.
    select coalesce(array_agg(distinct s.roast_log_id), '{}')
      into v_roasts
      from public.pack_run pr
      join public.pack_run_source s on s.pack_run_id = pr.pack_run_id
     where pr.lot_code = p_lot_code and pr.company_id = v_company;

    if v_scope = 'lot' then
      v_scope_label := 'This bagging run only';
      select coalesce(array_agg(pr.pack_run_id), '{}') into v_runs
        from public.pack_run pr
       where pr.lot_code = p_lot_code and pr.company_id = v_company and pr.voided_at is null;

    elsif v_scope = 'roast' then
      v_scope_label := 'Everything off the same roast batches';
      select coalesce(array_agg(distinct pr.pack_run_id), '{}') into v_runs
        from public.pack_run_source s
        join public.pack_run pr on pr.pack_run_id = s.pack_run_id
       where s.roast_log_id = any (v_roasts)
         and pr.company_id = v_company and pr.voided_at is null;

    elsif v_scope = 'day' then
      -- The bagger or the line shed something: everything through it that day,
      -- whatever coffee it was.
      v_scope_label := 'Everything bagged that day';
      select coalesce(array_agg(pr.pack_run_id), '{}') into v_runs
        from public.pack_run pr
       where pr.company_id = v_company and pr.packed_on = v_day and pr.voided_at is null;
      select coalesce(array_agg(distinct s.roast_log_id), '{}') into v_roasts
        from public.pack_run_source s where s.pack_run_id = any (v_runs);

    else
      v_scope_label := 'Everything sharing the green';
      select coalesce(array_agg(distinct c.origin_purchase_id), '{}')
        into v_green
        from public.roast_log_lot_consumption c
       where c.roast_log_id = any (v_roasts);
    end if;

  -- ── Door 2: a supplier says a green lot is bad ────────────────────────────
  elsif p_origin_purchase_id is not null then
    v_scope := 'green';
    v_scope_label := 'Everything made from this green lot';
    select cip.company_id,
           jsonb_build_object('kind','green lot',
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
    v_roasts := null;

  -- ── Door 3: a run of bags or labels is bad ────────────────────────────────
  else
    v_scope := 'lot';
    v_scope_label := 'Every run that used this packaging';
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

  -- ── Fill in whichever arrays the chosen scope did not set ─────────────────
  if v_runs is null then
    -- Green-scoped: green → roasts → runs. Roasts come from the green rather
    -- than from the runs on purpose — coffee roasted from a bad lot and not yet
    -- bagged is still affected, and it is the easiest batch to actually stop.
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
       and pr.company_id = v_company and pr.voided_at is null;

    -- The bag that came back is affected whatever the ledger says.
    if p_lot_code is not null then
      select coalesce(array_agg(distinct r), '{}') into v_runs
        from unnest(v_runs || array(
          select pr.pack_run_id from public.pack_run pr
           where pr.lot_code = p_lot_code and pr.company_id = v_company
             and pr.voided_at is null)) r;
    end if;
  end if;

  if v_roasts is null then
    select coalesce(array_agg(distinct s.roast_log_id), '{}')
      into v_roasts
      from public.pack_run_source s where s.pack_run_id = any (v_runs);
  end if;

  if v_green is null then
    -- Context, not accusation: on a narrow scope this says what coffee is in the
    -- affected bags, not that the coffee is suspect.
    select coalesce(array_agg(distinct c.origin_purchase_id), '{}')
      into v_green
      from public.roast_log_lot_consumption c where c.roast_log_id = any (v_roasts);
  end if;

  with roasts as (
    select rl.roast_log_id, rl.roast_date, rl.charge_weight_lbs, rl.session_id
      from public.roast_log rl where rl.roast_log_id = any (v_roasts)
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
    'scope', v_scope,
    'scope_label', v_scope_label,
    'green_is_suspect', v_scope = 'green',

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

comment on function public.recall_report(text, text, text, text) is
  'One recall report, in sections a person can read. Three doors, and — from a returned bag — four widths, because where the problem got in decides how far it reached. A plastic fragment came from the roaster or the bagger; the green is fine.';

-- ── The scope is chosen at step two and frozen at finalise ──────────────────
drop function if exists public.set_recall_trigger(text, text, text, text, boolean);

create or replace function public.set_recall_trigger(
  p_recall_id          text,
  p_lot_code           text default null,
  p_origin_purchase_id text default null,
  p_packaging_lot_code text default null,
  p_system_picked      boolean default false,
  p_scope              text default 'green'
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_company text; v_status text; v_doors int;
begin
  select company_id, status into v_company, v_status
    from public.recall where recall_id = p_recall_id and company_id in (select auth_company_ids());
  if v_company is null then raise exception 'No such recall.' using errcode = 'no_data_found'; end if;
  if v_status <> 'draft' then
    raise exception 'That recall is already finalised. Its scope cannot be changed.'
      using errcode = 'invalid_parameter_value';
  end if;

  v_doors := (p_lot_code is not null)::int
           + (p_origin_purchase_id is not null)::int
           + (p_packaging_lot_code is not null)::int;
  if v_doors <> 1 then
    raise exception 'Give exactly one starting point: a bag lot code, a green purchase, or a packaging lot.'
      using errcode = 'invalid_parameter_value';
  end if;
  if coalesce(p_scope, 'green') not in ('lot','roast','day','green') then
    raise exception 'Unknown scope.' using errcode = 'invalid_parameter_value';
  end if;

  update public.recall
     set trigger_kind = case when p_lot_code is not null then 'packed_lot'
                             when p_origin_purchase_id is not null then 'green_lot'
                             else 'packaging_lot' end,
         trigger_ref  = coalesce(p_lot_code, p_origin_purchase_id, p_packaging_lot_code),
         trigger_scope = case when p_lot_code is not null then coalesce(p_scope, 'green')
                              when p_origin_purchase_id is not null then 'green'
                              else 'lot' end,
         lot_selection = case when p_system_picked then 'system' else 'user' end,
         updated_at = now()
   where recall_id = p_recall_id;
end;
$$;

create or replace function public.finalise_recall(p_recall_id text, p_variance_note text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_rec public.recall;
  v_report jsonb;
  v_packed numeric; v_shipped numeric; v_unacc numeric; v_pct numeric;
  v_actor record; v_elapsed int; v_needed text;
begin
  select * into v_rec from public.recall
   where recall_id = p_recall_id and company_id in (select auth_company_ids());
  if v_rec.recall_id is null then raise exception 'No such recall.' using errcode = 'no_data_found'; end if;
  if v_rec.status <> 'draft' then
    raise exception 'That recall is already finalised.' using errcode = 'invalid_parameter_value';
  end if;
  if v_rec.trigger_ref is null then
    raise exception 'Choose what set this off before finalising it.' using errcode = 'invalid_parameter_value';
  end if;

  v_needed := case when v_rec.kind = 'exercise' then 'recall.exercise' else 'recall.manage' end;
  if not public.auth_has_permission(v_needed, v_rec.company_id) then
    raise exception 'You do not have permission to finalise this.' using errcode = 'insufficient_privilege';
  end if;

  v_report := public.recall_report(
    case when v_rec.trigger_kind = 'packed_lot'    then v_rec.trigger_ref end,
    case when v_rec.trigger_kind = 'green_lot'     then v_rec.trigger_ref end,
    case when v_rec.trigger_kind = 'packaging_lot' then v_rec.trigger_ref end,
    v_rec.trigger_scope);
  if not coalesce((v_report->>'found')::boolean, false) then
    raise exception 'Nothing found for that starting point.' using errcode = 'no_data_found';
  end if;

  v_packed  := coalesce((v_report#>>'{totals,bags_packed}')::numeric, 0);
  v_shipped := coalesce((v_report#>>'{totals,bags_shipped}')::numeric, 0);
  v_unacc   := coalesce((v_report#>>'{totals,bags_unaccounted}')::numeric, 0);
  v_pct := case when v_packed > 0 then round(((v_packed - v_unacc) / v_packed) * 100, 1) else null end;

  if v_pct is not null and v_pct < 100 and coalesce(trim(p_variance_note), '') = '' then
    raise exception 'Only % percent of the coffee is accounted for. Write one line saying why before finalising — it prints beside the number.', v_pct
      using errcode = 'invalid_parameter_value';
  end if;

  v_elapsed := greatest(round(extract(epoch from (now() - v_rec.initiated_at)) / 60)::int, 0);
  select * into v_actor from public.actor_at();

  update public.recall
     set report = v_report, status = 'finalised', finalised_at = now(),
         finalised_by_team_member = v_actor.team_member_id,
         finalised_by_name = v_actor.actor_name,
         completed_at = now(), elapsed_minutes = v_elapsed,
         bags_accounted = v_packed - v_unacc, accounted_pct = v_pct,
         variance_note = nullif(trim(p_variance_note), ''), updated_at = now()
   where recall_id = p_recall_id;

  insert into public.recall_notice (recall_id, customer_id, customer_name, email, phone, lot_codes, reply_token)
  select p_recall_id, cu.customer_id, c->>'customer',
         nullif(c->>'email',''), nullif(c->>'phone',''),
         (select array_agg(distinct l->>'lot_code') from jsonb_array_elements(v_report->'packed_lots') l),
         encode(extensions.gen_random_bytes(18), 'hex')
    from jsonb_array_elements(v_report->'customers') c
    left join public.customers cu on cu.company_id = v_rec.company_id and cu.name_company = c->>'customer';

  return jsonb_build_object(
    'recall_id', p_recall_id, 'reference_no', v_rec.reference_no,
    'elapsed_minutes', v_elapsed, 'within_two_hours', v_elapsed <= 120,
    'accounted_pct', v_pct, 'bags_packed', v_packed, 'bags_shipped', v_shipped,
    'bags_unaccounted', v_unacc,
    'customers', (select count(*) from public.recall_notice where recall_id = p_recall_id),
    'without_email', (select count(*) from public.recall_notice where recall_id = p_recall_id and nullif(email,'') is null));
end;
$$;

drop function if exists public.recall_report(text, text, text);

revoke all on function public.recall_report(text, text, text, text) from public;
revoke all on function public.set_recall_trigger(text, text, text, text, boolean, text) from public;
grant execute on function public.recall_report(text, text, text, text) to authenticated;
grant execute on function public.set_recall_trigger(text, text, text, text, boolean, text) to authenticated;

commit;
