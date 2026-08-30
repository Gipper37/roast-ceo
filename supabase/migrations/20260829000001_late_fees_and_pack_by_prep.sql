-- Late fees, and the pack queue learns prep.
--
-- 1. Late fees (requirements captured 2026-08-26, built now):
--    - billing_settings.late_fee_percent — the company's standard rate; NULL
--      means the feature is off (simplest possible flag).
--    - a GLOBAL 'Late fee' product type: reduces_total false, is_sellable
--      FALSE — the sellability engine already keeps a non-sellable type out
--      of every order form and the shop, so fee products can never be picked
--      by hand.
--    - the posted-line guard gains ONE carve-out: a late-fee line may be
--      APPENDED to a posted invoice. Nothing else changes — fee lines can't
--      be edited or deleted any more than other lines (a waiver is a credit
--      memo, per the standing immutability doctrine). Penalties are
--      append-only, reversals leave a trail.
--    - apply_late_fee(order_id): the whole fee in one place. Refuses legacy,
--      unposted, paid, void; refuses when the company has no rate; refuses a
--      second fee within 28 days (monthly cadence, protected even if the UI
--      is clicked twice); computes the fee on the CURRENT BALANCE (total + tax
--      − live payments − credit memos), which is what makes next month's fee
--      compound on this month's, and shrink when a partial payment lands.
--      Finds or creates the company's Late fee product on first use.
--
-- 2. pack_totals_by_prep — the totals view aggregates by product alone, so
--    coffee_prep is destroyed before any frontend sees it (the diagnosed hard
--    blocker for grouping the pack queue by grind). Same week logic, one more
--    grouping column.

begin;

-- ── 1a. The setting ──────────────────────────────────────────────────────────
alter table public.billing_settings
  add column if not exists late_fee_percent numeric
  check (late_fee_percent is null or (late_fee_percent >= 0 and late_fee_percent <= 25));

-- ── 1b. The type ─────────────────────────────────────────────────────────────
insert into public.product_type (product_type_id, product_type, reduces_total, is_sellable, company_id)
values ('ptype_late_fee', 'Late fee', false, false, null)
on conflict (product_type_id) do nothing;

-- ── 1c. The guard carve-out ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.guard_posted_order_detail_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE v_posted boolean; v_type text;
BEGIN
  SELECT posted INTO v_posted FROM public.orders
   WHERE order_id = COALESCE(NEW.order_id, OLD.order_id);

  IF NOT COALESCE(v_posted, false) THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'cannot remove a line from posted invoice % — void or issue a credit memo', OLD.order_id;
  END IF;
  IF TG_OP = 'INSERT' THEN
    -- The one sanctioned append: a late-fee line. The original document is
    -- untouched; the penalty is a new, individually identifiable line, and
    -- its reversal is a credit memo — append-only in both directions.
    SELECT p.product_type INTO v_type FROM public.products p WHERE p.product_id = NEW.product_id;
    IF v_type = 'ptype_late_fee' THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'cannot add a line to posted invoice % — void or issue a credit memo', NEW.order_id;
  END IF;
  -- Every number the invoice shows, not just the net. A discount that can move
  -- while total_price stands still is a silently restated invoice.
  IF (NEW.quantity         IS DISTINCT FROM OLD.quantity)
  OR (NEW.product_id       IS DISTINCT FROM OLD.product_id)
  OR (NEW.total_price      IS DISTINCT FROM OLD.total_price)
  OR (NEW.list_price_total IS DISTINCT FROM OLD.list_price_total)
  OR (NEW.discount_kind    IS DISTINCT FROM OLD.discount_kind)
  OR (NEW.discount_value   IS DISTINCT FROM OLD.discount_value)
  OR (NEW.discount_amount  IS DISTINCT FROM OLD.discount_amount)
  OR (NEW.amount_override  IS DISTINCT FROM OLD.amount_override) THEN
    RAISE EXCEPTION 'line on posted invoice % is locked — void or issue a credit memo', OLD.order_id;
  END IF;
  RETURN NEW;
END;
$function$;

-- ── 1d. The fee ──────────────────────────────────────────────────────────────
create or replace function public.apply_late_fee(p_order_id text)
returns numeric
language plpgsql
as $function$
declare
  v_order      record;
  v_pct        numeric;
  v_paid_cents bigint;
  v_balance    numeric;
  v_fee        numeric;
  v_product_id text;
  v_group_id   uuid;
begin
  select o.order_id, o.company_id, o.facility_id, o.posted, o.invoice_state,
         o.is_legacy_import, o.due_date,
         (coalesce(o.order_total,0) + coalesce(o.tax_amount,0)) as doc_total
    into v_order
    from public.orders o
   where o.order_id = p_order_id
   for update;
  if not found then raise exception 'order % not found', p_order_id; end if;
  if coalesce(v_order.is_legacy_import, false) then
    raise exception 'imported invoices keep their original amounts — no fees on % ', p_order_id;
  end if;
  if not coalesce(v_order.posted, false)
     or v_order.invoice_state not in ('open','overdue','partial') then
    raise exception 'late fees apply to open, partial or overdue STRATA invoices only (this one is %)',
      coalesce(v_order.invoice_state, 'not issued');
  end if;
  if v_order.due_date is null or v_order.due_date >= current_date then
    raise exception 'invoice % is not past due', p_order_id;
  end if;

  select late_fee_percent into v_pct
    from public.billing_settings where company_id = v_order.company_id;
  if v_pct is null or v_pct <= 0 then
    raise exception 'no standard late fee is set — add one in Configuration first';
  end if;

  -- Monthly cadence, enforced where the click can't break it.
  if exists (
    select 1 from public.order_details od
    join public.products p on p.product_id = od.product_id
    where od.order_id = p_order_id
      and p.product_type = 'ptype_late_fee'
      and od.created_at > now() - interval '28 days'
  ) then
    raise exception 'a late fee was already added to % in the last 28 days', p_order_id;
  end if;

  -- The balance the fee compounds on: document total (any prior fees
  -- included) minus live payments and credit memos — the recompute's math.
  select coalesce(sum(a.amount_cents),0) into v_paid_cents
    from public.invoice_payment_allocations a
    join public.invoice_payments p on p.payment_id = a.payment_id
   where a.order_id = p_order_id and p.voided_at is null;
  v_paid_cents := v_paid_cents + coalesce((select sum(amount_cents)
    from public.credit_memos where applied_to_order_id = p_order_id and voided_at is null), 0);

  v_balance := v_order.doc_total - (v_paid_cents / 100.0);
  v_fee := round(v_balance * v_pct / 100.0, 2);
  if v_fee <= 0 then
    raise exception 'nothing outstanding on % — no fee to charge', p_order_id;
  end if;

  -- The company's Late fee product, created on first use. Non-sellable by
  -- type, so it exists for these lines and appears in no picker or shop.
  select p.product_id into v_product_id
    from public.products p
   where p.company_id = v_order.company_id
     and p.product_type = 'ptype_late_fee'
     and p.is_active
   limit 1;
  if v_product_id is null then
    v_group_id := gen_random_uuid();
    insert into public.product_groups (group_id, group_name, product_type, company_id, facility_id)
    values (v_group_id, 'Late fee', 'ptype_late_fee', v_order.company_id, v_order.facility_id);
    v_product_id := gen_random_uuid()::text;
    insert into public.products (product_id, product_name, group_id, product_type,
                                 company_id, facility_id, is_active)
    values (v_product_id, 'Late fee', v_group_id, 'ptype_late_fee',
            v_order.company_id, v_order.facility_id, true);
  end if;

  -- Through the engine like any line: amount_override is honoured verbatim,
  -- and 'Delivered' keeps it out of every pack rollup — there is nothing to
  -- pack about a penalty.
  insert into public.order_details (order_detail_id, order_id, product_id,
                                    quantity, amount_override, item_status)
  values (gen_random_uuid()::text, p_order_id, v_product_id, 1, v_fee, 'Delivered');

  return v_fee;
end;
$function$;

-- ── 2. Pack totals, by prep ──────────────────────────────────────────────────
create or replace view public.pack_totals_by_prep
with (security_invoker = true) as
with facility_params as (
  select f.facility_id, f.company_id,
         coalesce(nullif(f.time_zone, ''), 'Pacific/Honolulu') as timezone,
         coalesce(( select cp.value_number::integer from company_parameters cp
                     where cp.parameter_id = 'orders_reset_day' and cp.facility_id = f.facility_id limit 1),
                  ( select sp.amount::integer from standard_parameters sp
                     where sp.parameters_id = 'orders_reset_day' limit 1), 6) as orders_reset_day
    from facilities f
), calc as (
  select fp.facility_id, fp.company_id,
         (current_timestamp at time zone fp.timezone)::date
           - (extract(dow from (current_timestamp at time zone fp.timezone)::date)::integer
              - fp.orders_reset_day + 7) % 7 as orders_week_start
    from facility_params fp
)
select o.facility_id, o.company_id, od.product_id,
       od.coffee_prep,
       sum(od.quantity) filter (where od.item_status = 'Open') as left_to_pack,
       sum(od.quantity) filter (where od.item_status = 'Packed'
                                  and o.order_date >= c.orders_week_start) as packed_qty
  from order_details od
  join orders o on o.order_id = od.order_id
  join calc c on c.facility_id = o.facility_id
 where o.order_status <> 'Canceled'
 group by o.facility_id, o.company_id, od.product_id, od.coffee_prep;

commit;

notify pgrst, 'reload schema';
