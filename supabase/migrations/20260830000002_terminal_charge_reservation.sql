-- The terminal's ceiling check becomes atomic.
--
-- The review's P1: two operators charging the same invoice concurrently both
-- read the same balance, both pass the app-side ceiling, and BOTH cards
-- capture at the gateway — over-collection the DB guards can only convert
-- into a refund errand afterwards. The fix is a reservation: the pending
-- payment_transactions row (which the terminal already writes before the
-- gateway call) becomes a HOLD, and this function creates it atomically —
-- order locked, balance recomputed from committed ledger rows MINUS other
-- live holds, state checked against the same non-collectable list the
-- allocation guard enforces — so the second operator is refused BEFORE any
-- card is charged.

begin;

create or replace function public.reserve_terminal_charge(
  p_order_id        text,
  p_amount_cents    bigint,
  p_idempotency_key text,
  p_provider        text,
  p_platform_fee_cents bigint default 0,
  p_payout_cents       bigint default 0
)
returns uuid
language plpgsql
as $function$
declare
  v_order        record;
  v_paid_cents   bigint;
  v_held_cents   bigint;
  v_balance      bigint;
  v_txn_id       uuid;
begin
  if p_order_id is null or coalesce(p_amount_cents, 0) <= 0 then
    raise exception 'nothing to charge';
  end if;

  -- Serialize on the invoice: the second concurrent reservation waits here
  -- and then sees the first one's hold.
  select o.order_id, o.company_id, o.posted, o.invoice_state,
         round((coalesce(o.order_total,0) + coalesce(o.tax_amount,0)) * 100)::bigint as total_cents
    into v_order
    from public.orders o
   where o.order_id = p_order_id
     and o.company_id in (select public.auth_company_ids())
   for update;
  if not found then raise exception 'invoice not found'; end if;

  -- The allocation guard's non-collectable list, enforced BEFORE the card is
  -- charged instead of after (review P2: written-off invoices charged first,
  -- refused second).
  if not coalesce(v_order.posted, false)
     or v_order.invoice_state is null
     or v_order.invoice_state in ('void', 'draft', 'written_off') then
    raise exception 'invoice % is not collectable (%)', p_order_id,
      coalesce(v_order.invoice_state, 'not issued');
  end if;

  select coalesce(sum(a.amount_cents), 0) into v_paid_cents
    from public.invoice_payment_allocations a
    join public.invoice_payments p on p.payment_id = a.payment_id
   where a.order_id = p_order_id and p.voided_at is null;
  v_paid_cents := v_paid_cents + coalesce((select sum(amount_cents)
    from public.credit_memos
   where applied_to_order_id = p_order_id and voided_at is null), 0);

  -- Live holds: pending terminal sales for this order that haven't resolved.
  select coalesce(sum(t.gross_amount_cents), 0) into v_held_cents
    from public.payment_transactions t
   where t.order_id = p_order_id
     and t.type = 'sale'
     and t.status = 'pending';

  v_balance := greatest(0, v_order.total_cents - v_paid_cents - v_held_cents);
  if p_amount_cents > v_balance then
    raise exception 'only % cents remain chargeable on this invoice (another charge may be in flight)', v_balance;
  end if;

  insert into public.payment_transactions
    (company_id, order_id, provider, type, status, idempotency_key,
     gross_amount_cents, platform_fee_cents, roaster_payout_cents)
  values
    (v_order.company_id, p_order_id, p_provider, 'sale', 'pending', p_idempotency_key,
     p_amount_cents, coalesce(p_platform_fee_cents, 0), coalesce(p_payout_cents, 0))
  returning payment_transaction_id into v_txn_id;

  return v_txn_id;
end;
$function$;

commit;

notify pgrst, 'reload schema';
