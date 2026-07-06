-- invoice_ar_balances: EXPOSE aging_excluded as a column instead of filtering on
-- it. Imported QB invoices (aging_excluded=true) are payable and must appear on
-- the customer PAY page + record-payment; they should only drop out of the AGING
-- REPORT. So the view now carries ALL posted invoices with their aging_excluded
-- flag; the aging consumers (getCompanyAging/getCustomerAging + the customer A/R
-- page) filter aging_excluded=false in-app, while the pay/record-payment paths use
-- everything with a balance. Plan: memory/project_invoice_payment_p5.md.
-- NOTE: CREATE OR REPLACE VIEW can only APPEND columns (not reorder), so
-- aging_excluded goes LAST, after the existing column list.
CREATE OR REPLACE VIEW public.invoice_ar_balances WITH (security_invoker = true) AS
SELECT o.company_id, o.order_id, o.customer_id, o.invoice_number, o.invoice_state, o.due_date,
       round((COALESCE(o.order_total,0) + COALESCE(o.tax_amount,0)) * 100)::bigint AS total_cents,
       COALESCE(pa.paid_cents,0) + COALESCE(cm.credit_cents,0) AS paid_cents,
       GREATEST(round((COALESCE(o.order_total,0) + COALESCE(o.tax_amount,0)) * 100)::bigint
                - COALESCE(pa.paid_cents,0) - COALESCE(cm.credit_cents,0), 0) AS balance_due_cents,
       o.aging_excluded
FROM public.orders o
LEFT JOIN (
  SELECT a.order_id, SUM(a.amount_cents) AS paid_cents
    FROM public.invoice_payment_allocations a
    JOIN public.invoice_payments p ON p.payment_id=a.payment_id AND p.voided_at IS NULL
   GROUP BY a.order_id
) pa ON pa.order_id = o.order_id
LEFT JOIN (
  SELECT applied_to_order_id AS order_id, SUM(amount_cents) AS credit_cents
    FROM public.credit_memos WHERE applied_to_order_id IS NOT NULL AND voided_at IS NULL
   GROUP BY applied_to_order_id
) cm ON cm.order_id = o.order_id
WHERE o.posted AND o.invoice_state IS NOT NULL;
GRANT SELECT ON public.invoice_ar_balances TO authenticated;

NOTIFY pgrst, 'reload schema';
