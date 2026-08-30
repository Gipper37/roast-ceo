-- MCR: adopt imported open A/R into STRATA invoicing.
--
-- 209 unpaid QuickBooks invoices ($164,949) came across flagged
-- is_legacy_import and were never posted — which made them invisible to the
-- balance view, unpayable through A/R, and unreachable by the overdue sweep.
-- The owner's call (2026-08-29): adopt them. Posting sends NO email — only
-- explicit sends and the overdue sweep ever email anyone.
--
-- What adoption sets, and nothing more:
--   posted        = true                        (STRATA now collects it)
--   invoice_state = 'overdue' / 'open'          (by derived due date)
--   due_date      = order_date + the customer's terms (net days; card/cod/
--                   receipt are due on receipt)
-- is_legacy_import stays TRUE — it keeps protecting the imported lines from
-- engine recompute. All 209 reconcile to the cent (header = sum of lines,
-- verified 2026-08-29), so the order-total trigger cannot restate anything.
-- Rows with no QB invoice number are left alone and listed at the end.
--
-- Usage: run inside BEGIN; ... COMMIT; after reviewing the counts.
--   PGPASSWORD=... psql <prod> -f scripts/mcr_adopt_open_ar.sql

\set ON_ERROR_STOP on

begin;

-- Snapshot for the record (re-runnable; harmless duplicate rows are fine)
create table if not exists public._mcr_adopt_open_ar_snapshot as
  select now() as snapped_at, o.order_id, o.posted, o.invoice_state, o.due_date
  from orders o where false;
insert into public._mcr_adopt_open_ar_snapshot
select now(), o.order_id, o.posted, o.invoice_state, o.due_date
from orders o
where o.company_id = '9ShiyDAXhV'
  and o.is_legacy_import
  and o.paid_at is null
  and o.order_status <> 'Canceled'
  and o.invoice_number is not null
  and not coalesce(o.posted, false);

update orders o
set posted        = true,
    invoice_state = case
      when (o.order_date + coalesce(pt.net_days, 0)) < current_date then 'overdue'
      else 'open' end,
    due_date      = o.order_date + coalesce(pt.net_days, 0)
from customers c
left join payment_terms pt on pt.terms_id = c.payment_terms
where c.customer_id = o.customer_id
  and o.company_id = '9ShiyDAXhV'
  and o.is_legacy_import
  and o.paid_at is null
  and o.order_status <> 'Canceled'
  and o.invoice_number is not null
  and not coalesce(o.posted, false);

-- What happened
select 'adopted' as what, count(*), round(sum(coalesce(order_total,0)+coalesce(tax_amount,0))) as dollars
from orders where company_id='9ShiyDAXhV' and is_legacy_import and posted and paid_at is null;

select 'now visible in A/R view' as what, count(*), round(sum(balance_due_cents)/100.0) as dollars
from invoice_ar_balances b join orders o using (order_id)
where o.company_id='9ShiyDAXhV' and o.is_legacy_import;

-- Left alone: unpaid but no QB invoice number — handle by hand if wanted
select 'skipped (no invoice number)' as what, order_id, order_date, order_total
from orders
where company_id='9ShiyDAXhV' and is_legacy_import and paid_at is null
  and order_status <> 'Canceled' and invoice_number is null;

commit;
