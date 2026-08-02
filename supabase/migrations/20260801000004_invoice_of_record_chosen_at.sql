-- "Never asked" is a different state from "chose QuickBooks".
--
-- Invoicing no longer requires a cutover (20260801000003): a company that is
-- entitled to invoice just invoices, and billing_settings provisions itself on
-- the first allocation. That left one thing unsaid — whether the roaster has
-- ever been TOLD that STRATA is now numbering and tracking their invoices, and
-- that they should stop writing the same invoice in QuickBooks.
--
-- That is worth asking exactly once, at the first send, where it is concrete:
-- they are looking at an invoice they want to go out. Not at signup (nobody can
-- predict their workflow), not in the import (importing and invoicing are
-- unrelated), and not in Settings (nobody goes looking to grant themselves a
-- feature they already pay for).
--
-- 🔴 WHY A COLUMN AND NOT JUST THE ROW'S EXISTENCE. The obvious marker — "has a
-- billing_settings row" — stopped working the moment allocate_invoice_number
-- began provisioning one on first use. A roaster would be marked as having
-- answered by the very act that should have prompted the question. So the
-- answer is recorded explicitly, and NULL means nobody has been asked.
--
-- Backfilled for anyone already invoicing: 3,588 invoices in means the decision
-- was made long ago in practice, and asking now would be asking someone to
-- confirm something they have been living with for a month.

begin;

alter table public.billing_settings
  add column if not exists invoice_of_record_chosen_at timestamptz;

comment on column public.billing_settings.invoice_of_record_chosen_at is
  'When the roaster was asked, and answered, which system issues their invoices. NULL = never asked (the first-send prompt is still owed). Set for either answer — declining is an answer.';

-- Anyone who has already issued a STRATA invoice number has answered in the only
-- way that counts. cutover_date is the older signal for the same thing.
update public.billing_settings bs
   set invoice_of_record_chosen_at = coalesce(bs.cutover_date::timestamptz, bs.created_at, now())
 where bs.invoice_of_record_chosen_at is null
   and (
     bs.cutover_date is not null
     or exists (
       select 1 from public.orders o
        where o.company_id = bs.company_id
          and o.invoice_number is not null
          and coalesce(o.is_legacy_import, false) = false
     )
   );

commit;

notify pgrst, 'reload schema';
