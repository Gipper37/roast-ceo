-- The terminal charges several invoices at once.
--
-- One card charge, split oldest-due-first across the invoices the operator
-- ticked. The reservation keeps its guarantees per INVOICE, so holds get a
-- home of their own: terminal_charge_holds rows (one per invoice per pending
-- charge) that release the moment the transaction leaves 'pending'. The
-- single-order reserve_terminal_charge is replaced by the array form —
-- an array of one is the single-invoice case.

begin;

create table if not exists public.terminal_charge_holds (
  payment_transaction_id uuid not null references public.payment_transactions (payment_transaction_id) on delete cascade,
  order_id               text not null references public.orders (order_id) on delete cascade,
  amount_cents           bigint not null check (amount_cents > 0),
  primary key (payment_transaction_id, order_id)
);

alter table public.terminal_charge_holds enable row level security;
do $$ begin
  create policy tenant_company_access on public.terminal_charge_holds
    for all using (
      payment_transaction_id in (
        select payment_transaction_id from public.payment_transactions
        where company_id in (select public.auth_company_ids())
      )
    );
exception when duplicate_object then null; end $$;

drop function if exists public.reserve_terminal_charge(text, bigint, text, text, bigint, bigint);

create or replace function public.reserve_terminal_charge(
  p_order_ids       text[],
  p_amount_cents    bigint,
  p_idempotency_key text,
  p_provider        text,
  p_platform_fee_cents bigint default 0,
  p_payout_cents       bigint default 0
)
returns jsonb
language plpgsql
as $function$
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
                            and t.status = 'pending'
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

commit;

notify pgrst, 'reload schema';
