-- Fix: make channels + supplier_category truly global, fix UK supplier categories

BEGIN;

-- ══════════════════════════════════════════════════════════════════════
-- 1. Channels: set company_id = NULL (make global)
-- ══════════════════════════════════════════════════════════════════════
UPDATE channel SET company_id = NULL WHERE company_id IS NOT NULL;

-- ══════════════════════════════════════════════════════════════════════
-- 2. Supplier categories: set company_id = NULL (make global)
-- ══════════════════════════════════════════════════════════════════════
UPDATE supplier_category SET company_id = NULL WHERE company_id IS NOT NULL;

-- ══════════════════════════════════════════════════════════════════════
-- 3. Fix UK suppliers: both are coffee suppliers, not consumable
-- ══════════════════════════════════════════════════════════════════════
UPDATE supplier
SET supplier_category = 'GG1a6L'
WHERE company_id = '752af3ed-4'
  AND supplier_category = 'PlmoC2';

COMMIT;
