-- =============================================================================
-- Migrate legacy customer management_type values onto the seeded globals
-- =============================================================================
-- The previous hardcoded list inside CustomerDetail.tsx exposed three
-- legacy values that ended up on real customer rows for SHCRUSA:
--
--   "Client Orders"       (26 customers) — customer places their own orders
--   "Social Hour Orders"  ( 6 customers) — vendor (Social Hour) places for them
--   "Social Hour On Site" ( 2 customers) — vendor manages inventory on-site
--
-- Map onto the seeded globals from migration 20260514000001 so all
-- customers move onto the canonical names that Phase 2 automation
-- (visit reminders, vendor-placed queue, customer-reminder engine)
-- will dispatch on.
--
--   "Client Orders"       → "Customer-Initiated"
--   "Social Hour Orders"  → "Vendor-Placed Orders"
--   "Social Hour On Site" → "Vendor-Managed Inventory"
--
-- "Customer-Initiated" (not "with Reminders") is the safe default for
-- "Client Orders" — those customers don't currently have an opt-in to
-- email reminders. The operator can promote them to
-- "Customer-Initiated with Reminders" individually later (the UI
-- email-required guard fires at that point).
--
-- After remapping, drop the now-unused per-company management_type
-- rows ("Company Managed Order", "Client Managed Order" — present in
-- the table for company R7CbqHmA1j but referenced by zero customer
-- rows). Keeps the dropdown clean.
-- =============================================================================

-- 1) Remap customer rows.
UPDATE public.customers SET management_type = 'Customer-Initiated'
  WHERE management_type = 'Client Orders';

UPDATE public.customers SET management_type = 'Vendor-Placed Orders'
  WHERE management_type = 'Social Hour Orders';

UPDATE public.customers SET management_type = 'Vendor-Managed Inventory'
  WHERE management_type = 'Social Hour On Site';

-- 2) Drop the unused legacy reference rows. NOT IN guard so we never
-- delete a row that's still referenced — defensive even though the
-- audit above said zero references.
DELETE FROM public.management_type
WHERE management_type IN (
  'Company Managed Order',
  'Client Managed Order',
  'Client Orders',
  'Social Hour Orders',
  'Social Hour On Site'
)
AND management_type NOT IN (
  SELECT DISTINCT management_type FROM public.customers
  WHERE management_type IS NOT NULL
);

-- Verification queries (run manually post-push):
--   SELECT management_type, count(*) FROM customers
--   WHERE management_type IS NOT NULL GROUP BY 1;
--   -- Expected: only the 6 seeded globals appear.
--
--   SELECT management_type, company_id FROM management_type
--   ORDER BY company_id NULLS FIRST, management_type;
--   -- Expected: 6 rows with NULL company_id, no per-company orphans.
