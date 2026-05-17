-- Migration: Make channel + consumable_type global (not company-scoped)
-- Also: link UK team auth_user_ids, set UK subscription to enterprise, seed roaster unit

BEGIN;

-- ══════════════════════════════════════════════════════════════════════
-- 1. Make channel table global
-- ══════════════════════════════════════════════════════════════════════

-- Keep Hawaii's channels as the canonical global set (they're the most complete)
-- Remap any products referencing shopify-test channels to the global equivalents
UPDATE products SET channel = (
  SELECT c2.channel_id FROM channel c1
  JOIN channel c2 ON c2.channel = c1.channel AND c2.company_id = 'R7CbqHmA1j'
  WHERE c1.channel_id = products.channel
  AND c1.company_id = 'shopify-test-company-001'
)
WHERE channel IN (SELECT channel_id FROM channel WHERE company_id = 'shopify-test-company-001');

-- Delete the shopify-test duplicates
DELETE FROM channel WHERE company_id = 'shopify-test-company-001';

-- Now set company_id = NULL on all remaining channels (making them global)
ALTER TABLE channel ALTER COLUMN company_id DROP NOT NULL;
UPDATE channel SET company_id = NULL;

-- ══════════════════════════════════════════════════════════════════════
-- 2. Make consumable_type table global
-- ══════════════════════════════════════════════════════════════════════

ALTER TABLE consumable_type ALTER COLUMN company_id DROP NOT NULL;
UPDATE consumable_type SET company_id = NULL;

-- ══════════════════════════════════════════════════════════════════════
-- 3. Link UK team auth_user_ids
-- ══════════════════════════════════════════════════════════════════════

UPDATE team SET auth_user_id = 'e55fd478-9fcb-4f41-99f2-bc219f6438ca'
WHERE email = 'roast@socialhourcoffee.uk' AND company_id = '752af3ed-4' AND auth_user_id IS NULL;

UPDATE team SET auth_user_id = 'd87b764a-2299-4595-b5c0-2dec0a354c97'
WHERE email = 'ryan@brmg.co' AND company_id = '752af3ed-4' AND auth_user_id IS NULL;

-- ══════════════════════════════════════════════════════════════════════
-- 4. Set UK subscription to enterprise
-- ══════════════════════════════════════════════════════════════════════

INSERT INTO subscriptions (subscription_id, company_id, plan_id, status)
VALUES ('uk-enterprise-manual', '752af3ed-4', 'enterprise', 'active')
ON CONFLICT (subscription_id) DO UPDATE
SET plan_id = 'enterprise', status = 'active';

-- ══════════════════════════════════════════════════════════════════════
-- 5. Seed roaster unit for UK
-- ══════════════════════════════════════════════════════════════════════

INSERT INTO roaster_units (roaster_unit_id, company_id, facility_id, name, is_active)
VALUES (gen_random_uuid(), '752af3ed-4', 'b9b37e83-1986-46c0-bc69-fce89120155e', 'Roaster 1', true);

COMMIT;
