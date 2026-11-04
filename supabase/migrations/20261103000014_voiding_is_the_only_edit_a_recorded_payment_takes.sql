-- Voiding is the one edit a recorded payment takes, and a payment with nothing applied
-- can be taken back by whoever wrote it a moment ago.
--
-- The first of two: 20261103000015 takes DELETE and the allocation writes off
-- payment.record, and the frontend has to land in between. See the order below.
--
-- 🔴 invoice.void COULD REWRITE THE WHOLE ROW. invoice_payments_update asks the key, but
-- a policy picks rows and has no way to pick columns, and the table-wide grant let the
-- key send anything over raw REST. voidPayment sends voided_at and nothing else. So
-- amount_cents, received_date, customer_id and the rest could change with no trail and
-- no recompute, and the function below could be walked straight past: it trusts
-- created_by, created_at and payment_transaction_id. Rehearsed on staging as
-- company_admin against a card payment three days old from someone else, unallocated:
-- the function refused, UPDATE set those three to me, now and null, the function then
-- removed it. That is the one row it exists to leave alone. Narrowed to the one column,
-- the same move 20260908000034 made on team. A column grant is checked before RLS, so
-- this refuses out loud rather than touching no rows.
--
-- The admin client keeps the table-wide grant. The webhook's refund fan-out shrinks
-- amount_cents, and it runs as service_role, which holds its own.
--
-- 🔴 AND A VOID GOES ONE WAY. With only the grant the key could still clear voided_at,
-- which puts a payment back in the balance with no recompute and un-voids a row for the
-- function below. USING says the row is not voided yet and WITH CHECK says it is now, so
-- the only move left is the void itself. A second void of the same row touches nothing,
-- and voidPayment still answers ok. FOR UPDATE reads this policy too, and the only
-- caller that locks these rows, guard_allocation_not_overapplied, runs as its owner.
--
-- 🔴 THE ORDER, AND WHY IT IS TWO FILES.
--   1. This file. The frontend already live carries on untouched: its void sends only
--      voided_at, and its rollback's DELETE still has a policy.
--   2. The frontend that calls remove_unapplied_payment, which does not exist before 1.
--   3. 20261103000015, once 2 is live on prod and not a moment before.
-- As one file this had a window that lasted until the manual promote. The old frontend
-- allocates row by row and rolls back with .delete(), which with no policy touches no
-- rows and reports no error. On a two-invoice payment the first allocation lands and the
-- second is refused, so the first invoice's balance has dropped with its invoice_state
-- stale, a full-amount payment stands, and the operator, told only of the refusal,
-- enters it again.

revoke update on public.invoice_payments from authenticated;
grant update (voided_at) on public.invoice_payments to authenticated;

alter policy invoice_payments_update on public.invoice_payments
  using (
    company_id in (select public.auth_company_ids())
    and public.auth_has_permission('invoice.void', company_id)
    and voided_at is null
  )
  with check (
    company_id in (select public.auth_company_ids())
    and public.auth_has_permission('invoice.void', company_id)
    and voided_at is not null
  );

-- The one thing the DELETE was for: taking back a payment recordPayment wrote a moment
-- ago, when its allocations were refused. Each test closes a way of reaching a row that
-- matters, and a row past all of them has never touched an invoice:
--
--   no allocations      the whole point. Its allocations went in one statement, so a
--                       refusal leaves none. An applied payment is voided instead.
--   by this caller      nobody takes back somebody else's entry.
--   moments ago         five minutes is far past one PostgREST call under the 8s
--                       statement timeout and leaves no route to an old row. Both
--                       sides are tested because created_at is the client's to send
--                       on insert, and a future date would otherwise hold it open.
--   no card behind it   chargeAndRecord and the pay page write this same row after the
--                       card is taken. If the allocation then fails, the row is the
--                       only ledger record of real money, and it stays.
--   not voided          a void is history, and history stays.
--
-- FOR UPDATE is the lock guard_allocation_not_overapplied takes, and an allocation
-- insert also holds a key share on this row until it commits. So an insert in flight
-- is waited for and then seen by the check below it, and one that arrives later waits
-- here and fails on the missing payment.
--
-- Nothing read here can be rewritten after the insert, only voided_at set, which makes
-- this refuse. That is the narrowed grant above doing it: without it these tests are a
-- form to fill in.
--
-- Definer, so the tenancy and the key are written out: this runs past RLS. The refusals
-- reach the operator through recordPayment, so they read as sentences.
create or replace function public.remove_unapplied_payment(p_payment_id text)
 returns void
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_payment public.invoice_payments%rowtype;
begin
  select * into v_payment
    from public.invoice_payments
   where payment_id = p_payment_id
     for update;

  -- One message for missing and for another company's: this must not say which.
  if not found or v_payment.company_id not in (select public.auth_company_ids()) then
    raise exception 'That payment could not be found.' using errcode = 'no_data_found';
  end if;

  if not public.auth_has_permission('payment.record', v_payment.company_id) then
    raise exception 'You do not have permission to remove this payment.'
      using errcode = 'insufficient_privilege';
  end if;

  if v_payment.created_by is distinct from auth.uid()::text then
    raise exception 'That payment was recorded by someone else, so it has to be voided instead.'
      using errcode = 'insufficient_privilege';
  end if;

  if v_payment.created_at not between now() - interval '5 minutes' and now() then
    raise exception 'That payment was not recorded just now, so it has to be voided instead.'
      using errcode = 'check_violation';
  end if;

  if v_payment.payment_transaction_id is not null then
    raise exception 'That payment came through the card processor, so it cannot be removed.'
      using errcode = 'check_violation';
  end if;

  if v_payment.voided_at is not null then
    raise exception 'That payment has been voided, and a voided payment stays on the record.'
      using errcode = 'check_violation';
  end if;

  if exists (select 1 from public.invoice_payment_allocations a where a.payment_id = p_payment_id) then
    raise exception 'That payment has been applied to an invoice, so it has to be voided instead.'
      using errcode = 'check_violation';
  end if;

  delete from public.invoice_payments where payment_id = p_payment_id;
end;
$function$;

revoke all on function public.remove_unapplied_payment(text) from public, anon;
grant execute on function public.remove_unapplied_payment(text) to authenticated;
