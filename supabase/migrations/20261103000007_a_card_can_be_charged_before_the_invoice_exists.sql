-- Charge a card on an order that has no invoice yet.
--
-- Owner, 2026-11-03: "i need to be able to record payment and that would stamp the
-- invoice number and as paid if it went through ... what if i need to charge someone
-- before it gets packed."
--
-- "If it went through" fixes the order of things: the card goes first and the number
-- is minted only on approval, so a declined card burns no invoice number and leaves
-- the order exactly as it was. reserve_terminal_charge refuses an order with no
-- invoice, on purpose, so this is its sibling for that one case.
--
-- 🔴 EVERY REFUSAL finalize_invoice WOULD MAKE IS MADE HERE, BEFORE THE CARD. Once the
-- gateway says yes, finalize_invoice failing means money with no invoice to put it
-- on. Same lock, same pending row and hold, so two people charging one order cannot
-- both capture, and a charge in flight here also counts against
-- reserve_terminal_charge, which reads the same holds.
--
-- 🔴 APPROVED IS NOT THE SAME AS RECORDED. The gateway's yes flips the row to 'approved'
-- before the invoice is issued and the ledger written, and a hold counted only while
-- 'pending'. So if either of those failed, "do not charge again" lived only in one
-- browser's memory: a reload or a second operator reserved cleanly and took the card a
-- second time. It also covers the seconds between approval and the ledger, and a
-- pending charge the webhook later approves. charge_hold_is_live is that one answer:
-- a hold stands until the money is ON an invoice, meaning a payment row with an
-- allocation, because the balance reads allocations and a payment row alone changes
-- nothing. A voided payment also ends it: that charge has been dealt with.
-- reserve_terminal_charge has the same gap; asking this function is the only change to
-- its body. The invoice pay page asks it too (order_live_hold_cents) and writes holds
-- of its own, so one surface's unanswered charge blocks the others.
--
-- stuck_card_charges is the list a person works from. A charge the webhook approves
-- after a timeout left status 'pending', so every stuck list dropped it while the
-- invoice stayed unpaid and the reservation kept refusing, with no way to see why.
--
-- Security invoker, like its sibling: tenancy comes from auth_company_ids and the
-- pending row from payment_transactions_insert, which asks payment.charge_card.

create or replace function public.charge_hold_is_live(p_txn uuid)
returns boolean
language sql
stable
as $function$
  select exists (
    select 1 from public.payment_transactions t
     where t.payment_transaction_id = p_txn
       and (t.status = 'pending'
            or (t.status = 'approved'
                and not exists (
                  select 1 from public.invoice_payments lp
                   where lp.payment_transaction_id = t.payment_transaction_id
                     and (lp.voided_at is not null
                          or exists (select 1 from public.invoice_payment_allocations la
                                      where la.payment_id = lp.payment_id)))))
  );
$function$;

create or replace function public.order_live_hold_cents(p_order_ids text[])
returns bigint
language sql
stable
as $function$
  select coalesce(sum(h.amount_cents), 0)::bigint
    from public.terminal_charge_holds h
   where h.order_id = any (p_order_ids)
     and public.charge_hold_is_live(h.payment_transaction_id);
$function$;

create or replace function public.stuck_card_charges(p_company_id text)
returns table (
  payment_transaction_id uuid,
  order_id text,
  gross_amount_cents bigint,
  created_at timestamptz,
  status text
)
language sql
stable
as $function$
  select t.payment_transaction_id, t.order_id, t.gross_amount_cents, t.created_at, t.status
    from public.payment_transactions t
   where t.company_id = p_company_id
     and t.type = 'sale'
     and (
       (t.status = 'pending' and t.created_at < now() - interval '1 day')
       or (t.status = 'approved'
           and exists (select 1 from public.terminal_charge_holds h
                        where h.payment_transaction_id = t.payment_transaction_id)
           and public.charge_hold_is_live(t.payment_transaction_id))
     )
   order by t.created_at;
$function$;

revoke all on function public.charge_hold_is_live(uuid) from public, anon;
grant execute on function public.charge_hold_is_live(uuid) to authenticated, service_role;
revoke all on function public.order_live_hold_cents(text[]) from public, anon;
grant execute on function public.order_live_hold_cents(text[]) to authenticated, service_role;
revoke all on function public.stuck_card_charges(text) from public, anon;
grant execute on function public.stuck_card_charges(text) to authenticated, service_role;

create or replace function public.reserve_order_charge(
  p_order_id text,
  p_amount_cents bigint,
  p_idempotency_key text,
  p_provider text,
  p_platform_fee_cents bigint default 0,
  p_payout_cents bigint default 0
)
returns jsonb
language plpgsql
as $function$
declare
  v_o       record;
  v_mode    text;
  v_cutover date;
  v_tz      text;
  v_today   date;
  v_total   bigint;
  v_held    bigint;
  v_txn_id  uuid;
begin
  if coalesce(p_amount_cents, 0) <= 0 then
    raise exception 'Enter an amount to charge.';
  end if;

  select o.company_id, o.customer_id, o.order_date, o.invoice_number, o.posted,
         o.is_legacy_import, o.is_opening_balance, o.order_status, o.shop_order_ref,
         o.facility_id, o.order_total, o.tax_amount
    into v_o
    from public.orders o
   where o.order_id = p_order_id
     and o.company_id in (select public.auth_company_ids())
     for update;
  if not found then raise exception 'That order could not be found.'; end if;

  if v_o.invoice_number is not null or coalesce(v_o.posted, false) then
    raise exception 'This order already has an invoice. Refresh the page and charge it from there.';
  end if;
  if v_o.shop_order_ref is not null then
    raise exception 'Storefront orders are not invoiced from here.';
  end if;
  if v_o.customer_id is null then
    raise exception 'This order has no customer to invoice.';
  end if;
  if coalesce(v_o.is_legacy_import, false) then
    raise exception 'This order was imported from QuickBooks and keeps its original number.';
  end if;
  if coalesce(v_o.is_opening_balance, false) then
    raise exception 'This is an opening balance from your cutover, not an order to invoice.';
  end if;
  if v_o.order_status = 'Canceled' then
    raise exception 'Canceled orders cannot be charged. Reopen the order first.';
  end if;
  if coalesce(v_o.order_total, 0) <= 0 then
    raise exception 'Add at least one line item with a price before charging.';
  end if;

  select b.invoice_of_record, b.cutover_date into v_mode, v_cutover
    from public.billing_settings b where b.company_id = v_o.company_id;
  if coalesce(v_mode, 'quickbooks') <> 'strata' then
    raise exception 'STRATA is not your invoice of record yet.';
  end if;
  select f.time_zone into v_tz from public.facilities f where f.facility_id = v_o.facility_id;
  v_today := (now() at time zone coalesce(nullif(v_tz, ''), 'UTC'))::date;
  if v_cutover is not null and v_o.order_date is not null
     and v_o.order_date < v_cutover and v_o.order_date < v_today then
    raise exception 'This order is dated before your STRATA start date, so it stays in QuickBooks.';
  end if;

  v_total := round((coalesce(v_o.order_total, 0) + coalesce(v_o.tax_amount, 0)) * 100)::bigint;
  select coalesce(sum(h.amount_cents), 0) into v_held
    from public.terminal_charge_holds h
    join public.payment_transactions t on t.payment_transaction_id = h.payment_transaction_id
   where h.order_id = p_order_id
     and public.charge_hold_is_live(t.payment_transaction_id);
  if v_held + p_amount_cents > v_total then
    raise exception 'Only % can still be charged on this order. Another charge may be in flight.',
      to_char(greatest(v_total - v_held, 0) / 100.0, 'FM999999990.00');
  end if;

  insert into public.payment_transactions
    (company_id, order_id, provider, type, status, idempotency_key,
     gross_amount_cents, platform_fee_cents, roaster_payout_cents)
  values
    (v_o.company_id, p_order_id, p_provider, 'sale', 'pending', p_idempotency_key,
     p_amount_cents, coalesce(p_platform_fee_cents, 0), coalesce(p_payout_cents, 0))
  returning payment_transaction_id into v_txn_id;

  insert into public.terminal_charge_holds (payment_transaction_id, order_id, amount_cents)
  values (v_txn_id, p_order_id, p_amount_cents);

  return jsonb_build_object(
    'payment_transaction_id', v_txn_id,
    'allocations', jsonb_build_array(
      jsonb_build_object('order_id', p_order_id, 'amount_cents', p_amount_cents))
  );
end;
$function$;

revoke all on function public.reserve_order_charge(text, bigint, text, text, bigint, bigint) from public, anon;
grant execute on function public.reserve_order_charge(text, bigint, text, text, bigint, bigint) to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.reserve_terminal_charge(p_order_ids text[], p_amount_cents bigint, p_idempotency_key text, p_provider text, p_platform_fee_cents bigint DEFAULT 0, p_payout_cents bigint DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  v_company    text;
  v_remaining  bigint := p_amount_cents;
  v_txn_id     uuid;
  v_allocs     jsonb := '[]'::jsonb;
  r            record;
  v_take       bigint;
begin
  if coalesce(array_length(p_order_ids, 1), 0) = 0 or coalesce(p_amount_cents, 0) <= 0 then
    raise exception 'nothing to charge';
  end if;

  -- Lock every selected invoice in a deterministic order (no deadlocks), all
  -- company-checked, all collectable — BEFORE any card is touched.
  for r in
    select o.order_id, o.company_id, o.posted, o.invoice_state, o.due_date,
           round((coalesce(o.order_total,0) + coalesce(o.tax_amount,0)) * 100)::bigint as total_cents
      from public.orders o
     where o.order_id = any (p_order_ids)
       and o.company_id in (select public.auth_company_ids())
     order by o.order_id
     for update
  loop
    if v_company is null then v_company := r.company_id;
    elsif v_company <> r.company_id then raise exception 'invoices span companies'; end if;
    if not coalesce(r.posted, false)
       or r.invoice_state is null
       or r.invoice_state in ('void', 'draft', 'written_off') then
      raise exception 'invoice % is not collectable (%)', r.order_id,
        coalesce(r.invoice_state, 'not issued');
    end if;
  end loop;
  if v_company is null then raise exception 'invoice not found'; end if;

  insert into public.payment_transactions
    (company_id, order_id, provider, type, status, idempotency_key,
     gross_amount_cents, platform_fee_cents, roaster_payout_cents)
  values
    (v_company, p_order_ids[1], p_provider, 'sale', 'pending', p_idempotency_key,
     p_amount_cents, coalesce(p_platform_fee_cents, 0), coalesce(p_payout_cents, 0))
  returning payment_transaction_id into v_txn_id;

  -- Split oldest-due-first across what each invoice can still take —
  -- committed ledger minus other LIVE holds.
  for r in
    select o.order_id, o.due_date,
           greatest(0,
             round((coalesce(o.order_total,0) + coalesce(o.tax_amount,0)) * 100)::bigint
             - coalesce((select sum(a.amount_cents)
                           from public.invoice_payment_allocations a
                           join public.invoice_payments p on p.payment_id = a.payment_id
                          where a.order_id = o.order_id and p.voided_at is null), 0)
             - coalesce((select sum(amount_cents) from public.credit_memos
                          where applied_to_order_id = o.order_id and voided_at is null), 0)
             - coalesce((select sum(h.amount_cents)
                           from public.terminal_charge_holds h
                           join public.payment_transactions t on t.payment_transaction_id = h.payment_transaction_id
                          where h.order_id = o.order_id
                            and public.charge_hold_is_live(t.payment_transaction_id)
                            and t.payment_transaction_id <> v_txn_id), 0)
           ) as available_cents
      from public.orders o
     where o.order_id = any (p_order_ids)
     order by o.due_date nulls last, o.order_id
  loop
    exit when v_remaining <= 0;
    v_take := least(v_remaining, r.available_cents);
    if v_take > 0 then
      insert into public.terminal_charge_holds (payment_transaction_id, order_id, amount_cents)
      values (v_txn_id, r.order_id, v_take);
      v_allocs := v_allocs || jsonb_build_object('order_id', r.order_id, 'amount_cents', v_take);
      v_remaining := v_remaining - v_take;
    end if;
  end loop;

  if v_remaining > 0 then
    raise exception 'only % cents remain chargeable across those invoices (another charge may be in flight)',
      p_amount_cents - v_remaining;
  end if;

  return jsonb_build_object('payment_transaction_id', v_txn_id, 'allocations', v_allocs);
end;
$function$;
