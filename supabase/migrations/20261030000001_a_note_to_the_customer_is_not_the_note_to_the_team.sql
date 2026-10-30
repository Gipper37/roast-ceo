-- A note to the customer is not the note to the team.
--
-- The owner asked for two notes on an order: one that PRINTS on the invoice
-- ("Notes to Customer") and one that never leaves the building ("Note to
-- internal team").
--
-- 🔴 THE OBVIOUS IMPLEMENTATION IS THE DANGEROUS ONE. `orders.order_notes`
-- already exists and is labelled "Notes" in the UI, so the cheap move is to
-- relabel it "Notes to Customer" and print it. Measured on production first:
-- 4,271 of this roaster's 4,305 orders (99.2%) carry an order_notes value, and
-- what is in it is internal bookkeeping --
--
--     QB Invoice #103584
--     INV 104984 / MISSING FRENCH DECAF
--
-- Relabelling that field would have printed a QuickBooks reference number, and
-- occasionally a complaint about a missing item, onto almost every invoice the
-- roaster sends out. The code agrees with the data: the QuickBooks importer
-- DEDUPES on `order_notes ilike 'QB*#*'` (qbImportActions.ts), the supersede
-- path PREPENDS to it, and the orders list SEARCHES it. It is an internal
-- field that happens to be called Notes.
--
-- So the existing column keeps its meaning and only its LABEL changes, and the
-- customer-facing note is a new column that starts empty everywhere. Nothing
-- that exists today can leak to a customer through it.

begin;

alter table public.orders
  add column if not exists notes_to_customer text;

comment on column public.orders.notes_to_customer is
  'Customer-facing note, PRINTED on the invoice and the packing slip. Shown in the UI as "Notes to Customer". Distinct from order_notes, which is the internal note and is never rendered on a customer document.';

comment on column public.orders.order_notes is
  'INTERNAL note, never rendered on a customer-facing document. Shown in the UI as "Note to internal team". Load-bearing: the QuickBooks importer dedupes legacy orders on "QB Invoice #<num>" here, the supersede path prepends to it, and the orders list searches it. For anything the customer should read, use notes_to_customer.';

do $$
begin
  -- Post-condition. This can fail: if the add were skipped or rolled back by
  -- an earlier statement in the same transaction, the invoice renderer would
  -- select a column that does not exist and every invoice would 500.
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public'
       and table_name   = 'orders'
       and column_name  = 'notes_to_customer'
  ) then
    raise exception 'notes_to_customer was not added to public.orders';
  end if;

  raise notice 'notes_to_customer added; order_notes keeps its meaning as the internal note';
end $$;

commit;
