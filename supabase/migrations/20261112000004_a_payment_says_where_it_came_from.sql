-- A recorded payment says where the money came from.
--
-- The accountant's complaint: she knows what she keys in by hand, but once it is in the
-- register a payment the customer made online looks exactly like one she entered, and in
-- some views it reads as neither. Nothing in invoice_payments says which it was.
--
-- Three things can put a row in this table, and each one knows which it is at the moment
-- it writes:
--   online         the customer paid for themselves on a page we served -- the invoice pay
--                  link, or storefront checkout. No staff member touched the card.
--   staff_charge   a staff member typed the card in the app (the accounting terminal's
--                  charge over the phone, or the Charge a card button on an order).
--   hand_entry     a person recorded money that arrived some other way: a check, cash, a
--                  card run on the countertop machine, a transfer.
--
-- 🔴 WHY A COLUMN AND NOT A DERIVATION. All 44 rows on prod can be told apart today by
-- two signals that happen to agree: an online payment is written by the service-role
-- client, so created_by lands NULL, and only a charge carries a payment_transaction_id.
-- Both are SIDE EFFECTS of which client did the insert, not statements about where the
-- money came from, and either could stop being true without a single reader noticing --
-- an online path that gains a user session, or a hand entry that one day records the
-- gateway number the customer read over the phone. The register would quietly start
-- lying. So each writer says what it is.
--
-- One path cannot say it first-hand: applying a stuck charge records money the app took
-- on some earlier screen, and nothing on payment_transactions says which screen. That
-- one reads the transaction's created_by, with the reason written at the call site. It is
-- the only reader of the side effect, it is the rare path (0 of the 44 rows below), and
-- it is the place to look first if the register ever disagrees with itself.
--
-- The memos agree too, which is how the backfill below can be trusted: the 18 rows with a
-- transaction and a created_by all say 'Card by phone', the 9 with a transaction and no
-- created_by all say 'Online card payment', and the 17 with no transaction are all typed
-- sentences from a person ('CHK - 147157', 'Cash from Lorenzo...').

alter table public.invoice_payments add column source text;

comment on column public.invoice_payments.source is
  'Where the money came from: online (the customer paid on a page we served), staff_charge (a staff member typed the card in the app), hand_entry (a person recorded money that arrived another way). Set by the writer at insert and never edited -- authenticated may UPDATE only voided_at. NULL means a writer that does not name it, which is a bug: select count(*) from invoice_payments where source is null.';

-- Backfill, exhaustive by construction: every row has a transaction or it does not, and
-- with one it has a created_by or it does not.
update public.invoice_payments set source = case
  when payment_transaction_id is null then 'hand_entry'
  when created_by is null             then 'online'
  else                                     'staff_charge'
end
where source is null;

-- Added after the backfill so it is validated against real rows rather than trusted.
-- NULL stays legal: a payment is money that has already left the customer, and refusing
-- the insert over a label would leave a captured charge unrecorded -- the one failure
-- this codebase keeps paying for. A missed writer shows up as a NULL in the query above,
-- not as a charge stuck on the dashboard.
alter table public.invoice_payments
  add constraint invoice_payments_source_known
  check (source is null or source in ('online', 'staff_charge', 'hand_entry'));

-- No new grant: authenticated holds INSERT and SELECT on the table, which covers a column
-- added later, and its UPDATE is column-level on voided_at alone.

-- This can only pass. The backfill covers every row, so a NULL here would mean the update
-- did not run at all.
do $$
declare n_unsourced int;
begin
  select count(*) into n_unsourced from public.invoice_payments where source is null;
  if n_unsourced > 0 then
    raise exception 'invoice_payments.source left NULL on % rows after the backfill', n_unsourced;
  end if;
end $$;
