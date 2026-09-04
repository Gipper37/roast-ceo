-- Late-fee cadence comes from the invoice's own net terms, not a hardcode.
--
-- apply_late_fee refused a second fee within a flat 28 days. Owner
-- (2026-09-04): the cadence should be the invoice's terms — a Net 30 invoice
-- that stays unpaid can take another fee each 30 days past due, a Net 14
-- every 14. The terms period is derived from the invoice itself
-- (due_date − order_date), which is how the due date was computed at issue,
-- so it holds for every posted invoice including imports. Floored at 7 days
-- so due-on-receipt terms (period 0) can never fee daily.
--
-- Body otherwise byte-identical to the live function (exported via
-- pg_get_functiondef 2026-09-04) except: order_date added to the select,
-- v_window_days declared/computed, the cadence guard + its message, and
-- "Configuration" → "Settings" in the no-fee-set error.

begin;

CREATE OR REPLACE FUNCTION public.apply_late_fee(p_order_id text)
 RETURNS numeric
 LANGUAGE plpgsql
AS $function$
declare
  v_order       record;
  v_role        text;
  v_pct         numeric;
  v_paid_cents  bigint;
  v_balance     numeric;
  v_fee         numeric;
  v_product_id  text;
  v_group_id    uuid;
  v_window_days integer;
begin
  select o.order_id, o.company_id, o.facility_id, o.posted, o.invoice_state,
         o.due_date, o.order_date,
         (coalesce(o.order_total,0) + coalesce(o.tax_amount,0)) as doc_total
    into v_order
    from public.orders o
   where o.order_id = p_order_id
   for update;
  if not found then raise exception 'order % not found', p_order_id; end if;

  -- REST-callable, so the permission gate lives here too, not only in the
  -- server action. No auth context (psql, service role) passes — the same
  -- trust every service path already carries.
  if auth.uid() is not null then
    select t.role into v_role
      from public.team t
     where t.auth_user_id = auth.uid()
       and t.company_id = v_order.company_id
       and t.is_active
     limit 1;
    if v_role is null or not exists (
      select 1 from public.role_permissions rp
       where rp.role_id = v_role
         and rp.permission_id = 'ar.late_fee_apply'
         and rp.granted
    ) then
      raise exception 'your role cannot apply late fees';
    end if;
  end if;

  -- Posted + a collectable state are the gates. The legacy-import flag is
  -- deliberately NOT one: an ADOPTED imported invoice (posted by the
  -- adoption script) ages and fees like any other. Un-adopted history is
  -- never posted, so it can never arrive here.
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
    raise exception 'no standard late fee is set — add one in Settings first';
  end if;

  -- Once per terms period, enforced where the click can't break it. The
  -- period is the invoice's own net terms (due − issue date), floored at
  -- 7 days so due-on-receipt invoices can never fee daily.
  v_window_days := greatest(coalesce(v_order.due_date - v_order.order_date, 28), 7);
  if exists (
    select 1 from public.order_details od
    join public.products p on p.product_id = od.product_id
    where od.order_id = p_order_id
      and p.product_type = 'ptype_late_fee'
      and od.created_at > now() - (v_window_days || ' days')::interval
  ) then
    raise exception 'a late fee was already added to % within its % day terms period', p_order_id, v_window_days;
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

  -- The sentinel the guard demands: only THIS function, having passed every
  -- check above, may append to a posted invoice — and only for this order,
  -- only within this transaction. A raw PostgREST insert has no sentinel and
  -- dies in the guard like any other tampering (review P1).
  perform set_config('app.late_fee_append', p_order_id, true);

  -- Money columns are explicit because handle_order_detail_logic deliberately
  -- skips repricing legacy rows — an ADOPTED imported invoice would otherwise
  -- get a fee line with no dollars on it. On native rows the trigger derives
  -- the same values from amount_override; writing both keeps one truth.
  insert into public.order_details (order_detail_id, order_id, product_id,
                                    quantity, amount_override,
                                    unit_price_at_sale, list_price_total,
                                    discount_amount, total_price, item_status)
  values (gen_random_uuid()::text, p_order_id, v_product_id, 1, v_fee,
          v_fee, v_fee, 0, v_fee, 'Delivered');

  perform set_config('app.late_fee_append', '', true);

  return v_fee;
end;
$function$;

commit;
