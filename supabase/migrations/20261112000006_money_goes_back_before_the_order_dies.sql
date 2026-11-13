-- Money goes back before the order dies.
--
-- Owner: "if a paid order is voided/cancel we have to have a flow for that too.
-- a refund would need to be forced before void/cancel if the payment was done
-- through strata. if its just a manually recorded payment (check selected etc)
-- then no refund needed."
--
-- 🔴 IT HAS ALREADY HAPPENED ONCE. One prod order is Canceled with $360 still
-- sitting at the gateway: the order is dead, the invoice is gone from A/R, and
-- the customer's bank still has their money with nothing on any screen saying
-- so. 30 live orders currently hold $12,669.83 that this protects.
--
-- WHY THE RULE FALLS OUT OF THE MONEY RATHER THAN BEING IMPOSED ON IT.
-- A hand-entered payment -- a cheque, cash, a card run on the countertop
-- machine -- is money that never passed through us, so there is no
-- payment_transactions row and nothing for STRATA to send back; the roaster
-- hands it over themselves. A payment taken here (online or charged by staff)
-- carries a gateway transaction, and the gateway is holding the money. So
-- "did this go through STRATA?" is answered by asking the gateway's own
-- ledger, not by reading a label off the payment. Sum sale minus refund for
-- the order: above zero means their bank still has it.
--
-- IN THE DATABASE, NOT ONLY IN voidInvoice. That action already refuses a paid
-- invoice, but order_status has no permission gate and no transition guard
-- (0 check constraints and 0 RLS policies mention it, measured), so the status
-- dropdown, a bulk update or a raw PostgREST call all reach Canceled without
-- passing it. A guard the UI can walk around is a hint.
--
-- The same action is also WRONGER than this rule in the other direction: it
-- refuses every paid invoice with "issue a credit memo instead", including one
-- paid by cheque, which by the rule above should simply void. That half is
-- fixed in the app, where the message lives.

begin;

create or replace function public.guard_void_needs_refund()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_cents bigint;
begin
  -- The gateway's own arithmetic. A voided sale (status 'voided') and a
  -- declined one contribute nothing, which is correct: neither is holding
  -- money. A hand-entered payment has no row here at all.
  select coalesce(sum(case
           when t.type = 'sale'   and t.status = 'approved' then  t.gross_amount_cents
           when t.type = 'refund' and t.status = 'approved' then -t.gross_amount_cents
           else 0 end), 0)
    into v_cents
    from public.payment_transactions t
   where t.order_id = NEW.order_id;

  if v_cents > 0 then
    raise exception 'This order was paid through STRATA and $% is still with the customer''s bank. Refund that payment first, then cancel or void the order. (Money you recorded by hand — a cheque or cash — never blocks this: give it back yourself.)',
      to_char(v_cents / 100.0, 'FM999999990.00');
  end if;

  return NEW;
end
$fn$;

comment on function public.guard_void_needs_refund() is
  'Refuses to cancel or void an order while the payment gateway still holds the customer''s money. Hand-entered payments carry no gateway transaction and never block, by instruction: that money never passed through us. Lives here and not only in voidInvoice because order_status has no permission gate and no transition guard, so the status dropdown reaches Canceled without passing the action.';

-- Sorts before zy_stamp_document_closed, so an order that is refused here is
-- never stamped closed on the way out.
drop trigger if exists zx_guard_void_needs_refund on public.orders;
create trigger zx_guard_void_needs_refund
  before update on public.orders
  for each row
  when (
       (NEW.order_status  = 'Canceled' and OLD.order_status  is distinct from 'Canceled')
    or (NEW.voided_at     is not null  and OLD.voided_at     is null)
    or (NEW.invoice_state = 'void'     and OLD.invoice_state is distinct from 'void')
  )
  execute function public.guard_void_needs_refund();

do $$
declare v_n integer; v_cents bigint;
begin
  if not exists (select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
                  where c.relname = 'orders' and t.tgname = 'zx_guard_void_needs_refund') then
    raise exception 'the void guard is not on orders';
  end if;

  -- It has to fire before the close stamp, or a refused void still stamps.
  if 'zx_guard_void_needs_refund' >= 'zy_stamp_document_closed' then
    raise exception 'the void guard no longer fires before the close stamp';
  end if;

  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'guard_void_needs_refund'
                    and p.prosrc like '%payment_transactions%') then
    raise exception 'the void guard does not read the gateway ledger';
  end if;

  -- Already-dead orders are reported, not repaired: sending money back is a
  -- decision with a customer on the other end of it, not a migration.
  with out as (
    select t.order_id,
           sum(case when t.type = 'sale'   and t.status = 'approved' then  t.gross_amount_cents
                    when t.type = 'refund' and t.status = 'approved' then -t.gross_amount_cents
                    else 0 end) as cents
      from public.payment_transactions t group by t.order_id)
  select count(*), coalesce(sum(out.cents), 0) into v_n, v_cents
    from public.orders o join out on out.order_id = o.order_id
   where out.cents > 0
     and (o.order_status = 'Canceled' or o.voided_at is not null or o.invoice_state = 'void');
  if v_n > 0 then
    raise notice 'STRANDED: % order(s) are already canceled or void with $% still at the gateway. They predate this guard and need a refund by hand.',
      v_n, to_char(v_cents / 100.0, 'FM999999990.00');
  end if;
end $$;

commit;
