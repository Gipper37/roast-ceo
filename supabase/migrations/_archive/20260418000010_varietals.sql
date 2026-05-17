-- ─────────────────────────────────────────────────────────────────────
-- Varietal ref table + many-to-many to coffee_source.
--
-- Mirrors the flavor_note model (00007). A coffee source frequently
-- carries multiple varietals (e.g. Caturra + Bourbon + Typica), so a
-- normalized junction is the right shape.
--
--   varietal                  — global ref list, seeded with common
--                               arabica + robusta cultivars. Companies
--                               can add their own with company_id set;
--                               company_id IS NULL is global.
--
--   coffee_source_varietal    — junction. Cascades on coffee_source
--                               delete; restricts on varietal delete
--                               so reorganizing the seed list doesn't
--                               silently strip tags.
-- ─────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS varietal (
  varietal_id text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  name        text NOT NULL,
  -- Optional grouping (e.g. 'Bourbon-Typica', 'Hybrid', 'Robusta',
  -- 'Heirloom'). Used for display grouping in pickers.
  category    text,
  -- Lower = earlier in pickers within a category.
  sort_order  integer,
  -- NULL = global (visible to all companies). Otherwise scoped to one
  -- company's custom additions.
  company_id  text REFERENCES companies(company_id) ON DELETE CASCADE,
  is_active   boolean NOT NULL DEFAULT true,
  created_at  timestamptz DEFAULT now(),
  updated_at  timestamptz DEFAULT now(),
  created_by  text,
  updated_by  text
);

-- A given name should appear at most once per company (and once
-- globally). Use COALESCE so global rows are uniqued by name alone.
CREATE UNIQUE INDEX IF NOT EXISTS uq_varietal_name_company
  ON varietal (lower(name), COALESCE(company_id, ''));

CREATE INDEX IF NOT EXISTS idx_varietal_company
  ON varietal (company_id);

-- Audit triggers (same pattern as other ref tables).
DROP TRIGGER IF EXISTS trg_audit_insert ON varietal;
CREATE TRIGGER trg_audit_insert BEFORE INSERT ON varietal
  FOR EACH ROW EXECUTE FUNCTION handle_new_record();
DROP TRIGGER IF EXISTS trg_audit_update ON varietal;
CREATE TRIGGER trg_audit_update BEFORE UPDATE ON varietal
  FOR EACH ROW EXECUTE FUNCTION handle_updated_record();

-- ─────────────────────────────────────────────────────────────────────
-- Junction
-- ─────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS coffee_source_varietal (
  coffee_source_id text NOT NULL REFERENCES coffee_source(coffee_source_id) ON DELETE CASCADE,
  varietal_id      text NOT NULL REFERENCES varietal(varietal_id) ON DELETE RESTRICT,
  created_at       timestamptz DEFAULT now(),
  PRIMARY KEY (coffee_source_id, varietal_id)
);

CREATE INDEX IF NOT EXISTS idx_csv_varietal
  ON coffee_source_varietal (varietal_id);

-- ─────────────────────────────────────────────────────────────────────
-- Seed common varietals. Categories follow the standard arabica
-- lineage groupings + a small Robusta bucket.
-- ─────────────────────────────────────────────────────────────────────
INSERT INTO varietal (name, category, sort_order, company_id) VALUES
  -- Bourbon / Typica family (the "old world" arabicas)
  ('Typica',          'Bourbon-Typica',  10, NULL),
  ('Bourbon',         'Bourbon-Typica',  20, NULL),
  ('Red Bourbon',     'Bourbon-Typica',  21, NULL),
  ('Yellow Bourbon',  'Bourbon-Typica',  22, NULL),
  ('Pink Bourbon',    'Bourbon-Typica',  23, NULL),
  ('Caturra',         'Bourbon-Typica',  30, NULL),
  ('Catuai',          'Bourbon-Typica',  31, NULL),
  ('Mundo Novo',      'Bourbon-Typica',  32, NULL),
  ('Pacas',           'Bourbon-Typica',  40, NULL),
  ('Pacamara',        'Bourbon-Typica',  41, NULL),
  ('Maragogipe',      'Bourbon-Typica',  42, NULL),
  ('Maracaturra',     'Bourbon-Typica',  43, NULL),
  ('Villalobos',      'Bourbon-Typica',  44, NULL),
  ('Villa Sarchi',    'Bourbon-Typica',  45, NULL),
  ('Java',            'Bourbon-Typica',  50, NULL),
  ('Mokka',           'Bourbon-Typica',  51, NULL),
  ('Kent',            'Bourbon-Typica',  60, NULL),
  ('SL14',            'Bourbon-Typica',  70, NULL),
  ('SL28',            'Bourbon-Typica',  71, NULL),
  ('SL34',            'Bourbon-Typica',  72, NULL),
  ('S795',            'Bourbon-Typica',  80, NULL),

  -- Ethiopian landraces (often labeled "Heirloom")
  ('Ethiopian Heirloom', 'Landrace', 10, NULL),
  ('Geisha',             'Landrace', 20, NULL),
  ('Wush Wush',          'Landrace', 30, NULL),
  ('74110',              'Landrace', 40, NULL),
  ('74112',              'Landrace', 41, NULL),
  ('74158',              'Landrace', 42, NULL),

  -- Hybrids / disease-resistant cultivars
  ('Castillo',     'Hybrid', 10, NULL),
  ('Colombia',     'Hybrid', 11, NULL),
  ('Tabi',         'Hybrid', 12, NULL),
  ('Catimor',      'Hybrid', 20, NULL),
  ('Sarchimor',    'Hybrid', 21, NULL),
  ('Ruiru 11',     'Hybrid', 30, NULL),
  ('Batian',       'Hybrid', 31, NULL),
  ('Centroamericano (H1)', 'Hybrid', 40, NULL),
  ('Marsellesa',   'Hybrid', 41, NULL),
  ('Starmaya',     'Hybrid', 42, NULL),
  ('IH-90',        'Hybrid', 43, NULL),

  -- Robusta + interspecific
  ('Robusta',      'Robusta', 10, NULL),
  ('Liberica',     'Robusta', 20, NULL),
  ('Excelsa',      'Robusta', 30, NULL)
ON CONFLICT DO NOTHING;
