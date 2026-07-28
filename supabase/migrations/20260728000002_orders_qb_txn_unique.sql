-- One QuickBooks document = one order, enforced by the database.
--
-- The QB import deduped on its OWN deterministic row id, so it only ever recognised
-- orders THIS wizard created. A company that had already migrated its history another
-- way — a script, an earlier tool, a consultant — got every one of those invoices
-- imported a SECOND time. MCR hit exactly that: 134 duplicate orders, $75,564.92 of
-- double-counted revenue, because the prior migration minted `mcrimp-ord-…` ids while
-- the wizard looked for `qbimp-ord-…`.
--
-- The importer now keys on qb_txn_id (the QuickBooks document number), which
-- identifies the invoice however its row was created. This index makes that a
-- guarantee rather than a convention: no future importer, script, or hand-insert can
-- reintroduce the duplicate for ANY tenant, whatever id scheme it uses.
--
-- Scoped per company (a QB number is only unique within one company's books) and
-- partial, so the vast majority of orders — native STRATA ones with no qb_txn_id —
-- are unaffected.
--
-- Credit memos are NOT at risk of colliding with a same-numbered invoice: QuickBooks
-- gives them their own document number ("CM - 104073", "CM102891"), which is what
-- lands in qb_txn_id.
--
-- MCR's 134 duplicates were removed by scripts/mcr_remove_duplicate_qb_orders.sql
-- before this ran; the index would fail on them otherwise, which is the point.

create unique index if not exists orders_company_qb_txn_uidx
  on public.orders (company_id, qb_txn_id)
  where qb_txn_id is not null;

comment on index public.orders_company_qb_txn_uidx is
  'One QuickBooks document = one order, per company. Stops a second import (or a different migration tool) re-importing invoices that are already here.';

notify pgrst, 'reload schema';
