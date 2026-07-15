-- ============================================================================
-- MCR invoice-number backfill + seamless QuickBooks continuation
-- Company: Maui Coffee Roasters (9ShiyDAXhV)
--
-- ⚠️  RUN ONLY AFTER the QuickBooks wizard import is COMPLETE, so the max number
--     reflects every imported invoice (currently 104297; ~104543 after import).
-- ⚠️  PROD DATA CHANGE — run inside the transaction, review the verify output,
--     then COMMIT (or ROLLBACK if anything looks off).
--
-- Why: the py-migration stored each order's QB number in orders.qb_txn_id, not
-- orders.invoice_number, so STRATA's invoice-of-record numbering (which reads
-- invoice_number) saw an empty series and restarted at INV-000003. This moves the
-- numbers into invoice_number, drops the INV- prefix, and seeds the counter to
-- max+1 so STRATA continues the exact QuickBooks series (…104544).
-- ============================================================================

BEGIN;

-- 1. Backfill: legacy QB number -> invoice_number, for NUMERIC refs only.
--    The 42 non-numeric refs (credit-memo codes, hand refs) are deliberately
--    left NULL — confirmed "fine as is". Unique index is (company_id,
--    invoice_number) WHERE NOT NULL; all 3,332 numeric qb_txn_id are distinct
--    (verified), so no collision.
UPDATE public.orders
   SET invoice_number  = qb_txn_id,
       is_legacy_import = true
 WHERE company_id = '9ShiyDAXhV'
   AND invoice_number IS NULL
   AND qb_txn_id ~ '^\d+$';

-- 2. Seamless format: no prefix + 6-digit pad, matching QB's bare numbers.
UPDATE public.billing_settings
   SET invoice_prefix    = '',
       invoice_pad_width = 6,
       updated_at        = now()
 WHERE company_id = '9ShiyDAXhV';

-- 3. Seed the next number = highest used + 1 (empty prefix now, so this continues
--    the bare series). set_invoice_next_seq's own guard would also enforce this.
UPDATE public.billing_settings
   SET invoice_next_seq = (
         SELECT max(invoice_number::bigint) + 1
           FROM public.orders
          WHERE company_id = '9ShiyDAXhV'
            AND invoice_number ~ '^\d+$'
       ),
       updated_at = now()
 WHERE company_id = '9ShiyDAXhV';

-- ---- VERIFY (review before COMMIT) ----------------------------------------
-- Expect: prefix '', pad 6, next_seq = max+1 (e.g. 104544).
SELECT invoice_of_record, invoice_prefix, invoice_pad_width, invoice_next_seq
  FROM public.billing_settings WHERE company_id = '9ShiyDAXhV';

-- Expect: with_num = 3,332 (+ any new wizard imports), max_num = highest QB #.
SELECT count(*) FILTER (WHERE invoice_number IS NOT NULL)               AS with_num,
       count(*) FILTER (WHERE invoice_number IS NULL)                   AS without_num,
       max(invoice_number::bigint) FILTER (WHERE invoice_number ~ '^\d+$') AS max_num
  FROM public.orders WHERE company_id = '9ShiyDAXhV';

-- Sanity: the next number must exceed the max (no repeat).
SELECT (SELECT invoice_next_seq FROM public.billing_settings WHERE company_id='9ShiyDAXhV')
       > (SELECT max(invoice_number::bigint) FROM public.orders
            WHERE company_id='9ShiyDAXhV' AND invoice_number ~ '^\d+$') AS next_is_safe;

COMMIT;
