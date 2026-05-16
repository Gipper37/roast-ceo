-- Fix: make channels + supplier_category truly global
-- The audit trigger (handle_updated_record) restores company_id from OLD when NEW is NULL,
-- so we must skip audit to allow setting company_id = NULL.

BEGIN;

SET LOCAL app.skip_audit = 'true';

-- Channels: set company_id = NULL (make global)
UPDATE channel SET company_id = NULL WHERE company_id IS NOT NULL;

-- Supplier categories: set company_id = NULL (make global)
UPDATE supplier_category SET company_id = NULL WHERE company_id IS NOT NULL;

COMMIT;
