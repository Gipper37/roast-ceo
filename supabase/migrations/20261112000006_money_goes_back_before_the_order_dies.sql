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
-- so. 31 live orders hold $12,669.83 that this protects.
--
-- 🔴 THAT FIGURE READ $28,361.26 UNTIL THE ARITHMETIC WAS CHECKED, AND THE
-- EXTRA WAS NOT COVERAGE -- IT WAS THE SAME MONEY COUNTED TWICE. Counting
-- terminal holds beside the allocations they had already become inflated the
-- total to nearly double, and the figure goes into the refusal the roaster
-- reads, to the cent. The per-order arithmetic is still the right one -- it
-- finds one order a per-transaction sum cannot see, because one charge can
-- pay several invoices -- but the gain was one order, not sixteen thousand
-- dollars. A dedup is not a speedup and a bigger number is not more
-- protection: price what REMAINS against what is actually at the gateway.
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

-- 🔴 ONE ARITHMETIC, NOT TWO. The guard below refuses the write; the orders
-- list has to ask the same question BEFORE it writes, because a bulk cancel
-- is a single statement over N orders -- one card-paid order in a selection
-- of twenty aborts all twenty and the refusal reaches the user as a thrown
-- server action, which Next masks in a production build. If the screen's
-- check and the guard's check were written twice they would drift, and the
-- drift would show up as a button that fails or a refusal that never fires.
-- 🔴 THE THREE TERMS MUST BE DISJOINT, AND THE CLAMP GOES ROUND THE WHOLE
-- SUM, NOT ROUND ONE TERM. One charge is visible in three places -- as an
-- allocation once it is filed as a payment, as a terminal hold that says
-- which orders it covers, and as the raw transaction -- so the same dollar
-- is easy to count twice, and a refund clamped inside its own term nets
-- against nothing. Both mistakes were in the first draft of this function:
-- 26 of 31 prod holds name a transaction that is ALREADY a live payment, so
-- it told the roaster to refund roughly double; and five name a DECLINED
-- sale, which would have made two delivered prod orders permanently
-- impossible to cancel, void or delete over money the gateway never took.
--
-- 🔴 charge_hold_is_live IS THE PREDICATE, AND IT ALREADY EXISTED
-- (20261103000007). A hold is live while the charge is unanswered, or
-- approved and not yet filed as an allocated payment -- which is exactly
-- "not already counted by term (a)". Writing the test again here is how the
-- two drift.
--
-- SECURITY INVOKER on purpose. Inside guard_void_needs_refund (which is
-- DEFINER) this runs as the owner and sees everything, so the guard can
-- never be blinded; called as an RPC by the orders list it is bounded by
-- RLS, so a signed-in user cannot read another tenant's amounts -- or learn
-- that one of their order ids exists -- by guessing. Every table it reads is
-- company-scoped and granted to authenticated, so the screen still sees its
-- own tenant whole.
create or replace function public.order_gateway_money_cents(p_order_ids text[])
returns table (order_id text, cents bigint)
language sql
stable
security invoker
set search_path to 'public', 'pg_temp'
as $fn$
  select o.order_id,
         greatest(
           -- (a) card money already filed as a payment and claimed by THIS order.
           coalesce((select sum(a.amount_cents)
                       from public.invoice_payment_allocations a
                       join public.invoice_payments p on p.payment_id = a.payment_id
                      where a.order_id = o.order_id and a.company_id = o.company_id
                        and p.voided_at is null
                        and p.payment_transaction_id is not null), 0)
           -- (b) a charge still standing at the gateway, split per order by its
           --     holds. Dead holds -- declined, or already filed as (a) -- are
           --     not money anyone is holding.
         + coalesce((select sum(h.amount_cents)
                       from public.terminal_charge_holds h
                      where h.order_id = o.order_id
                        and public.charge_hold_is_live(h.payment_transaction_id)), 0)
           -- (c) a charge filed on the order that became neither. Holds are
           --     authoritative about the split, so a charge that has any is
           --     counted there and not again here.
         + coalesce((select sum(t.gross_amount_cents)
                       from public.payment_transactions t
                      where t.order_id = o.order_id and t.company_id = o.company_id
                        and t.type = 'sale'
                        and (t.status in ('approved', 'pending') or t.settled)
                        and not exists (select 1 from public.invoice_payments p2
                                         where p2.payment_transaction_id = t.payment_transaction_id
                                           and p2.voided_at is null)
                        and not exists (select 1 from public.terminal_charge_holds h2
                                         where h2.payment_transaction_id = t.payment_transaction_id)), 0)
           -- (d) less whatever has already gone back. A PARTIAL refund leaves
           --     the payment standing, so this has to net against (a), not be
           --     clamped away inside a term of its own.
         - coalesce((select sum(t.gross_amount_cents)
                       from public.payment_transactions t
                      where t.order_id = o.order_id and t.company_id = o.company_id
                        and t.type = 'refund' and t.status = 'approved'), 0)
         , 0)::bigint
    from public.orders o
   where o.order_id = any(p_order_ids)
$fn$;

comment on function public.order_gateway_money_cents(text[]) is
  'How much of the customer''s money the payment gateway is still holding for each of these orders, net of refunds already made. Measured per ORDER -- live card allocations, plus LIVE terminal holds (charge_hold_is_live), plus any charge filed on the order that became neither -- because one card charge can pay several invoices and payment_transactions.order_id names only the first. The three terms are disjoint on purpose: a hold stops being live the moment its charge is filed as an allocated payment, so nothing is counted twice. Read by guard_void_needs_refund, and by the orders list before a bulk cancel, so the screen and the guard cannot disagree.';

-- 🔴 `revoke from public, anon` does NOT revoke from authenticated, which is
-- why the grant below is the whole access story for a signed-in user. It is
-- safe to give because the function is INVOKER: RLS answers for it.
revoke all on function public.order_gateway_money_cents(text[]) from public, anon;
grant execute on function public.order_gateway_money_cents(text[]) to authenticated;

create or replace function public.guard_void_needs_refund()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_cents bigint; v_order text;
begin
  v_order := coalesce(NEW.order_id, OLD.order_id);

  -- The same arithmetic the orders list asks before it offers the cancel.
  -- See order_gateway_money_cents for why it is per ORDER and why `approved`
  -- alone was never the right test.
  select coalesce(m.cents, 0) into v_cents
    from public.order_gateway_money_cents(array[v_order]) m;

  if coalesce(v_cents, 0) > 0 then
    raise exception 'This order was paid through STRATA and $% is still with the customer''s bank. Refund that payment first, then cancel or void the order. (Money you recorded by hand — a cheque or cash — never blocks this: give it back yourself.)',
      to_char(v_cents / 100.0, 'FM999999990.00');
  end if;

  return coalesce(NEW, OLD);
end
$fn$;

comment on function public.guard_void_needs_refund() is
  'Refuses to cancel, void or DELETE an order while the payment gateway still holds the customer''s money. Measured per ORDER -- live card allocations, plus terminal holds, plus any charge filed on the order that never became a payment -- because one card charge can pay several invoices and payment_transactions.order_id names only the first. Counts a charge as live when it is approved, unanswered, or settled whatever its status says. Hand-entered payments carry no gateway transaction and never block, by instruction: that money never passed through us. Lives here and not only in voidInvoice because order_status has no permission gate and no transition guard, so the status dropdown reaches Canceled without passing the action, and a DELETE passes no action at all.';

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

-- 🔴 AND A DELETE KILLS THE ORDER JUST AS DEAD. orders_delete_needs_permission
-- admits order.cancel OR order.create -- 8 of 11 roles on prod, staff among
-- them -- and the only DELETE guard on orders refuses solely when OLD.posted.
-- Three prod orders are unposted AND holding approved gateway money right now.
-- payment_transactions_order_id_fkey is ON DELETE SET NULL, so the money row
-- would survive with no order to name it, and the stranded report below
-- (which joins orders) could never count it again. The migration's own reason
-- for living in the database -- "a guard the UI can walk around is a hint" --
-- applies with more force here, because a DELETE needs no UI at all.
drop trigger if exists zx_guard_delete_needs_refund on public.orders;
create trigger zx_guard_delete_needs_refund
  before delete on public.orders
  for each row
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

  if not exists (select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
                  where c.relname = 'orders' and t.tgname = 'zx_guard_delete_needs_refund') then
    raise exception 'a DELETE still walks past the void guard';
  end if;

  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'guard_void_needs_refund'
                    and p.prosrc like '%order_gateway_money_cents%') then
    raise exception 'the void guard no longer shares its arithmetic with the screen';
  end if;

  -- Already-dead orders are reported, not repaired: sending money back is a
  -- decision with a customer on the other end of it, not a migration.
  select count(*), coalesce(sum(m.cents), 0) into v_n, v_cents
    from public.orders o
    join public.order_gateway_money_cents(
           array(select order_id from public.orders
                  where order_status = 'Canceled' or voided_at is not null or invoice_state = 'void')) m
      on m.order_id = o.order_id
   where m.cents > 0;
  if v_n > 0 then
    raise notice 'STRANDED: % order(s) are already canceled or void with $% still at the gateway. They predate this guard and need a refund by hand.',
      v_n, to_char(v_cents / 100.0, 'FM999999990.00');
  end if;
end $$;

-- ── Probes that RUN, each rolling itself back ─────────────────────────
-- 🔴 The block above only reads. These two perform the real write and undo
-- it, and they are a PAIR: the case that must be refused and the control that
-- must pass. Without the control, a guard that refused everything would look
-- exactly as green as a guard that works.
do $$
declare v_paid text; v_free text; v_ok boolean;
begin
  -- Must REFUSE: an order the gateway is still holding money for.
  select m.order_id into v_paid
    from public.order_gateway_money_cents(
           array(select order_id from public.orders where order_status <> 'Canceled')) m
   where m.cents > 0
   limit 1;

  if v_paid is null then
    raise warning 'NO CARD-PAID LIVE ORDER ON THIS DATABASE — the refusal is UNPROVEN here, not proven';
  else
    v_ok := false;
    begin
      update public.orders set order_status = 'Canceled' where order_id = v_paid;
    exception when others then
      v_ok := (SQLERRM like '%still with the customer%');
      if not v_ok then
        raise exception 'the cancel was refused for the WRONG reason: %', SQLERRM;
      end if;
    end;
    if not v_ok then
      raise exception 'an order holding gateway money was cancelled without a refund';
    end if;

    -- The same order, deleted rather than cancelled, must be refused too.
    v_ok := false;
    begin
      delete from public.orders where order_id = v_paid;
    exception when others then
      v_ok := (SQLERRM like '%still with the customer%');
    end;
    if not v_ok then
      raise exception 'an order holding gateway money was DELETED without a refund';
    end if;
  end if;

  -- 🔴 THE CONTROL THAT MUST PASS. The owner's rule is that hand-entered
  -- money never blocks. An order with no gateway charge must still cancel,
  -- or this guard has stopped the roastery cancelling anything.
  select o.order_id into v_free
    from public.orders o
   where o.order_status not in ('Canceled')
     and o.voided_at is null
     and not exists (select 1 from public.payment_transactions t where t.order_id = o.order_id)
     and not exists (select 1 from public.invoice_payment_allocations a where a.order_id = o.order_id)
     and not exists (select 1 from public.terminal_charge_holds h where h.order_id = o.order_id)
   limit 1;
  if v_free is null then
    raise warning 'NO GATEWAY-FREE ORDER ON THIS DATABASE — the control is UNPROVEN here';
  else
    begin
      update public.orders set order_status = 'Canceled' where order_id = v_free;
      raise exception 'PROBE_ROLLBACK';
    exception when others then
      if SQLERRM <> 'PROBE_ROLLBACK' then
        raise exception 'an order with NO gateway money could not be cancelled, so this guard blocks everything: %', SQLERRM;
      end if;
    end;
  end if;
end $$;

commit;
