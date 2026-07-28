-- MCR ONLY — remove the 134 duplicate orders the 2026-07-28 wizard import created.
--
-- WHY THEY EXIST (this part is general, the cleanup is not):
-- The wizard deduped on its OWN deterministic row id (`qbimp-ord-<hash>`). MCR's
-- history had already been migrated by a python script that minted `mcrimp-ord-…`
-- ids. Same QuickBooks invoice, two different row ids — so the wizard saw 134
-- already-imported invoices as new and wrote them a second time. Revenue was
-- overstated by $75,564.92 across 134 orders / 399 lines.
--
-- The importer now keys dedup on qb_txn_id (the QuickBooks document number), which
-- recognises the invoice however its row was created, and a partial unique index
-- makes a repeat structurally impossible. This script clears the damage that was
-- done before those landed.
--
-- WHICH COPY GOES: the one THIS import created (created_by = the batch id). The
-- py-migrated row is the original and is referenced by the rest of MCR's history.
-- Deleting the batch's copy is exactly what Undo would do for these rows — this is
-- narrower, keeping the 254 genuinely-new orders from the same batch.
--
-- SAFE TO RE-RUN: the WHERE clause only matches rows that still have a surviving
-- twin, so a second run deletes nothing.

\echo '=== DRY RUN — nothing is written by this section ==='

WITH dups AS (
  SELECT o.order_id, o.qb_txn_id, o.order_total
  FROM orders o
  WHERE o.company_id = '9ShiyDAXhV'
    AND o.created_by = '0c887913-cc8c-404c-a854-43fcc329940e'
    AND EXISTS (
      SELECT 1 FROM orders x
      WHERE x.company_id = o.company_id
        AND x.qb_txn_id  = o.qb_txn_id
        AND x.order_id  <> o.order_id
        AND x.created_by IS DISTINCT FROM o.created_by
    )
)
SELECT 'orders to delete' AS check, count(*)::text AS v FROM dups
UNION ALL SELECT 'their $ value',   to_char(sum(order_total), 'FM999,999,990.00') FROM dups
UNION ALL SELECT 'their lines',     (SELECT count(*)::text FROM order_details WHERE order_id IN (SELECT order_id FROM dups))
UNION ALL SELECT 'batch orders KEPT',
  (SELECT count(*)::text FROM orders
   WHERE company_id='9ShiyDAXhV' AND created_by='0c887913-cc8c-404c-a854-43fcc329940e'
     AND order_id NOT IN (SELECT order_id FROM dups));

\echo '=== APPLY — uncomment once the dry run reads right ==='

-- BEGIN;
--
-- CREATE TEMP TABLE dup_orders AS
--   SELECT o.order_id
--   FROM orders o
--   WHERE o.company_id = '9ShiyDAXhV'
--     AND o.created_by = '0c887913-cc8c-404c-a854-43fcc329940e'
--     AND EXISTS (
--       SELECT 1 FROM orders x
--       WHERE x.company_id = o.company_id
--         AND x.qb_txn_id  = o.qb_txn_id
--         AND x.order_id  <> o.order_id
--         AND x.created_by IS DISTINCT FROM o.created_by
--     );
--
-- -- Children first (order_details has an FK to orders).
-- DELETE FROM order_details WHERE order_id IN (SELECT order_id FROM dup_orders);
-- DELETE FROM orders        WHERE order_id IN (SELECT order_id FROM dup_orders);
--
-- -- Post-checks: no QB number may appear twice, and the 254 real ones remain.
-- SELECT 'remaining dup qb_txn_id' AS check, count(*) FROM (
--   SELECT qb_txn_id FROM orders WHERE company_id='9ShiyDAXhV' AND qb_txn_id IS NOT NULL
--   GROUP BY qb_txn_id HAVING count(*) > 1) x;
-- SELECT 'batch orders remaining' AS check, count(*) FROM orders
--   WHERE company_id='9ShiyDAXhV' AND created_by='0c887913-cc8c-404c-a854-43fcc329940e';
--
-- COMMIT;
