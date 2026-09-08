-- ============================================================================
-- MCR (Maui Coffee Roasters, company_id 9ShiyDAXhV) legacy-invoice backfill
-- ----------------------------------------------------------------------------
-- Makes the Python-migrated QuickBooks orders behave as if imported via the QB
-- import tool, AND surfaces each order's original QB number as invoice_number so
-- STRATA continues right where QuickBooks left off. Sets forward numbering to
-- continue from the last QB number, and corrects the UTC-skewed cutover_date.
--
-- Company-scoped to 9ShiyDAXhV — NEVER touches any other tenant.
-- RUN AGAINST PROD ONLY AFTER EXPLICIT REVIEW/APPROVAL.
--
-- Verified preconditions (prod, read-only, 2026-07-06):
--   * 3,374 orders (created_by='mcr-qb-import'); invoice_number NULL on all;
--     is_legacy_import false on all; every order has a QB number (qb_txn_id).
--   * qb_txn_id is UNIQUE within the company (0 duplicates) -> raw backfill is
--     collision-safe against orders_company_invoice_number_uidx.
--   * max pure-numeric QB number = 104297 -> forward seed = 104298.
--   * 3,332 pure-numeric refs; 42 non-numeric refs (e.g. 'P&S103792', 'CM102891',
--     'QUOTE103313', 'CM2272026', 'missing') -> stored VERBATIM (unique, safe).
--   * No other MCR orders currently carry an invoice_number.
-- ============================================================================

-- ── 0. DRY RUN (read-only) — re-verify immediately before writing ────────────
SELECT count(*) AS total,
       count(*) FILTER (WHERE invoice_number IS NULL) AS inv_null,
       count(*) FILTER (WHERE NOT is_legacy_import)   AS not_legacy
  FROM public.orders
 WHERE company_id='9ShiyDAXhV' AND created_by='mcr-qb-import';

SELECT btrim(qb_txn_id) AS num, count(*) c        -- expect 0 rows (no dups)
  FROM public.orders
 WHERE company_id='9ShiyDAXhV' AND created_by='mcr-qb-import'
   AND qb_txn_id IS NOT NULL AND btrim(qb_txn_id) <> ''
 GROUP BY 1 HAVING count(*) > 1;

SELECT max(btrim(qb_txn_id)::bigint) AS max_qb_numeric   -- expect 104297
  FROM public.orders
 WHERE company_id='9ShiyDAXhV' AND created_by='mcr-qb-import'
   AND btrim(qb_txn_id) ~ '^\d+$';

-- ── 1. BACKFILL (transactional) ──────────────────────────────────────────────
BEGIN;

-- 1a. Surface the QB number as invoice_number + flag as archived legacy history.
--     invoice_state stays NULL and posted stays false, so these do NOT enter A/R
--     aging or the pay-link flow — they are historical records that simply show
--     their original number. is_legacy_import blocks any accidental re-finalize.
UPDATE public.orders
   SET invoice_number   = NULLIF(btrim(qb_txn_id), ''),
       is_legacy_import = true,
       qb_sync_status   = 'skip'
 WHERE company_id='9ShiyDAXhV'
   AND created_by='mcr-qb-import'
   AND invoice_number IS NULL;                 -- idempotent

-- 1b. Continue STRATA numbering from the last QB number, no prefix (seamless),
--     and correct the cutover date to the operator's real local day (was recorded
--     as 2026-07-06 from UTC; the local Hawaii cutover day was 2026-07-05).
UPDATE public.billing_settings
   SET invoice_prefix   = '',
       invoice_next_seq = 104298,             -- max QB (104297) + 1; confirm vs step 0
       cutover_date     = DATE '2026-07-05',
       updated_at       = now()
 WHERE company_id='9ShiyDAXhV';

-- 1c. IN-TRANSACTION VERIFICATION (review before COMMIT) ----------------------
SELECT invoice_number, count(*)                 -- expect 0 rows (no dup numbers)
  FROM public.orders
 WHERE company_id='9ShiyDAXhV' AND invoice_number IS NOT NULL
 GROUP BY 1 HAVING count(*) > 1;

SELECT count(*) AS seed_collision                -- expect 0
  FROM public.orders
 WHERE company_id='9ShiyDAXhV' AND invoice_number='104298';

SELECT count(*) FILTER (WHERE invoice_number IS NOT NULL) AS with_number,
       count(*) FILTER (WHERE is_legacy_import)           AS legacy
  FROM public.orders
 WHERE company_id='9ShiyDAXhV' AND created_by='mcr-qb-import';   -- expect 3374 / 3374

SELECT invoice_of_record, invoice_prefix, invoice_next_seq, invoice_pad_width, cutover_date
  FROM public.billing_settings WHERE company_id='9ShiyDAXhV';

COMMIT;
-- ROLLBACK;   -- use this instead of COMMIT if any verification above looks wrong
