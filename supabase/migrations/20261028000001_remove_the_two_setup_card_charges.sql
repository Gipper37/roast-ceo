-- Remove the two card charges that were never real money.
--
-- Maui Coffee Roasters' Card sales page reads "Collected $827.32". No customer
-- has ever paid them by card through STRATA. Both rows behind that number are
-- the sandbox charges from the four month incident: production was pointed at
-- sandbox.activitypaygateway.co, the gateway approved them, the invoice was
-- stamped paid, and nothing arrived in anybody's bank.
--
-- Owner, 2026-10-27, on being shown it: "we don't need sandbox data" and "that
-- was just for setting the strata app up. we're live now."
--
-- ── Why this is a delete and not an environment column ───────────────────
--
-- The obvious durable fix is to stamp every charge with the gateway it was
-- taken on and filter the roaster-facing totals. It would be defending against
-- a bug that is already fixed: lib/payments/providers/apEnv.ts now REFUSES an
-- environment it cannot name instead of defaulting to sandbox, and preview
-- deployments are forced to sandbox while pointing at the STAGING database, so
-- a sandbox charge has no route into this table any more. These two are
-- wreckage from a specific incident, not a category that will recur.
--
-- ── What is deleted, and what is voided instead ──────────────────────────
--
-- Deleting the payments alone would make it WORSE. Both invoices sit at
-- balance_due_cents = 0 because these payments pay them off; remove the
-- payments and two canceled orders start owing $827.32 between them. So the
-- invoices are voided in the same breath: a posted invoice on a canceled order
-- whose payment never existed is exactly what void is for, and a voided
-- invoice is out of A/R rather than overdue in it.
--
-- Both orders are already Canceled, both invoices are INV-000001 and
-- INV-000002 -- the first two ever issued, from standing the app up. Nothing
-- else references the rows: chargebacks 0, terminal_charge_holds 0, checked on
-- production before writing this.

begin;

-- Named explicitly. A WHERE clause that matched "sandbox-looking" rows by
-- date or by settled=false would be a rule, and a rule can match a real charge
-- that has simply not settled yet -- which, on the day this ships, is what
-- every genuine charge will look like for its first day or two.
create temporary table _setup_charges (payment_transaction_id uuid primary key) on commit drop;
insert into _setup_charges values
  ('617d4d5d-ea61-4732-88db-4ca87e36b65e'),   -- $27.32, order 3376, INV-000002
  ('45eea2ba-8e02-4b1d-8719-1396e388310a');   -- $800.00, order 3375, INV-000001

do $$
declare
  n_found   int;
  n_live    int;
  n_other   int;
begin
  select count(*) into n_found
    from public.payment_transactions pt join _setup_charges s using (payment_transaction_id);

  -- 🔴 ABSENT IS NOT A FAULT. These two rows exist on production and nowhere
  -- else, so on staging -- and on any database restored after this has already
  -- run -- there is simply nothing to clean. Raising here is what failed CI on
  -- the area backfill this morning: an assertion that cannot pass on staging
  -- destroys the rehearsal it is supposed to be part of. Say so and stop.
  if n_found = 0 then
    raise notice 'neither setup charge is present here; nothing to clean';
    return;
  end if;

  -- 🔴 Refuse if either one is attached to an order that is not Canceled. If
  -- somebody has reopened one of these since this was written, the assumption
  -- this migration rests on is gone and a human should look.
  select count(*) into n_live
    from public.payment_transactions pt
    join _setup_charges s using (payment_transaction_id)
    join public.orders o on o.order_id = pt.order_id
   where coalesce(o.order_status, '') <> 'Canceled';
  if n_live > 0 then
    raise exception
      '% of the setup charges are on an order that is no longer Canceled; do not delete them blind', n_live;
  end if;

  -- And refuse if MCR has taken a charge that is NOT one of these two, because
  -- then the company is live and deleting by hand is the wrong instrument.
  select count(*) into n_other
    from public.payment_transactions pt
   where pt.company_id = '9ShiyDAXhV'
     and pt.payment_transaction_id not in (select payment_transaction_id from _setup_charges);
  if n_other > 0 then
    raise exception
      'MCR has % card charge(s) besides the two setup ones; stop and look before deleting anything', n_other;
  end if;
end $$;

-- The A/R side first, so no moment exists where a posted invoice is unpaid and
-- not yet void.
update public.orders o
   set invoice_state = 'void',
       updated_at    = now(),
       updated_by    = 'setup-charge-cleanup-20261028'
  from public.payment_transactions pt
  join _setup_charges s using (payment_transaction_id)
 where o.order_id = pt.order_id
   and o.invoice_state is distinct from 'void';

delete from public.invoice_payments
 where payment_transaction_id in (select payment_transaction_id from _setup_charges);

delete from public.payment_transactions
 where payment_transaction_id in (select payment_transaction_id from _setup_charges);

do $$
declare
  n_left  int;
  n_owed  int;
begin
  select count(*) into n_left
    from public.payment_transactions
   where company_id = '9ShiyDAXhV'
     and payment_transaction_id in (
       '617d4d5d-ea61-4732-88db-4ca87e36b65e', '45eea2ba-8e02-4b1d-8719-1396e388310a');
  if n_left <> 0 then
    raise exception '% setup charge(s) survived the delete', n_left;
  end if;

  -- The thing this migration exists to prevent: a canceled setup order left
  -- owing money because its payment was removed and its invoice was not voided.
  select count(*) into n_owed
    from public.orders
   where company_id = '9ShiyDAXhV'
     and order_number in (3375, 3376)
     and invoice_state is not null
     and invoice_state <> 'void';
  if n_owed > 0 then
    raise exception '% setup invoice(s) are not void and would now read as unpaid', n_owed;
  end if;

  raise notice 'MCR card charges: 0. Both setup invoices voided. Card sales now reads nothing collected, which is true.';
end $$;

commit;
