-- A customer reachable only at a notification address is on the recall list.
--
-- Owner, 2026-11-16: "fix the recal ... also", of the fan-out work in
-- 20261116000001.
--
-- 🔴 WHAT I FIRST TOLD HIM WAS WRONG, AND THE CORRECTION IS THE POINT.
-- I reported that a customer with notification emails but no `customers.email`
-- "is never offered a recall notice at all". They are: `finalise_recall`
-- inserts a `recall_notice` row for EVERY customer in the report. The real
-- defect is quieter and worse:
--
--   `recall_report` reads `cu.email` alone, so the frozen notice has no
--   address. The screen then says "N have no email address: fill one in"
--   (RecallDetail.tsx:342) while ap@ sits in the column next door, and
--   `confirm_recall_send` filters `nullif(email,'') is not null` -- so that
--   customer is counted as unreachable and left OUT of the send, on a recall,
--   silently.
--
-- So the fix belongs at the FREEZE, not at the send gate: once the address is
-- frozen, the count, the warning, the expected-count check and the send all
-- agree with no further change.
--
-- WHAT CHANGES, IN THREE PIECES.
--
-- 1. `public.is_sendable_email(text)`, new. The SQL twin of `SENDABLE_EMAIL`
--    in lib/email/recipients.ts. The duplication is deliberate and it is the
--    smaller cost: `notification_emails` has a cap constraint but no format
--    check, so a row written by anything other than the one normalising code
--    path could put junk in -- and freezing junk would make the screen say
--    "reachable" and the send fail. One unusable entry must leave the customer
--    reading as unreachable, which is TRUE and tells the roaster what to fix.
--
-- 2. `recall_report`.customers now coalesces `cu.email` with the first
--    sendable `notification_emails` entry, emits `customer_id`, and says in
--    `email_source` which column the address came from. Fixing the REPORT and
--    not just the freeze is what makes the wizard's preview honest too
--    (NewRecallWizard.tsx:492 renders "(no email on file)" from this).
--
--    🔴 `customer_id` inside `select distinct jsonb_build_object(...)` SPLITS
--    two same-named customers into two rows. That is a correction, not a
--    regression: `totals.customers` already counts `distinct cust`, so the
--    list was under-reporting against its own total. Both readers of this
--    array (NewRecallWizard.tsx:492, RecallDetail.tsx:972) read `customer`,
--    `email`, `phone` and `address` by name, so the extra keys are additive.
--
-- 3. `finalise_recall` joins the customer by `customer_id` instead of
--    `cu.name_company = c->>'customer'`. (company_id, name_company) is NOT
--    unique -- prod has 10 duplicate groups covering 20 customers -- so the
--    name join could seat one customer's frozen address beside the other's
--    customer_id. `lib/food-safety/recallNoticeEmail.ts` distrusts that id for
--    exactly this reason; now it has a key it can trust.
--
-- 🔴 WHY THIS CANNOT BE APPLIED BEFORE 20261116000001, AND WHY THE FILENAME IS
-- THE ONLY THING PROTECTING THAT. Both functions are plpgsql, and with
-- `check_function_bodies = on` a plpgsql body naming a missing column is
-- accepted at CREATE and fails only at call time, with 42703. So a wrong order
-- here would go green in CI and break at the first roaster who finalises a
-- recall. The verify block asserts `customers.notification_emails` exists,
-- which is the assertion that makes this file safe.
--
-- NOTHING HISTORICAL IS RE-MEANT: prod has 0 `recall_notice` rows, so no
-- frozen notice is rewritten and no sent notice changes meaning. Both bodies
-- below were extracted with `pg_get_functiondef` and patched in place, never
-- retyped: CREATE OR REPLACE rewrites all of a body, and `recall_report` is
-- 368 lines of it.

begin;

set local lock_timeout = '3s';
set local statement_timeout = '120s';

-- ---------------------------------------------------------------------------
-- 1. The sendability rule, in SQL, once.
-- ---------------------------------------------------------------------------
create or replace function public.is_sendable_email(p_email text)
returns boolean
language sql
immutable
parallel safe
set search_path to 'pg_catalog', 'pg_temp'
as $fn$
  -- Deliberately conservative, and deliberately not RFC 5322, for the same
  -- reason the TS twin is: it exists to keep one unusable entry out of a `to:`
  -- field, because Resend rejects a malformed address for the WHOLE message.
  select coalesce(p_email, '') ~ '^[^[:space:]@,;<>"]+@[^[:space:]@,;<>"]+\.[^[:space:]@,;<>"]{2,}$';
$fn$;

comment on function public.is_sendable_email(text) is
  'Whether one address is sendable. The SQL twin of SENDABLE_EMAIL in lib/email/recipients.ts; keep the two in step. Used by recall_report to decide whether a customers.notification_emails entry may be frozen onto a recall notice: freezing an unusable entry would make the screen say the customer is reachable and the send fail.';


-- ---------------------------------------------------------------------------
-- 2. recall_report: a notification address is an address.
--    Extracted with pg_get_functiondef and patched in the customers block
--    only. Everything else is byte-for-byte what prod runs today.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.recall_report(p_lot_code text DEFAULT NULL::text, p_origin_purchase_id text DEFAULT NULL::text, p_packaging_lot_code text DEFAULT NULL::text, p_scope text DEFAULT 'green'::text, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
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
  v_trace_from date;
  v_untraceable jsonb := '[]'::jsonb;
  v_from date;
  v_to   date;
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

  -- Clip the trace to its dates. The trigger that fired this recall is
  -- exempt: you are holding that bag, whatever its date.
  select st.trace_start_date into v_trace_from
    from public.fs_settings st where st.company_id = v_company;

  -- p_from may narrow the window but never widen it past the day lot
  -- tracking began — that would print history nobody tracked and imply
  -- somebody checked it.
  v_from := greatest(p_from, v_trace_from);
  if v_from is null then v_from := coalesce(p_from, v_trace_from); end if;
  v_to := coalesce(p_to, current_date);

  if v_from is not null or p_to is not null then
    select coalesce(array_agg(rl.roast_log_id), '{}')
      into v_roasts
      from public.roast_log rl
     where rl.roast_log_id = any (coalesce(v_roasts, '{}'))
       and (v_from is null or rl.roast_date::date >= v_from)
       and (v_to   is null or rl.roast_date::date <= v_to);

    select coalesce(array_agg(pr.pack_run_id), '{}')
      into v_runs
      from public.pack_run pr
     where pr.pack_run_id = any (coalesce(v_runs, '{}'))
       and (
         -- the bag that came back is never clipped out of its own recall
         (p_lot_code is not null and pr.lot_code = p_lot_code)
         or ((v_from is null or pr.packed_on >= v_from)
             and (v_to is null or pr.packed_on <= v_to)));
  end if;

  if v_scope = 'green' then
    select coalesce(jsonb_agg(jsonb_build_object(
             'roast_log_id', sf.roast_log_id,
             'roast_date', rl.roast_date,
             'recipe', coalesce(rl.recipe_name_snapshot, rr.recipe_name),
             'coffee', ci2.origin,
             'lbs_unaccounted', sf.lbs_unmet) order by rl.roast_date desc), '[]'::jsonb)
      into v_untraceable
      from public.roast_lot_shortfall sf
      join public.roast_log rl on rl.roast_log_id = sf.roast_log_id
      left join public.roast_recipes rr on rr.recipe_id = rl.recipe_id
      left join public.coffee_inventory ci2
             on ci2.origin_id = sf.origin_id and ci2.facility_id = sf.facility_id
     where sf.company_id = v_company
       and sf.waived_at is null
       -- Pre-implementation history is out of scope, not an open question.
       and (v_from is null or rl.roast_date::date >= v_from)
       and (v_to   is null or rl.roast_date::date <= v_to)
       -- Only green this recall actually implicates.
       and exists (select 1 from public.coffee_inventory_purchased cip2
                    where cip2.origin_purchase_id = any (v_green)
                      and cip2.origin = sf.origin_id
                      and cip2.facility_id = sf.facility_id)
       -- Already traced by the normal path: not a gap.
       and not (sf.roast_log_id = any (coalesce(v_roasts, '{}')));
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
                 'customer_id', cu.customer_id,
                 'customer', cu.name_company,
                 -- A customer reachable only at a notification address IS
                 -- reachable. Before this, a blank `email` froze a notice with
                 -- no address, the screen said "fill one in" with ap@ sitting
                 -- in the column next door, and confirm_recall_send left them
                 -- out of the send entirely.
                 'email', coalesce(
                            nullif(trim(cu.email), ''),
                            (select e from unnest(cu.notification_emails) e
                              where public.is_sendable_email(e) limit 1)),
                 -- Which column it came from, so the notice can say so and a
                 -- bounce on ap@ does not stamp email_bounced_at on a customer
                 -- whose own address is fine.
                 'email_source', case
                   when nullif(trim(cu.email), '') is not null then 'customer'
                   when exists (select 1 from unnest(cu.notification_emails) e
                                 where public.is_sendable_email(e)) then 'notification'
                   else null end,
                 'phone', cu.phone,
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

    'trace_start_date', v_trace_from,
    'covers_from', v_from,
    'covers_to', v_to,
    -- Roasts this recall KNOWS it could not follow. An empty green trace
    -- with a non-empty list here means "we could not trace N roasts", not
    -- "nothing else is affected".
    'untraceable_roasts', v_untraceable,

    'totals', jsonb_build_object(
      'green_lots',    coalesce(array_length(v_green,1), 0),
      'roast_batches', (select count(*) from roasts),
      'packed_lots',   (select count(*) from runs),
      'bags_packed',   (select coalesce(sum(bags),0) from runs),
      'bags_shipped',  (select coalesce(sum(bags),0) from allocs where released_at is null),
      'bags_released', (select coalesce(sum(bags),0) from allocs where released_at is not null),
      'bags_unaccounted', (select coalesce(sum(bags),0) from runs)
                          - (select coalesce(sum(bags),0) from allocs where released_at is null),
      'customers',     (select count(distinct cust) from allocs where cust is not null),
      'untraceable_roasts', jsonb_array_length(v_untraceable),
      'lbs_unaccounted', (select coalesce(sum((e->>'lbs_unaccounted')::numeric), 0)
                              from jsonb_array_elements(v_untraceable) e))
  ) into v_report;

  return v_report;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 3. finalise_recall: join the customer by id, not by name.
--    Extracted with pg_get_functiondef and patched in the insert's join only.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.finalise_recall(p_recall_id text, p_variance_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
    -- 🔴 THE ID, NOT THE NAME. (company_id, name_company) is not unique --
    -- prod has 10 duplicate groups covering 20 customers -- so the name join
    -- could seat one customer's frozen address beside the other's
    -- customer_id, and a recall notice is the worst place to mis-address.
    -- recall_report now emits customer_id, so the join has a key.
    left join public.customers cu
           on cu.company_id = v_rec.company_id
          and cu.customer_id = c->>'customer_id';

  return jsonb_build_object(
    'recall_id', p_recall_id, 'reference_no', v_rec.reference_no,
    'elapsed_minutes', v_elapsed, 'within_two_hours', v_elapsed <= 120,
    'accounted_pct', v_pct, 'bags_packed', v_packed, 'bags_shipped', v_shipped,
    'bags_unaccounted', v_unacc,
    'customers', (select count(*) from public.recall_notice where recall_id = p_recall_id),
    'without_email', (select count(*) from public.recall_notice where recall_id = p_recall_id and nullif(email,'') is null));
end;
$function$;

do $$
declare
  v_type   text;
  v_src    text;
  v_n      int;
  v_defn   boolean;
  v_path   text[];
  v_flat   text;
begin
  -- 1. 🔴 THE 42703 TRAP. Both bodies below name
  --    customers.notification_emails, and a plpgsql body naming a missing
  --    column is accepted at CREATE and fails only when a roaster finalises a
  --    recall. This is the assertion that makes the file order matter.
  select format_type(a.atttypid, a.atttypmod) into v_type
  from pg_attribute a
  where a.attrelid = 'public.customers'::regclass
    and a.attname  = 'notification_emails'
    and not a.attisdropped;

  if v_type is null then
    raise exception 'customers.notification_emails does not exist, so recall_report would fail with 42703 the first time a roaster finalises a recall. Apply 20261116000001 first.';
  end if;
  if v_type <> 'text[]' then
    raise exception 'customers.notification_emails is %, not text[]; unnest() in recall_report would not compile the way this migration assumes', v_type;
  end if;

  -- 2. The sendability rule answers, in both directions. A rule that only ever
  --    says yes would freeze junk; one that only ever says no would make every
  --    notification-only customer read as unreachable, which is the bug.
  if not public.is_sendable_email('ap@maui.example.com') then
    raise exception 'is_sendable_email rejects a plainly good address, so no notification-only customer would ever reach the recall list';
  end if;
  if public.is_sendable_email('ap@') or public.is_sendable_email('ap@x')
     or public.is_sendable_email('a@b.c') then
    raise exception 'is_sendable_email accepts an address with no usable domain, which Resend refuses for the whole message';
  end if;
  if public.is_sendable_email('a b@c.co') or public.is_sendable_email('x@y.co, z@w.co')
     or public.is_sendable_email('a@b.co;c@d.co') or public.is_sendable_email('<a@b.co>') then
    raise exception 'is_sendable_email accepts a string holding more than one address or a delimiter, so one entry could carry a second address nobody chose';
  end if;
  if public.is_sendable_email('') or public.is_sendable_email(null) is not false then
    raise exception 'is_sendable_email does not answer false for an empty or null address';
  end if;

  -- 3. recall_report actually reads the second column, says where the address
  --    came from, and emits the key the freeze needs.
  select count(*) into v_n
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'recall_report';
  if v_n <> 1 then
    raise exception 'there are % recall_report functions; a changed signature creates an OVERLOAD and the old one keeps being called', v_n;
  end if;

  select p.prosrc, p.prosecdef, p.proconfig into v_src, v_defn, v_path
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'recall_report';

  -- 🔴 NOT "does the body mention the column". It does, in `email_source`, so
  --    that check PASSED while the address itself was back on `cu.email`
  --    alone -- the sabotage run caught it. The assertion has to be the
  --    ADDRESS expression, flattened so reindenting the body does not trip it.
  v_flat := regexp_replace(v_src, '\s+', ' ', 'g');
  if position('''email'', coalesce( nullif(trim(cu.email), ''''), (select e from unnest(cu.notification_emails) e where public.is_sendable_email(e) limit 1)),' in v_flat) = 0 then
    raise exception 'recall_report no longer resolves the address as cu.email coalesced with the first sendable notification_emails entry, so a customer reachable only there is frozen with no address and left out of the send';
  end if;
  if position('is_sendable_email' in v_src) = 0 then
    raise exception 'recall_report no longer checks sendability, so an unusable notification entry could be frozen and the screen would call that customer reachable';
  end if;
  if position('email_source' in v_src) = 0 then
    raise exception 'recall_report no longer says which column the address came from, so a bounce on a notification address cannot be told from one on the customer''s own';
  end if;
  if position('''customer_id'', cu.customer_id' in v_src) = 0 then
    raise exception 'recall_report no longer emits customer_id, so finalise_recall has no key to join on and would be back on the name join';
  end if;
  if not v_defn then
    raise exception 'recall_report is no longer SECURITY DEFINER; it reads across a tenant''s whole trace and the RLS on those tables would now refuse it';
  end if;
  if v_path is null or not (v_path @> array['search_path=public, pg_temp']) then
    raise exception 'recall_report lost its pinned search_path (now %); a SECURITY DEFINER function without one is resolvable by the caller', coalesce(v_path::text, '<none>');
  end if;

  -- 4. finalise_recall joins on the id, and NOT on the name. Both halves: the
  --    old join still present would mean the replace silently did nothing.
  select count(*) into v_n
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'finalise_recall';
  if v_n <> 1 then
    raise exception 'there are % finalise_recall functions; a changed signature creates an OVERLOAD', v_n;
  end if;

  select p.prosrc, p.prosecdef into v_src, v_defn
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'finalise_recall';

  if position('cu.customer_id = c->>''customer_id''' in v_src) = 0 then
    raise exception 'finalise_recall does not join the customer by id';
  end if;
  if position('cu.name_company = c->>''customer''' in v_src) > 0 then
    raise exception 'finalise_recall still joins the customer by name, so the replace did not take; (company_id, name_company) is not unique and one customer''s address can be seated beside another''s customer_id';
  end if;
  if position('recall_notice' in v_src) = 0 then
    raise exception 'finalise_recall no longer writes recall_notice rows; the behaviour that existed before this migration has been lost';
  end if;
  if not v_defn then
    raise exception 'finalise_recall is no longer SECURITY DEFINER';
  end if;
end $$;

commit;
