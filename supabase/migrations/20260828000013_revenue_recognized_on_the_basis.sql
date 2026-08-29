-- The revenue a filer recognises, on the basis they file.
--
-- The tax return got the accounting_basis treatment in 20260828000010. This is
-- its sibling for REVENUE — the top-line figure a CPA starts from — so a
-- cash-basis company can hand its accountant one number per month that means
-- what it says.
--
-- Deliberately a SEPARATE surface from the operational revenue reports. The
-- owner drew the line himself: Reports/profitability answer "how is the
-- business doing" and stay keyed to order dates, because a sale you have not
-- been paid for is still a sale you made. THIS view answers "what do we tell
-- the state and the IRS", which on a cash basis is a different number with
-- different dates. Blurring the two is how a roaster ends up reconciling
-- against the wrong total at filing time.
--
-- Same skeleton as tax_liability_by_rate on purpose: same basis switch, same
-- period logic, same exclusions. If the two ever disagree about which invoices
-- are in a month, one of them is wrong — keeping the shape identical makes that
-- an obvious diff instead of a subtle one.

begin;

create or replace view public.revenue_recognized as
select o.company_id,
       date_trunc('month', case when b.accounting_basis = 'cash'
                                then o.paid_at::date
                                else o.order_date end)::date as period,
       b.accounting_basis,
       count(distinct o.order_id)                    as invoices,
       round(sum(o.order_total), 2)                  as revenue,
       round(sum(coalesce(o.tax_amount, 0)), 2)      as tax_collected,
       round(sum(o.order_total + coalesce(o.tax_amount, 0)), 2) as gross_receipts,
       -- On a cash basis, what is NOT here yet: raised but unpaid. Shown so the
       -- report can say "and $X is still out there" instead of the number
       -- silently shrinking.
       (select round(coalesce(sum(o2.order_total), 0), 2)
          from public.orders o2
         where o2.company_id = o.company_id
           and o2.order_status <> 'Canceled'
           and o2.paid_at is null
           and b.accounting_basis = 'cash')          as unrecognized_outstanding
  from public.orders o
  join public.billing_settings b on b.company_id = o.company_id
 where o.order_status <> 'Canceled'
   and (b.accounting_basis <> 'cash' or o.paid_at is not null)
 group by 1, 2, 3;

comment on view public.revenue_recognized is
  'Revenue by month on the basis the company files: CASH counts an invoice when '
  'paid and dates it to the payment, ACCRUAL when raised. The operational '
  'revenue reports deliberately do NOT use this — they answer how the business '
  'is doing, this answers what gets filed.';

grant select on public.revenue_recognized to authenticated;

commit;
