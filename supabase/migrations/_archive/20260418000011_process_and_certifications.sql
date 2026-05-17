-- ─────────────────────────────────────────────────────────────────────
-- Coffee Process + Certifications: ref tables for picker fields on
-- coffee_source.
--
-- Until now both fields were freeform text:
--   coffee_source.process         text
--   coffee_source.certifications  text  (intended as comma-list)
--
-- That made aggregation, filtering and consistency impossible. This
-- migration introduces:
--
--   coffee_process                — single-value ref list. coffee_source
--                                   keeps its `process text` column;
--                                   we just suggest values from this
--                                   table to drive the dropdown. Inline
--                                   adds insert here.
--
--   certification +               — multi-value via junction. The
--   coffee_source_certification     existing `certifications text` is
--                                   left intact for back-compat reads.
-- ─────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS coffee_process (
  process_id  text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  name        text NOT NULL,
  -- Optional grouping for display (e.g. 'Washed', 'Natural', 'Honey',
  -- 'Experimental'). Pickers group by this.
  category    text,
  sort_order  integer,
  -- NULL = global; otherwise scoped to one company's customs.
  company_id  text REFERENCES companies(company_id) ON DELETE CASCADE,
  is_active   boolean NOT NULL DEFAULT true,
  created_at  timestamptz DEFAULT now(),
  updated_at  timestamptz DEFAULT now(),
  created_by  text,
  updated_by  text
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_coffee_process_name_company
  ON coffee_process (lower(name), COALESCE(company_id, ''));
CREATE INDEX IF NOT EXISTS idx_coffee_process_company
  ON coffee_process (company_id);

DROP TRIGGER IF EXISTS trg_audit_insert ON coffee_process;
CREATE TRIGGER trg_audit_insert BEFORE INSERT ON coffee_process
  FOR EACH ROW EXECUTE FUNCTION handle_new_record();
DROP TRIGGER IF EXISTS trg_audit_update ON coffee_process;
CREATE TRIGGER trg_audit_update BEFORE UPDATE ON coffee_process
  FOR EACH ROW EXECUTE FUNCTION handle_updated_record();

-- Seed common processes. Categories follow industry usage (the four
-- "primary" methods + an Experimental bucket for the long tail).
INSERT INTO coffee_process (name, category, sort_order, company_id) VALUES
  ('Washed',                      'Washed',       10, NULL),
  ('Wet-Hulled (Giling Basah)',   'Washed',       20, NULL),
  ('Double Washed',               'Washed',       30, NULL),

  ('Natural',                     'Natural',      10, NULL),
  ('Dry Process',                 'Natural',      20, NULL),

  ('Honey',                       'Honey',        10, NULL),
  ('White Honey',                 'Honey',        20, NULL),
  ('Yellow Honey',                'Honey',        21, NULL),
  ('Red Honey',                   'Honey',        22, NULL),
  ('Black Honey',                 'Honey',        23, NULL),
  ('Pulped Natural',              'Honey',        30, NULL),

  ('Anaerobic',                   'Experimental', 10, NULL),
  ('Anaerobic Natural',           'Experimental', 11, NULL),
  ('Anaerobic Washed',            'Experimental', 12, NULL),
  ('Carbonic Maceration',         'Experimental', 20, NULL),
  ('Lactic Fermented',            'Experimental', 30, NULL),
  ('Thermal Shock',               'Experimental', 40, NULL),
  ('Yeast Fermented',             'Experimental', 50, NULL),
  ('Co-Fermented',                'Experimental', 60, NULL),

  ('Decaf — Swiss Water',         'Decaf',        10, NULL),
  ('Decaf — CO2',                 'Decaf',        20, NULL),
  ('Decaf — Mountain Water',      'Decaf',        30, NULL),
  ('Decaf — EA (Sugarcane)',      'Decaf',        40, NULL)
ON CONFLICT DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────
-- Certifications
-- ─────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS certification (
  certification_id text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  name             text NOT NULL,
  -- Short tag used in chip displays (e.g. "USDA Organic" → "Organic").
  short_label      text,
  category         text,
  sort_order       integer,
  company_id       text REFERENCES companies(company_id) ON DELETE CASCADE,
  is_active        boolean NOT NULL DEFAULT true,
  created_at       timestamptz DEFAULT now(),
  updated_at       timestamptz DEFAULT now(),
  created_by       text,
  updated_by       text
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_certification_name_company
  ON certification (lower(name), COALESCE(company_id, ''));
CREATE INDEX IF NOT EXISTS idx_certification_company
  ON certification (company_id);

DROP TRIGGER IF EXISTS trg_audit_insert ON certification;
CREATE TRIGGER trg_audit_insert BEFORE INSERT ON certification
  FOR EACH ROW EXECUTE FUNCTION handle_new_record();
DROP TRIGGER IF EXISTS trg_audit_update ON certification;
CREATE TRIGGER trg_audit_update BEFORE UPDATE ON certification
  FOR EACH ROW EXECUTE FUNCTION handle_updated_record();

CREATE TABLE IF NOT EXISTS coffee_source_certification (
  coffee_source_id  text NOT NULL REFERENCES coffee_source(coffee_source_id) ON DELETE CASCADE,
  certification_id  text NOT NULL REFERENCES certification(certification_id) ON DELETE RESTRICT,
  created_at        timestamptz DEFAULT now(),
  PRIMARY KEY (coffee_source_id, certification_id)
);

CREATE INDEX IF NOT EXISTS idx_csc_certification
  ON coffee_source_certification (certification_id);

-- Seed common third-party + sustainability certifications.
INSERT INTO certification (name, short_label, category, sort_order, company_id) VALUES
  ('USDA Organic',                       'Organic',        'Organic',        10, NULL),
  ('EU Organic',                         'EU Organic',     'Organic',        11, NULL),
  ('JAS Organic',                        'JAS Organic',    'Organic',        12, NULL),

  ('Fairtrade International (FLO)',      'Fairtrade',      'Fair Trade',     10, NULL),
  ('Fair Trade USA',                     'Fair Trade USA', 'Fair Trade',     20, NULL),
  ('Fair for Life',                      'Fair for Life',  'Fair Trade',     30, NULL),

  ('Rainforest Alliance',                'Rainforest',     'Sustainability', 10, NULL),
  ('UTZ Certified',                      'UTZ',            'Sustainability', 20, NULL),
  ('Bird Friendly (SMBC)',               'Bird Friendly',  'Sustainability', 30, NULL),
  ('4C',                                 '4C',             'Sustainability', 40, NULL),
  ('C.A.F.E. Practices',                 'CAFE Practices', 'Sustainability', 50, NULL),

  ('Direct Trade',                       'Direct Trade',   'Sourcing',       10, NULL),
  ('Relationship Coffee',                'Relationship',   'Sourcing',       20, NULL),
  ('Single Origin',                      'Single Origin',  'Sourcing',       30, NULL),
  ('Single Estate',                      'Single Estate',  'Sourcing',       40, NULL),
  ('Microlot',                           'Microlot',       'Sourcing',       50, NULL),

  ('Cup of Excellence',                  'COE',            'Quality',        10, NULL),
  ('Specialty (80+ SCA)',                'Specialty',      'Quality',        20, NULL),

  ('Kosher',                             'Kosher',         'Other',          10, NULL),
  ('Halal',                              'Halal',          'Other',          20, NULL),
  ('Women Produced',                     'Women Produced', 'Other',          30, NULL),
  ('Smithsonian Bird Friendly',          'Bird Friendly',  'Other',          40, NULL)
ON CONFLICT DO NOTHING;
