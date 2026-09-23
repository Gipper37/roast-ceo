-- A written-off invoice is not money anybody is going to collect.
--
-- invoice_ar_balances had no term for a write-off, and none for a void
-- either -- it computed a balance from the totals and payments whatever state
-- the invoice was in. So calling writeOffInvoice changed invoice_state and
-- written_off_at and left balance_due_cents exactly where it was.
--
-- The consequences split, which is how it stayed hidden: getCompanyAging
-- filters `.neq(invoice_state, 'void')` so a VOID invoice disappears from the
-- aging report, but a WRITTEN-OFF one passes that filter and keeps its full
-- value in a bucket. Invoice 104705 at $16,565.34 would sit in 31-60 days
-- after being written off, while the register beside it showed it as written
-- off -- the summary and its own drill-down disagreeing.
--
-- Handled in the VIEW rather than in each caller, because there are several
-- and they already disagree. Writing off is the roaster deciding the money is
-- not coming; the ledger should say so in one place.
--
-- Not deleted, not hidden: the row stays, total_cents and paid_cents stay, and
-- the state still says what happened. Only the two BALANCE columns go to zero,
-- because that is the honest answer to "what is still owed".
--
-- Nothing is written off today -- MCR's posted invoices are 201 overdue and 2
-- paid -- so this changes no current figure and closes the hole before the
-- first write-off.

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
    CASE WHEN o.invoice_state = ANY (ARRAY['void'::text, 'written_off'::text]) THEN 0::numeric
         ELSE GREATEST(round((COALESCE(o.order_total, 0::numeric) + COALESCE(o.tax_amount, 0::numeric)) * 100::numeric)::bigint::numeric - COALESCE(pa.paid_cents, 0::numeric) - COALESCE(cm.credit_cents, 0::numeric), 0::numeric)
    END AS balance_due_cents,
    o.aging_excluded,
    -- THE POSITION. Signed, never clamped. Negative means the customer is in
    -- credit. Read by aging, the A/R total and anything stating what a
    -- customer's account actually stands at.
    --
    -- Appended rather than placed beside balance_due_cents because CREATE OR
    -- REPLACE VIEW cannot insert a column in the middle -- it can only add to
    -- the end.
    CASE WHEN o.invoice_state = ANY (ARRAY['void'::text, 'written_off'::text]) THEN 0::numeric
         ELSE round((COALESCE(o.order_total, 0::numeric) + COALESCE(o.tax_amount, 0::numeric)) * 100::numeric)::bigint::numeric
              - COALESCE(pa.paid_cents, 0::numeric) - COALESCE(cm.credit_cents, 0::numeric)
    END AS net_balance_cents
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
  'One row per posted invoice. balance_due_cents is what can still be COLLECTED (clamped at zero, and zero for a void or written-off invoice). net_balance_cents is the signed POSITION -- negative means the customer is in credit. Use the first to take money, the second to state a balance.';

do $$
declare
  v_bad int;
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='invoice_ar_balances'
      and column_name='net_balance_cents'
  ) then
    raise exception 'net_balance_cents was lost in the rewrite';
  end if;

  -- No void or written-off invoice may carry a balance.
  select count(*) into v_bad
  from public.invoice_ar_balances b
  join public.orders o on o.order_id = b.order_id
  where o.invoice_state in ('void', 'written_off')
    and (b.balance_due_cents <> 0 or b.net_balance_cents <> 0);
  if v_bad > 0 then
    raise exception '% void or written-off invoices still carry a balance', v_bad;
  end if;

  -- And the credit case from 000014 must still work.
  if not exists (
    select 1 from pg_views where viewname = 'invoice_ar_balances'
      and definition ~ 'net_balance_cents'
  ) then
    raise exception 'the signed position column is gone';
  end if;
end $$;

commit;
