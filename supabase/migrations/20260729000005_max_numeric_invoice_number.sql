-- Where should STRATA's invoice numbering start?
--
-- When a roaster makes STRATA their invoice of record, numbering has to CARRY ON
-- from QuickBooks. Restarting at 1 collides with the imported invoices immediately
-- (orders_company_invoice_number_uidx is unique per company), and even where it did
-- not collide it would hand a customer invoice #1 for a business ten years old.
--
-- invoice_number is TEXT, and real data holds several shapes — MCR alone has bare
-- numerics in two disjoint ranges (12527–13998, 101096–104543) plus 'INV-000002' and
-- 'P&S104339'. So this takes the highest ALL-NUMERIC value and ignores the rest,
-- rather than casting blindly and erroring on the first prefixed one.
--
-- Read-only. The import flow uses it to PREFILL the starting number, which the
-- operator can still change — it is a suggestion, not a decision made for them.

begin;

create or replace function public.max_numeric_invoice_number(p_company_id text)
returns bigint
language sql
stable
as $$
  select coalesce(max(o.invoice_number::bigint), 0)
    from public.orders o
   where o.company_id = p_company_id
     and o.invoice_number is not null
     and o.invoice_number ~ '^\d{1,18}$'   -- all-digits only, and inside bigint range
$$;

comment on function public.max_numeric_invoice_number(text) is
  'Highest all-numeric invoice_number for a company (0 if none). Used to suggest where STRATA numbering should continue from at cutover. Non-numeric forms are ignored, not cast.';

revoke all on function public.max_numeric_invoice_number(text) from public, anon;
grant execute on function public.max_numeric_invoice_number(text) to authenticated;

commit;

notify pgrst, 'reload schema';
