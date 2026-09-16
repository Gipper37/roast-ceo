-- MCR (9ShiyDAXhV): snapshot every imported order, then scrap them, so the
-- Custom Transaction Detail import can be re-run onto clean ground.
--
-- 🔴 "MARK THEM CANCELLED AND DELETE LATER" DOES NOT WORK. orders carries
--
--     CREATE UNIQUE INDEX orders_company_invoice_number_uidx
--       ON orders (company_id, invoice_number) WHERE invoice_number IS NOT NULL
--
-- so the old rows keep their invoice numbers reserved no matter what status
-- they hold. Re-importing invoice 104691 while a cancelled 104691 still exists
-- fails on the constraint. Old and new cannot coexist, which means the order is
-- necessarily: snapshot, delete, import, and restore from the snapshot if the
-- import disappoints.
--
-- THEY ARE ALREADY MARKED. No new column is needed — created_by has always
-- carried the provenance:
--
--     mcr-qb-import                          3,374   script import, Jun 25–Jun 26
--     36d35b93… / 0c887913…                    427   the two committed wizard batches
--     NULL                                       2   REAL STRATA ORDERS
--
-- Those two nulls are INV-000001 and INV-000002, raised in the app by a person.
-- Every statement below is scoped `created_by IS NOT NULL` so they survive. A
-- delete written as "all of MCR's orders" would take them, and nothing would
-- bring them back.
--
-- Verified before writing this: zero payment_transactions, zero
-- invoice_payment_allocations and zero chargebacks reference any imported
-- order, so nothing is orphaned by the delete.

begin;

-- ── 1. Snapshot ────────────────────────────────────────────────────────────
-- Whole rows, so a restore is an INSERT SELECT rather than a reconstruction.
-- 🔴 NOT `if not exists`. That is how this script nearly ate prod a second time.
-- The original took the snapshot with `create table if not exists`, so a second
-- run SILENTLY REUSED the first run's table and then deleted live rows against a
-- stale restore point — and the guard below reads that same stale table, gets
-- exactly the counts it expects, and reports success. A snapshot that can be
-- weeks old while claiming to be fresh is worse than no snapshot.
--
-- Plain `create table` now: if the table already exists this ERRORS and the
-- transaction rolls back before a single row is deleted. Date-stamp the names
-- for the day you actually run it.
create table mcr_orders_backup_20260805 as
select * from orders
 where company_id = '9ShiyDAXhV' and created_by is not null;

create table mcr_order_details_backup_20260805 as
select od.* from order_details od
 join orders o using (order_id)
 where o.company_id = '9ShiyDAXhV' and o.created_by is not null;

-- The guard, as an ASSERTION rather than a printed number. A `select` that a
-- human is supposed to read and act on is not a guard — nobody reads it when the
-- script is piped, and the one time it mattered it was reporting a stale table's
-- counts. Re-measure the expectation the day you run this and put it here; if
-- the source data has moved, this raises and nothing is deleted.
do $guard$
declare v_orders int; v_details int;
begin
  select count(*) into v_orders  from mcr_orders_backup_20260805;
  select count(*) into v_details from mcr_order_details_backup_20260805;
  raise notice 'snapshot took % orders and % details', v_orders, v_details;
  if v_orders <> 3801 or v_details <> 13331 then
    raise exception 'snapshot is % orders / % details, expected 3801 / 13331 — the source data has moved since this was scoped; re-measure before deleting anything', v_orders, v_details;
  end if;
end
$guard$;

-- ── 2. Scrap ───────────────────────────────────────────────────────────────
-- Children first. Both scoped by created_by, never by company alone.
delete from order_details od
 using orders o
 where od.order_id = o.order_id
   and o.company_id = '9ShiyDAXhV'
   and o.created_by is not null;

delete from orders
 where company_id = '9ShiyDAXhV' and created_by is not null;

-- ── 3. What should be left ────────────────────────────────────────────────
-- Exactly the two real invoices, and nothing else.
select order_id, order_date, invoice_number, order_status, order_total
  from orders where company_id = '9ShiyDAXhV'
 order by order_date;

-- Customers and products are deliberately untouched: 287 matched products and
-- 80 matched customers represent the manual classify work, and the new import
-- matches against them rather than recreating them.

commit;

-- ── Restore, if the new import disappoints ────────────────────────────────
-- Run these INSTEAD of committing, or after a failed re-import:
--
--   begin;
--   delete from order_details od using orders o
--    where od.order_id = o.order_id and o.company_id = '9ShiyDAXhV'
--      and o.created_by is not null;
--   delete from orders where company_id = '9ShiyDAXhV' and created_by is not null;
--   insert into orders       select * from mcr_orders_backup_20260805;
--   insert into order_details select * from mcr_order_details_backup_20260805;
--   commit;
--
-- Drop the snapshots only once the new import has been reconciled and lived
-- with for a while. They cost nothing to keep.
