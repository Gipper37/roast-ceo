-- No company without a billing mode.
--
-- `billing_settings.invoice_of_record` is, in this schema's own words, "the
-- single flag every billing surface gates on". Its column default is
-- 'quickbooks', the table comment says "No row => Mode B (keep QuickBooks)",
-- and the spine migration's purpose was that "existing tenants get NO new
-- billing behavior until they opt into 'strata'".
--
-- Four of the five companies on production have NO ROW. Every DB gate already
-- reads that as Mode B and refuses -- but ABSENCE IS NOT A SETTING, and one
-- path turns it into the opposite one:
--
--   allocate_invoice_number() and allocate_credit_memo_number() both begin with
--       insert into billing_settings (..., invoice_of_record, ...)
--       select p_company_id, 'strata', ...
--        where not exists (select 1 from billing_settings where company_id = ...)
--
--   and only AFTER that do they check `if v_mode = 'quickbooks' then raise`.
--   So the guard is unreachable for a company with no row: the insert it just
--   performed makes the mode 'strata', and the allocation proceeds.
--
-- That is reachable from the order screen, because allocate_invoice_number
-- deliberately admits `invoice.print` -- a packer at the bench hands a customer
-- a numbered document. So a packer pressing "Issue number and print" at a
-- company that has never invoiced from STRATA permanently sets that company's
-- invoice of record, with no confirmation and nothing on screen saying a
-- billing decision was just made. The owner's intent for the two live tenants
-- in this state is the opposite: "they are currently quickbooks ... we will
-- switch them over to strata once we're done with the full payments/invoicing
-- piece."
--
-- The fix is not a new guard. It is to stop the ambiguous state existing, so
-- that the guard those functions ALREADY HAVE is the thing that runs. With an
-- explicit 'quickbooks' row the insert does not fire, v_mode is 'quickbooks',
-- and the allocator raises the message it was always meant to raise:
-- "turn that off in Settings to invoice from STRATA".
--
-- 🔴 WHAT THIS DOES NOT DO: it does not change anybody's mode. Every company
-- without a row is ALREADY Mode B everywhere it is enforced -- payEligibility,
-- five DB gates, and recompute_overdue_invoices_all, which iterates
-- `where invoice_of_record = 'strata'`. This writes down what is already true.
-- The one company with a row ('strata') is not touched.

begin;

-- ── 1. Write down what is already true, for every company lacking a row ──────
-- invoice_next_seq mirrors what the allocators compute when they provision, so
-- a company that later switches to 'strata' cannot reuse a number it has
-- already handed out. Schema-driven, not an assumption that the count is zero.
insert into public.billing_settings (
  company_id, invoice_of_record, invoice_next_seq, credit_memo_next_seq
)
select c.company_id,
       'quickbooks',
       greatest(1, public.max_numeric_invoice_number(c.company_id) + 1),
       1
  from public.companies c
 where not exists (
   select 1 from public.billing_settings bs where bs.company_id = c.company_id
 )
on conflict (company_id) do nothing;

-- ── 2. Stop the state coming back ────────────────────────────────────────────
-- Nothing on `companies` created this row, which is why four of five companies
-- never had one. A new tenant now starts with the documented default written
-- down rather than implied by absence.
--
-- SECURITY DEFINER because billing_settings carries RLS and the role creating a
-- company is not necessarily one that can insert here. It deliberately does NOT
-- touch `role`: RESET ROLE inside a migration discards db-push's own role and
-- kills CI after the body has committed.
create or replace function public.ensure_billing_settings_row()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  insert into public.billing_settings (company_id, invoice_of_record)
  values (new.company_id, 'quickbooks')
  on conflict (company_id) do nothing;
  return new;
end;
$fn$;

comment on function public.ensure_billing_settings_row() is
  'Gives every new company an explicit billing mode. Absence of a billing_settings row is read as Mode B by every gate, but the two number allocators provision it as ''strata'' before their own quickbooks guard can fire -- so an absent row could be flipped by anyone holding invoice.print. A row that exists makes that guard reachable.';

drop trigger if exists trg_billing_settings_default on public.companies;
create trigger trg_billing_settings_default
  after insert on public.companies
  for each row execute function public.ensure_billing_settings_row();

-- ── 3. Post-condition ───────────────────────────────────────────────────────
do $$
declare
  v_missing integer;
begin
  -- This can fail: if the backfill were skipped, the allocators' provisioning
  -- path stays reachable and a print button can still set a tenant's invoice of
  -- record.
  select count(*) into v_missing
    from public.companies c
   where not exists (
     select 1 from public.billing_settings bs where bs.company_id = c.company_id
   );
  if v_missing > 0 then
    raise exception '% company(ies) still have no billing_settings row', v_missing;
  end if;

  -- 🔴 DELIBERATELY NOT ASSERTED: "exactly one company is 'strata'". That is a
  -- fact about PRODUCTION data, and staging is a different database with a
  -- different population -- an assertion like it would raise there, and db push
  -- stops at the first failure, so it would kill the release on the rehearsal
  -- that is supposed to prove it safe. The property that actually matters is
  -- structural and holds in every environment: this migration only INSERTs, and
  -- only for companies with no row, with `on conflict do nothing`. It therefore
  -- cannot change an existing company's mode, whatever that mode is.
  raise notice 'every company now has an explicit billing mode; no existing mode was changed';
end $$;

commit;
