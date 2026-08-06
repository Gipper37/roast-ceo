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
create table if not exists mcr_orders_backup_20260805 as
select * from orders
 where company_id = '9ShiyDAXhV' and created_by is not null;

create table if not exists mcr_order_details_backup_20260805 as
select od.* from order_details od
 join orders o using (order_id)
 where o.company_id = '9ShiyDAXhV' and o.created_by is not null;

-- Expect 3,801 orders and 13,331 details. If these disagree, STOP — something
-- has changed since this was written and the delete below is no longer scoped
-- to what was measured.
select (select count(*) from mcr_orders_backup_20260805)        as orders_backed_up,
       (select count(*) from mcr_order_details_backup_20260805) as details_backed_up;

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
