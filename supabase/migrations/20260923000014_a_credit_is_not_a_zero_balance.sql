-- A customer in credit is not a customer who owes nothing.
--
-- invoice_ar_balances clamped every balance at zero:
--
--   GREATEST(total_cents - paid_cents - credit_cents, 0) AS balance_due_cents
--
-- That is correct for "how much can be collected against this invoice" -- you
-- cannot collect a negative -- and it is the only column the view offered, so
-- every reader inherited the clamp whether or not it wanted it.
--
-- The result on live MCR data:
--
--   Maui Memorial ER   holds a $1,000.00 credit (a QuickBooks credit brought
--                      across as an order with order_total -1000.00)
--                      STRATA shows:  $272.50 owed, all 91+ days overdue
--                      Truth:        -$727.50, i.e. MCR owes THEM
--   My Titas Cafe      shown $6,157.92, true $5,730.29
--   Company A/R        shown $168,865.50, true $167,437.87
--
-- And it is worse than a wrong report. The storefront Pay page selects
-- balances with .gt('balance_due_cents', 0), so Maui Memorial ER is shown a
-- Pay button for $272.50 they do not owe, and the card flow would take it.
--
-- WHAT THIS CHANGES. balance_due_cents keeps its clamp, because the three
-- places that read it -- the Pay page, the record-payment maximum and the
-- credit-memo maximum -- all mean "collectable" and all filter or cap on it
-- being positive. A new signed column carries the truth for anything stating
-- a POSITION rather than a collection: aging, the A/R total, a customer's
-- balance.
--
-- Two columns because they are two different questions, and collapsing them is
-- what caused this. Nothing is inferred and nothing is netted here -- a credit
-- and an invoice stay separate rows; the caller decides whether to sum them.

begin;

create or replace view public.invoice_ar_balances
with (security_invoker = true)
as
 SELECT o.company_id,
    o.order_id,
    o.customer_id,
    o.invoice_number,
    o.invoice_state,
    o.due_date,
    round((COALESCE(o.order_total, 0::numeric) + COALESCE(o.tax_amount, 0::numeric)) * 100::numeric)::bigint AS total_cents,
    COALESCE(pa.paid_cents, 0::numeric) + COALESCE(cm.credit_cents, 0::numeric) AS paid_cents,
    -- COLLECTABLE. Clamped on purpose: you cannot take money against a credit.
    -- Read by the Pay page, the record-payment cap and the credit-memo cap.
    GREATEST(round((COALESCE(o.order_total, 0::numeric) + COALESCE(o.tax_amount, 0::numeric)) * 100::numeric)::bigint::numeric - COALESCE(pa.paid_cents, 0::numeric) - COALESCE(cm.credit_cents, 0::numeric), 0::numeric) AS balance_due_cents,
    o.aging_excluded,
    -- THE POSITION. Signed, never clamped. Negative means the customer is in
    -- credit. Read by aging, the A/R total and anything stating what a
    -- customer's account actually stands at.
    --
    -- Appended rather than placed beside balance_due_cents because CREATE OR
    -- REPLACE VIEW cannot insert a column in the middle -- it can only add to
    -- the end.
    round((COALESCE(o.order_total, 0::numeric) + COALESCE(o.tax_amount, 0::numeric)) * 100::numeric)::bigint::numeric
      - COALESCE(pa.paid_cents, 0::numeric) - COALESCE(cm.credit_cents, 0::numeric) AS net_balance_cents
   FROM orders o
     LEFT JOIN ( SELECT a.order_id,
            sum(a.amount_cents) AS paid_cents
           FROM invoice_payment_allocations a
             JOIN invoice_payments p ON p.payment_id = a.payment_id AND p.voided_at IS NULL
          GROUP BY a.order_id) pa ON pa.order_id = o.order_id
     LEFT JOIN ( SELECT credit_memos.applied_to_order_id AS order_id,
            sum(credit_memos.amount_cents) AS credit_cents
           FROM credit_memos
          WHERE credit_memos.applied_to_order_id IS NOT NULL AND credit_memos.voided_at IS NULL
          GROUP BY credit_memos.applied_to_order_id) cm ON cm.order_id = o.order_id
  WHERE o.posted AND o.invoice_state IS NOT NULL;

comment on view public.invoice_ar_balances is
  'One row per posted invoice. balance_due_cents is what can still be COLLECTED (clamped at zero). net_balance_cents is the signed POSITION -- negative means the customer is in credit. Use the first to take money, the second to state a balance.';

do $$
declare
  v_shown  numeric;
  v_true   numeric;
begin
  -- The view must be readable and the two columns must actually differ where a
  -- credit exists, or this migration changed nothing.
  select sum(balance_due_cents), sum(net_balance_cents) into v_shown, v_true
  from public.invoice_ar_balances where company_id = '9ShiyDAXhV';

  if v_shown is null then
    raise notice 'no MCR invoices on this database, skipping the reconciliation check';
  elsif v_shown = v_true then
    raise notice 'no credits present: collectable and net agree at %', v_shown;
  else
    raise notice 'MCR collectable % vs true position % (difference %)',
      v_shown, v_true, v_shown - v_true;
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='invoice_ar_balances'
      and column_name='net_balance_cents'
  ) then
    raise exception 'net_balance_cents was not added';
  end if;
end $$;

commit;
