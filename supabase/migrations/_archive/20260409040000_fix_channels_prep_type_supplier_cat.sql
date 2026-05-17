-- Fix duplicate channels, create prep_type table, fix supplier_category for UK

BEGIN;

-- ══════════════════════════════════════════════════════════════════════
-- 1. Fix duplicate channels — make truly global
-- ══════════════════════════════════════════════════════════════════════

-- Hawaii's channels still have company_id set (migration didn't NULL them properly)
-- UK has its own channels. Consolidate: keep one set with company_id = NULL.

-- First, remap UK products.channel to the global (Hawaii) channel IDs
UPDATE products SET channel = (
  SELECT g.channel_id FROM channel g
  WHERE g.channel = (SELECT uk.channel FROM channel uk WHERE uk.channel_id = products.channel)
    AND g.company_id = 'R7CbqHmA1j'
  LIMIT 1
)
WHERE channel IN (SELECT channel_id FROM channel WHERE company_id = '752af3ed-4');

-- Delete UK-specific channels
DELETE FROM channel WHERE company_id = '752af3ed-4';

-- Now NULL company_id on all remaining channels
UPDATE channel SET company_id = NULL WHERE company_id IS NOT NULL;

-- ══════════════════════════════════════════════════════════════════════
-- 2. Create prep_type lookup table (global/hybrid)
-- ══════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS prep_type (
  prep_type_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  prep_type text NOT NULL,
  company_id text REFERENCES companies(company_id) ON DELETE CASCADE,
  is_active boolean DEFAULT true,
  sort_order integer DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Seed global defaults (company_id = NULL)
INSERT INTO prep_type (prep_type, company_id, sort_order) VALUES
  ('Whole Bean', NULL, 1),
  ('Ground', NULL, 2),
  ('Drip', NULL, 3),
  ('Espresso', NULL, 4),
  ('Cold Brew', NULL, 5)
ON CONFLICT DO NOTHING;

-- ══════════════════════════════════════════════════════════════════════
-- 3. Fix supplier_category for UK — should be global like channels
-- ══════════════════════════════════════════════════════════════════════

-- Make supplier_category global (same pattern as channels)
-- UK has "Remote By Each" which is wrong — replace with Coffee + Consumables

-- Delete UK's bad category
DELETE FROM supplier_category WHERE company_id = '752af3ed-4';

-- Make Hawaii's categories global
UPDATE supplier_category SET company_id = NULL WHERE company_id IS NOT NULL;

COMMIT;
