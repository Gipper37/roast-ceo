-- Receipts keep their bags, and one delivery becomes ONE shipment
-- (owner-approved 2026-09-05, cleanup mediums).
--
-- 1. record_lot_receipt gains p_bags_ordered: the operator counted bags at
--    capture time and the receipt form now asks (required, prefilled) — but
--    the number was thrown away before this, leaving every recorded receipt
--    a shipment line with a blank Bags field. The trigger
--    trg_compute_coffee_purchase_amount fires BEFORE UPDATE OF bags_ordered
--    and overwrites bag_size with the raw coffee_source value (can be NULL)
--    and amount with bags x bag_size — for a counted lot both were set from
--    the count and must not drift, so a guard UPDATE (bag_size/amount are
--    NOT in the trigger's OF list) restores them. Counts are truth.
--    The old 7-arg function is DROPPED first: CREATE OR REPLACE with a new
--    defaulted arg would leave two overloads and PostgREST would refuse the
--    call as ambiguous (PGRST203).
--
-- 2. record_lot_receipts (batch): N counted lots from one physical delivery
--    become ONE received shipment header instead of N 'rcpt-…' headers —
--    shared supplier/date/shipping, per-lot cost + bags. Validates
--    everything first, aggregates the received-after-count warnings into a
--    single confirmable return (nothing written until clean or confirmed),
--    then writes atomically.

begin;

drop function if exists public.record_lot_receipt(text, numeric, text, date, numeric, text, boolean);

create function public.record_lot_receipt(
  p_origin_purchase_id text,
  p_cost_lb numeric,
  p_supplier_id text,
  p_received_date date,
  p_shipping_cost numeric default 0,
  p_shipment_id text default null,
  p_confirm_past_count boolean default false,
  p_bags_ordered numeric default null)
returns jsonb
language plpgsql
as $function$
declare
  v_lot record; v_count_date date; v_ship text;
begin
  select * into v_lot from public.coffee_inventory_purchased where origin_purchase_id = p_origin_purchase_id;
  if not found then raise exception 'lot % not found', p_origin_purchase_id; end if;
  if not coalesce(v_lot.receipt_pending, false) then raise exception 'lot has no pending receipt to record'; end if;
  if p_cost_lb is null or p_cost_lb < 0 then raise exception 'cost per lb is required'; end if;
  if p_received_date is null then raise exception 'received date is required'; end if;
  if p_bags_ordered is not null and p_bags_ordered <= 0 then raise exception 'bag count must be > 0'; end if;
  select max(count_date) into v_count_date
    from public.coffee_lot_count where origin_purchase_id = p_origin_purchase_id;
  if v_count_date is not null and p_received_date > v_count_date and not p_confirm_past_count then
    return jsonb_build_object(
      'warning', 'received_after_count',
      'count_date', v_count_date, 'received_date', p_received_date,
      'message', format('This lot was counted on %s but the receipt is dated %s (later). The counted bags can''t have come from a shipment received after the count — check the date, or confirm to record anyway.', v_count_date, p_received_date));
  end if;
  if p_shipment_id is not null then
    v_ship := p_shipment_id;
  else
    v_ship := 'rcpt-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 18);
    insert into public.shipment_received
      (shipment_id, company_id, facility_id, supplier_id, order_date, date_received, shipping_cost, status, voided, created_at, updated_at)
    values
      (v_ship, v_lot.company_id, v_lot.facility_id, p_supplier_id, p_received_date, p_received_date, coalesce(p_shipping_cost, 0), 'received', false, now(), now());
  end if;
  update public.coffee_inventory_purchased
     set shipment_id = v_ship, cost_lb = p_cost_lb, entry_method = 'shipment',
         bags_ordered = coalesce(p_bags_ordered, bags_ordered),
         receipt_pending = false, updated_at = now()
   where origin_purchase_id = p_origin_purchase_id;
  -- Trigger-overwrite guard: restore the counted bag_size/amount (BEFORE
  -- trigger rewrote them when bags_ordered changed). These columns are not
  -- in the trigger's OF list, so this sticks without re-firing it.
  update public.coffee_inventory_purchased
     set bag_size = v_lot.bag_size, amount = v_lot.amount
   where origin_purchase_id = p_origin_purchase_id
     and (bag_size is distinct from v_lot.bag_size or amount is distinct from v_lot.amount);
  return jsonb_build_object('ok', true, 'shipment_id', v_ship);
end;
$function$;

revoke execute on function public.record_lot_receipt(text, numeric, text, date, numeric, text, boolean, numeric) from public;

create function public.record_lot_receipts(
  p_receipts jsonb,
  p_supplier_id text,
  p_received_date date,
  p_shipping_cost numeric default 0,
  p_confirm_past_count boolean default false)
returns jsonb
language plpgsql
as $function$
declare
  v_item jsonb; v_lot record; v_count_date date; v_ship text;
  v_id text; v_cost numeric; v_bags numeric;
  v_company text; v_facility text;
  v_seen text[] := '{}'; v_warn jsonb := '[]'::jsonb; v_n int := 0;
begin
  if p_receipts is null or jsonb_typeof(p_receipts) <> 'array' or jsonb_array_length(p_receipts) = 0 then
    raise exception 'no lots to record';
  end if;
  if p_received_date is null then raise exception 'received date is required'; end if;

  -- Pass 1: validate every lot before writing anything.
  for v_item in select * from jsonb_array_elements(p_receipts) loop
    v_id := v_item->>'origin_purchase_id';
    v_cost := (v_item->>'cost_lb')::numeric;
    v_bags := (v_item->>'bags_ordered')::numeric;
    if v_id is null then raise exception 'lot id missing'; end if;
    if v_id = any(v_seen) then raise exception 'lot % appears twice in this delivery', v_id; end if;
    v_seen := v_seen || v_id;
    select * into v_lot from public.coffee_inventory_purchased where origin_purchase_id = v_id;
    if not found then raise exception 'lot % not found', v_id; end if;
    if not coalesce(v_lot.receipt_pending, false) then raise exception 'lot % has no pending receipt to record', v_id; end if;
    if v_cost is null or v_cost < 0 then raise exception 'cost per lb is required for every lot'; end if;
    if v_bags is null or v_bags <= 0 then raise exception 'bag count is required for every lot'; end if;
    if v_company is null then
      v_company := v_lot.company_id; v_facility := v_lot.facility_id;
    elsif v_lot.company_id is distinct from v_company or v_lot.facility_id is distinct from v_facility then
      raise exception 'these lots belong to different facilities — record them separately';
    end if;
    select max(count_date) into v_count_date
      from public.coffee_lot_count where origin_purchase_id = v_id;
    if v_count_date is not null and p_received_date > v_count_date then
      v_warn := v_warn || jsonb_build_object(
        'origin_purchase_id', v_id, 'lot_id', v_lot.lot_id,
        'count_date', v_count_date, 'received_date', p_received_date);
    end if;
  end loop;

  -- One aggregate confirm for the whole delivery; nothing written yet.
  if jsonb_array_length(v_warn) > 0 and not p_confirm_past_count then
    return jsonb_build_object(
      'warning', 'received_after_count',
      'lots', v_warn,
      'message', format('%s of these lots were counted before this received date. The counted bags can''t have come from a shipment received after the count — check the date, or confirm to record anyway.', jsonb_array_length(v_warn)));
  end if;

  -- Write: one delivery header, then every lot onto it.
  v_ship := 'rcpt-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 18);
  insert into public.shipment_received
    (shipment_id, company_id, facility_id, supplier_id, order_date, date_received, shipping_cost, status, voided, created_at, updated_at)
  values
    (v_ship, v_company, v_facility, p_supplier_id, p_received_date, p_received_date, coalesce(p_shipping_cost, 0), 'received', false, now(), now());

  for v_item in select * from jsonb_array_elements(p_receipts) loop
    v_id := v_item->>'origin_purchase_id';
    v_cost := (v_item->>'cost_lb')::numeric;
    v_bags := (v_item->>'bags_ordered')::numeric;
    select * into v_lot from public.coffee_inventory_purchased where origin_purchase_id = v_id;
    update public.coffee_inventory_purchased
       set shipment_id = v_ship, cost_lb = v_cost, entry_method = 'shipment',
           bags_ordered = v_bags,
           receipt_pending = false, updated_at = now()
     where origin_purchase_id = v_id;
    update public.coffee_inventory_purchased
       set bag_size = v_lot.bag_size, amount = v_lot.amount
     where origin_purchase_id = v_id
       and (bag_size is distinct from v_lot.bag_size or amount is distinct from v_lot.amount);
    v_n := v_n + 1;
  end loop;

  return jsonb_build_object('ok', true, 'shipment_id', v_ship, 'count', v_n);
end;
$function$;

revoke execute on function public.record_lot_receipts(jsonb, text, date, numeric, boolean) from public;

notify pgrst, 'reload schema';

commit;
