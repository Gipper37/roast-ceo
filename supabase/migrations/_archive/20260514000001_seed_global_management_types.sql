-- =============================================================================
-- Seed global account-management types
-- =============================================================================
-- The `management_type` table holds the relationship pattern between a roaster
-- and each of their customers (does the roaster visit + count? does the
-- customer pull from the shop? is it a standing order?). It was previously
-- a free-form per-company list that nobody seeded, so each tenant either
-- had nothing or had inconsistent ad-hoc strings ("Company Managed Order",
-- "Client Managed Order").
--
-- Six standard B2B account-management patterns are now seeded as GLOBALS
-- (`company_id IS NULL`), mirroring the global/per-company pattern already
-- used by `consumable_type` + `product_type`. Tenants can still add
-- company-specific custom types; they just can't override or rename a
-- global (the PK is `management_type` (text), so names are
-- globally unique).
--
-- These names are durable identifiers that Phase 2 features will key off:
--   - VMI            → on-site visit + count workflow
--   - Vendor-Placed  → "due to order for X" queue on roaster dashboard
--   - Standing Order → cron-generated draft orders at the cadence
--   - Customer w/ Reminders → email/SMS nudges with shop link
--   - Customer-Initiated    → pure pull, no automation
--   - One-Off              → ad-hoc, no managed relationship
-- =============================================================================

INSERT INTO public.management_type (management_type, company_id, created_at, updated_at)
VALUES
  ('Vendor-Managed Inventory',         NULL, now(), now()),
  ('Vendor-Placed Orders',             NULL, now(), now()),
  ('Standing Order',                   NULL, now(), now()),
  ('Customer-Initiated with Reminders', NULL, now(), now()),
  ('Customer-Initiated',               NULL, now(), now()),
  ('One-Off',                          NULL, now(), now())
ON CONFLICT (management_type) DO NOTHING;

-- Verification query (run manually after push):
--   SELECT management_type, company_id FROM management_type
--   WHERE company_id IS NULL ORDER BY management_type;
-- Expected: 6 rows, all with NULL company_id.
