-- A returned payment is not a voided one.
--
-- An ACH debit can come back days after we were told it was accepted. The
-- gateway says so with a `transaction_update` webhook whose status is
-- `returned` ("Transaction returned") or `late_return` ("Late ACH return").
-- Neither word is sayable here. Both status columns constrain to a list that
-- stops at 'voided':
--
--     payment_transactions.status   pending, approved, declined, failed, voided
--     orders.payment_status         null, pending, authorized, captured,
--                                   failed, refunded, partially_refunded, voided
--
-- So a return handler has exactly two options today and both of them lie:
-- write 'voided' and the money looks like it never moved, or write nothing and
-- the order still reads as paid.
--
-- 'voided' is the wrong word deliberately, not by accident. A void means the
-- charge was pulled before it ever settled: nothing to collect, nobody to
-- call. A return means the money did move, landed, and then the bank took it
-- back out, which means the coffee has already shipped and somebody has to go
-- chase the customer. Those are opposite instructions to the person reading
-- the order list, and one shared word makes them indistinguishable.
--
-- Both gateway statuses map onto the single value 'returned'. `late_return`
-- describes WHEN the bank reversed it, after the normal return window, not
-- what became of the money, and the exact gateway word stays in the stored
-- webhook payload for anyone who needs that detail. One domain word per
-- outcome, so no query has to remember to look for two synonyms.
--
-- ── A new word is only real once the readers know it ──────────────────────
--
-- Widening a CHECK makes a value WRITABLE. It teaches nothing to anything that
-- READS the column, and the first draft of this header reasoned only about
-- writers ("no query has to remember to look for two synonyms") without ever
-- enumerating who reads orders.payment_status. The writer ships in this same
-- release: app/api/webhooks/activitypay/route.ts:1052 sets payment_status to
-- reversal.kind with no status filter, because a return outranks whatever was
-- there. Every reader that pattern-matches the column has to carry 'returned'
-- as well, or the buyer is told the opposite of what happened:
--
--   app/(shop)/[slug]/orderDisplayState.ts, SETTLED_PAYMENT_STATUSES and
--     badgeFor(). An unrecognised value falls to the unsettled branch by
--     design, so a returned ACH debit shows "Payment not confirmed" and tells
--     the buyer the roaster is waiting on the bank and not to enter their card
--     again, while the bank has in fact taken the money back out and the
--     invoice is owed again.
--   app/(shop)/[slug]/orders/OrdersHistory.tsx:91-92, where isPaid is
--     'captured' or 'authorized' and isInvoiced is a null payment_status. So
--     'returned' is neither, and the row offers a Pay button against the
--     invoice this same reversal just reopened.
--
-- Those live in the frontend repo and are not changed by this file. They are
-- named here so that the next person widening a status column starts from the
-- reader list instead of from the constraint.
--
-- A CHECK cannot be altered in place, so each constraint is dropped and
-- rebuilt with its full value list. Both new lists are supersets of the ones
-- they replace, so the rebuild cannot fail validation on existing rows:
-- everything the old constraint admitted, the new one still admits. Nothing
-- else is widened, and the verify block below counts the values to prove it.

begin;

-- What the gateway told us about one attempt on the money.
alter table public.payment_transactions
  drop constraint if exists payment_transactions_status_chk;

alter table public.payment_transactions
  add constraint payment_transactions_status_chk
  check (status in ('pending', 'approved', 'declined', 'failed', 'voided', 'returned'));

-- Where the money for this order stands right now.
alter table public.orders
  drop constraint if exists orders_payment_status_chk;

alter table public.orders
  add constraint orders_payment_status_chk
  check (payment_status is null
         or payment_status in ('pending', 'authorized', 'captured', 'failed',
                               'refunded', 'partially_refunded', 'voided', 'returned'));

do $verify$
declare
  v_def   text;
  v_word  text;
  v_count int;
begin
  -- Both constraints are checked by reading the catalog rather than by
  -- inserting a probe row and rolling it back. This is the money ledger: a
  -- test row that a failed rollback left behind would be a phantom payment,
  -- and proving a CHECK admits a word does not require writing the word.

  select pg_get_constraintdef(oid) into v_def
    from pg_constraint
   where conname = 'payment_transactions_status_chk'
     and conrelid = 'public.payment_transactions'::regclass;
  if v_def is null then
    raise exception 'payment_transactions_status_chk is missing after the rebuild';
  end if;
  foreach v_word in array array['pending', 'approved', 'declined', 'failed', 'voided', 'returned'] loop
    if v_def not like '%''' || v_word || '''%' then
      raise exception 'payment_transactions.status no longer admits %', v_word;
    end if;
  end loop;
  -- Exactly six values, so the rebuild neither dropped one of the five that
  -- were there nor quietly let a sixth idea in alongside 'returned'.
  select count(*) into v_count from regexp_matches(v_def, '''[a-z_]+''', 'g');
  if v_count <> 6 then
    raise exception 'payment_transactions.status admits % values, expected 6: %', v_count, v_def;
  end if;

  select pg_get_constraintdef(oid) into v_def
    from pg_constraint
   where conname = 'orders_payment_status_chk'
     and conrelid = 'public.orders'::regclass;
  if v_def is null then
    raise exception 'orders_payment_status_chk is missing after the rebuild';
  end if;
  foreach v_word in array array['pending', 'authorized', 'captured', 'failed',
                                'refunded', 'partially_refunded', 'voided', 'returned'] loop
    if v_def not like '%''' || v_word || '''%' then
      raise exception 'orders.payment_status no longer admits %', v_word;
    end if;
  end loop;
  select count(*) into v_count from regexp_matches(v_def, '''[a-z_]+''', 'g');
  if v_count <> 8 then
    raise exception 'orders.payment_status admits % values, expected 8: %', v_count, v_def;
  end if;

  -- And null still means "no money has been asked for on this order", which is
  -- what 15,422 of them say.
  if v_def not like '%IS NULL%' then
    raise exception 'orders.payment_status no longer admits null';
  end if;

  raise notice 'a return is now sayable on both sides, and is not the same word as a void';
end
$verify$;

commit;
