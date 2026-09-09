-- Three ways the bagging chain could be broken, closed.
--
-- All three are mine, from 20260908000007, and all three matter because
-- pack_run_source and pack_run_allocation ARE the traceability chain — what a
-- recall walks and what a Costco audit reads back.
--
-- ── 1. TWO PACKERS COULD DRAW THE SAME COFFEE ───────────────────────────────
-- close_pack_run read its run with a bare `select * into v_run`, then called
-- pack_draw_plan, then inserted pack_run_source. Two overlapping transactions
-- each compute remaining_lbs from committed rows only, both take the same
-- batch, and the shelf goes negative on commit — silently, because
-- pack_draw_plan filters `remaining_lbs > 0.01` and an over-drawn batch simply
-- disappears from later draws.
--
-- The codebase already knew: allocate_line_from_stock takes `for update of pr`
-- (20260907000027:108) under the comment "so two packers working the same
-- product cannot both draw the last bags of a lot." That lock was applied one
-- layer down, at bag->order, and skipped at green->bag. Which is the layer the
-- whole session model was built for — several packers, several benches.
--
-- Locking the pack_run row alone would NOT fix it: the contention is between
-- two DIFFERENT runs reaching for one batch. So the draw is serialised on the
-- coffee itself with a transaction advisory lock on (company, recipe). Two
-- closes on the same recipe queue; closes on different coffees never touch.
--
-- ── 2. THE OVERRIDE VALIDATED NOTHING ───────────────────────────────────────
--     if p_sources is not null ... then
--       v_draw := p_sources;
--       v_plan := jsonb_build_object('basis','named','shortfall',0);
-- Straight through. No company check, no existence check, no quantity, and a
-- shortfall hardcoded to zero — then inserted into pack_run_source under
-- SECURITY DEFINER. Any pack.run holder could name any roast_log_id and forge
-- the identity chain the module exists to make truthful. The bin card would
-- make this the PRIMARY path, so it closes before that ships.
--
-- What it does NOT do is second-guess the packer. An off-recipe batch is still
-- accepted — the owner was explicit that naming the batch yourself is the most
-- accurate mode, and refusing it would push people back to bagging untracked.
-- It checks OWNERSHIP and ARITHMETIC, not judgement.
--
-- ── 3. A BATCH COULD APPEAR TWICE ON ONE RUN ────────────────────────────────
-- pack_run_source had two plain indexes and no unique key, so one roast could
-- land twice on the same run and the recall report would have to add them up
-- itself. Zero duplicates exist today; the constraint keeps it that way.
--
-- Also here: the two consumers of pack_run_allocation that 20260908000013 owed.

begin;

-- ── pack_run_source: one row per batch per run ──────────────────────────────
create unique index if not exists uq_pack_run_source_run_roast
  on public.pack_run_source (pack_run_id, roast_log_id);

-- ── allocate_line_from_stock must ignore released allocations ───────────────
-- Its "already drawn" guard was `exists (select 1 from pack_run_allocation
-- where order_detail_id = ...)` with no released filter, so a line whose bags
-- were given back and then re-packed was refused as a double-draw. This is the
-- consumer 20260908000013 deferred.
create or replace function public.allocate_line_from_stock(p_order_detail_id text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_line   record;
  v_need   numeric;
  v_taken  numeric := 0;
  v_used   jsonb := '[]'::jsonb;
  r        record;
begin
  select od.order_detail_id, od.product_id, od.company_id, od.facility_id,
         od.customer_id, od.quantity
    into v_line
    from public.order_details od
   where od.order_detail_id = p_order_detail_id
     and od.company_id in (select auth_company_ids());
  if v_line.order_detail_id is null then
    return jsonb_build_object('allocated', 0, 'short', 0, 'reason', 'not found');
  end if;

  -- Already drawn (a re-pack, a double click): leave it alone rather than
  -- double-counting the same bags out of stock. RELEASED rows do not count —
  -- their bags went back on the shelf and the line may legitimately draw again.
  if exists (select 1 from public.pack_run_allocation
              where order_detail_id = p_order_detail_id
                and released_at is null) then
    return jsonb_build_object('allocated', 0, 'short', 0, 'reason', 'already allocated');
  end if;

  v_need := coalesce(v_line.quantity, 0);
  if v_need <= 0 then
    return jsonb_build_object('allocated', 0, 'short', 0, 'reason', 'nothing to draw');
  end if;

  -- Oldest lot first, and locked, so two packers working the same product
  -- cannot both draw the last bags of a lot.
  for r in
    select pr.pack_run_id, pr.bags_remaining
      from public.pack_run_remaining pr
      join public.pack_run p on p.pack_run_id = pr.pack_run_id
     where pr.product_id = v_line.product_id
       and pr.company_id = v_line.company_id
       and pr.bags_remaining > 0
     order by pr.packed_on asc, pr.pack_run_id asc
     for update of p
  loop
    exit when v_need <= 0;
    declare v_take numeric := least(r.bags_remaining, v_need);
    begin
      insert into public.pack_run_allocation (pack_run_id, order_detail_id, customer_id, bags)
      values (r.pack_run_id, p_order_detail_id, v_line.customer_id, v_take);
      v_used  := v_used || jsonb_build_object('pack_run_id', r.pack_run_id, 'bags', v_take);
      v_need  := v_need - v_take;
      v_taken := v_taken + v_take;
    end;
  end loop;

  -- Never fails the pack: a shortfall is reported, not raised.
  return jsonb_build_object('allocated', v_taken, 'short', greatest(v_need, 0), 'lots', v_used);
end;
$$;

revoke all on function public.allocate_line_from_stock(text) from public;
grant execute on function public.allocate_line_from_stock(text) to authenticated;

CREATE OR REPLACE FUNCTION public.recall_report(p_lot_code text DEFAULT NULL::text, p_origin_purchase_id text DEFAULT NULL::text, p_packaging_lot_code text DEFAULT NULL::text, p_scope text DEFAULT 'green'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
               'customer', cu.name_company, 'bags', a.bags,
               -- Kept and FLAGGED, never filtered out. A released allocation
               -- can be an order that was delivered and then reopened for an
               -- edit: the customer HAS the coffee. Missing a consignee is
               -- the failure a recall exists to prevent.
               'released', (a.released_at is not null),
               'released_reason', a.release_reason
             ) order by a.order_date desc nulls last), '[]'::jsonb)
        from allocs a left join public.customers cu on cu.customer_id = a.cust),

    'totals', jsonb_build_object(
      'green_lots',    coalesce(array_length(v_green,1), 0),
      'roast_batches', (select count(*) from roasts),
      'packed_lots',   (select count(*) from runs),
      'bags_packed',   (select coalesce(sum(bags),0) from runs),
      'bags_shipped',  (select coalesce(sum(bags),0) from allocs where released_at is null),
      'bags_released', (select coalesce(sum(bags),0) from allocs where released_at is not null),
      'bags_unaccounted', (select coalesce(sum(bags),0) from runs)
                          - (select coalesce(sum(bags),0) from allocs where released_at is null),
      'customers',     (select count(distinct cust) from allocs where cust is not null))
  ) into v_report;

  return v_report;
end;
$function$;

-- ── close_pack_run: serialised, and the override checked ────────────────────
create or replace function public.close_pack_run(
  p_pack_run_id     text,
  p_bags            numeric,
  p_location        text    default null,
  p_bag_purchase_id text    default null,
  p_label_purchase_id text  default null,
  p_notes           text    default null,
  p_best_before     date    default null,
  p_allocations     jsonb   default '[]'::jsonb,
  p_sources         jsonb   default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_run         record;
  v_recipe      text;
  v_total       numeric;
  v_plan        jsonb;
  v_draw        jsonb;
  v_alloc_total numeric;
  v_snapshot    jsonb;
  v_actor       record;
  v_named_lbs   numeric;
  v_bad         int;
begin
  -- FOR UPDATE: two clicks on Record it cannot both pass the closed_at check.
  select * into v_run from public.pack_run where pack_run_id = p_pack_run_id for update;
  if v_run.pack_run_id is null or v_run.company_id not in (select auth_company_ids()) then
    raise exception 'That bagging session is not one of yours.' using errcode = 'insufficient_privilege';
  end if;
  if not public.auth_has_permission('pack.run', v_run.company_id) then
    raise exception 'You do not have permission to record bagging.' using errcode = 'insufficient_privilege';
  end if;
  if v_run.voided_at is not null then
    raise exception 'That session was voided.' using errcode = 'invalid_parameter_value';
  end if;
  if v_run.closed_at is not null then
    raise exception 'That session is already closed. Correct it instead.' using errcode = 'invalid_parameter_value';
  end if;
  if coalesce(p_bags, 0) <= 0 then
    raise exception 'How many bags did you fill?' using errcode = 'invalid_parameter_value';
  end if;

  select coalesce(sum((a->>'bags')::numeric), 0) into v_alloc_total
    from jsonb_array_elements(coalesce(p_allocations, '[]'::jsonb)) a;
  if v_alloc_total > p_bags then
    raise exception 'You have set aside % bags but only filled %.', v_alloc_total, p_bags
      using errcode = 'invalid_parameter_value';
  end if;

  v_total := p_bags * coalesce(v_run.unit_weight_lbs, 0);
  select recipe_id into v_recipe from public.products where product_id = v_run.product_id;

  -- 🔴 SERIALISE THE DRAW ON THE COFFEE, not on this run. The contention is two
  -- different runs reaching for one batch, so locking pack_run would not help.
  -- Transaction-scoped: released at commit or rollback, no matter what follows.
  perform pg_advisory_xact_lock(hashtext(v_run.company_id || ':' || coalesce(v_recipe, '-')));

  if p_sources is not null and jsonb_array_length(p_sources) > 0 then
    -- The bin-card path: the packer named the batches, and that IS the record.
    -- Checked for ownership and arithmetic; NOT second-guessed on which batch.
    select count(*) into v_bad
      from jsonb_array_elements(p_sources) s
      left join public.roast_log rl
             on rl.roast_log_id = s->>'roast_log_id'
            and rl.company_id = v_run.company_id
     where rl.roast_log_id is null;
    if v_bad > 0 then
      raise exception 'A batch named here is not one of yours.' using errcode = 'insufficient_privilege';
    end if;

    select count(*) into v_bad
      from jsonb_array_elements(p_sources) s
     where coalesce(nullif(s->>'lbs_used','')::numeric, 0) <= 0;
    if v_bad > 0 then
      raise exception 'Say how many pounds came from each batch. A source with no weight cannot be traced.'
        using errcode = 'invalid_parameter_value';
    end if;

    v_draw := p_sources;
    select coalesce(sum(nullif(s->>'lbs_used','')::numeric), 0) into v_named_lbs
      from jsonb_array_elements(p_sources) s;
    -- A real number, not a hardcoded zero: naming the batches yourself does not
    -- make the arithmetic agree, and a run that is short is worth flagging
    -- whoever decided the sources.
    v_plan := jsonb_build_object('basis', 'named',
                                 'shortfall', round(greatest(v_total - v_named_lbs, 0), 2));
  else
    v_plan := public.pack_draw_plan(v_run.company_id, v_recipe, v_total, 180, v_run.facility_id);
    v_draw := v_plan->'draw';
  end if;

  insert into public.pack_run_source (pack_run_id, roast_log_id, lbs_used)
  select p_pack_run_id, s->>'roast_log_id', nullif(s->>'lbs_used','')::numeric
    from jsonb_array_elements(coalesce(v_draw, '[]'::jsonb)) s
  on conflict (pack_run_id, roast_log_id) do update
    set lbs_used = coalesce(public.pack_run_source.lbs_used, 0) + coalesce(excluded.lbs_used, 0);

  select coalesce(jsonb_agg(jsonb_build_object(
           'roast_log_id', c.roast_log_id,
           'origin_purchase_id', c.origin_purchase_id,
           'lbs_consumed', c.lbs_consumed,
           'origin', coalesce(ci.origin, cip.origin),
           'supplier_lot', cip.lot_id)), '[]'::jsonb)
    into v_snapshot
    from jsonb_array_elements(coalesce(v_draw, '[]'::jsonb)) s
    join public.roast_log_lot_consumption c on c.roast_log_id = s->>'roast_log_id'
    left join public.coffee_inventory_purchased cip on cip.origin_purchase_id = c.origin_purchase_id
    left join public.coffee_inventory ci on ci.origin_id = cip.origin;

  select * into v_actor from public.actor_at();

  update public.pack_run
     set bags              = p_bags,
         total_lbs         = v_total,
         location          = coalesce(nullif(trim(p_location), ''), location),
         bag_purchase_id   = coalesce(p_bag_purchase_id, bag_purchase_id),
         label_purchase_id = coalesce(p_label_purchase_id, label_purchase_id),
         notes             = coalesce(nullif(trim(p_notes), ''), notes),
         best_before       = coalesce(p_best_before, best_before),
         green_snapshot    = v_snapshot,
         closed_at         = now(),
         packed_by_team_member = v_actor.team_member_id,
         packed_by_name        = v_actor.actor_name,
         updated_by            = v_actor.actor_name,
         updated_at            = now()
   where pack_run_id = p_pack_run_id;

  insert into public.pack_run_allocation (pack_run_id, order_detail_id, customer_id, bags)
  select p_pack_run_id,
         nullif(a->>'order_detail_id',''),
         nullif(a->>'customer_id',''),
         (a->>'bags')::numeric
    from jsonb_array_elements(coalesce(p_allocations, '[]'::jsonb)) a
   where coalesce((a->>'bags')::numeric, 0) > 0;

  return jsonb_build_object(
    'pack_run_id', p_pack_run_id,
    'lot_code',    v_run.lot_code,
    'bags',        p_bags,
    'total_lbs',   v_total,
    'basis',       v_plan->>'basis',
    'shortfall',   coalesce((v_plan->>'shortfall')::numeric, 0),
    'allocated',   v_alloc_total,
    'unallocated', p_bags - v_alloc_total);
end;
$$;

revoke all on function public.close_pack_run(text,numeric,text,text,text,text,date,jsonb,jsonb) from public;
grant execute on function public.close_pack_run(text,numeric,text,text,text,text,date,jsonb,jsonb) to authenticated;

commit;
