-- ─────────────────────────────────────────────────────────────────────
-- Flavor notes ref table + many-to-many to coffee_source.
--
-- Until now `coffee_source.flavor_notes` was a single freeform text
-- column. That makes filtering + comparison + autocomplete impossible.
-- This migration introduces a normalized model:
--
--   flavor_note               — global ref list, seeded with the SCA
--                               Coffee Taster's Flavor Wheel (2nd
--                               level + selected 3rd-level descriptors).
--                               Companies can add their own notes by
--                               inserting rows with company_id set;
--                               company_id IS NULL rows are visible to
--                               everyone.
--
--   coffee_source_flavor_note — junction. Cascades on coffee_source
--                               delete; restricts on flavor_note delete
--                               so we don't accidentally orphan tags
--                               when reorganizing the seed list.
--
-- We keep `coffee_source.flavor_notes` (text) intact for backward
-- compatibility with anything that still reads it. New writes prefer
-- the junction.
-- ─────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS flavor_note (
  flavor_note_id text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  name           text NOT NULL,
  category       text NOT NULL,
  -- Sort within a category; lower = earlier in pickers.
  sort_order     integer DEFAULT 100,
  -- NULL = global (visible to everyone). Non-null = company-scoped.
  company_id     text REFERENCES companies(company_id) ON DELETE CASCADE,
  is_active      boolean NOT NULL DEFAULT true,
  created_at     timestamptz DEFAULT now(),
  updated_at     timestamptz DEFAULT now(),
  -- Within a scope (global or company), names must be unique.
  UNIQUE NULLS NOT DISTINCT (company_id, name)
);

CREATE INDEX IF NOT EXISTS idx_flavor_note_category ON flavor_note(category);
CREATE INDEX IF NOT EXISTS idx_flavor_note_company  ON flavor_note(company_id);

CREATE TABLE IF NOT EXISTS coffee_source_flavor_note (
  coffee_source_id text NOT NULL REFERENCES coffee_source(coffee_source_id) ON DELETE CASCADE,
  flavor_note_id   text NOT NULL REFERENCES flavor_note(flavor_note_id)     ON DELETE RESTRICT,
  created_at       timestamptz DEFAULT now(),
  PRIMARY KEY (coffee_source_id, flavor_note_id)
);

CREATE INDEX IF NOT EXISTS idx_csfn_source ON coffee_source_flavor_note(coffee_source_id);
CREATE INDEX IF NOT EXISTS idx_csfn_note   ON coffee_source_flavor_note(flavor_note_id);

-- ── Seed: SCA Coffee Taster's Flavor Wheel ────────────────────────────
-- Categories follow the wheel's outer ring; descriptors are second
-- level (the most useful granularity for cupping notes). A handful of
-- third-level descriptors that everyone uses (Blueberry, Caramel,
-- Hazelnut, etc.) are included to spare the user "Berry/Other".
-- All seeded rows have company_id = NULL → visible to all tenants.

INSERT INTO flavor_note (name, category, sort_order, company_id) VALUES
  -- Floral
  ('Black Tea',        'Floral', 10, NULL),
  ('Chamomile',        'Floral', 20, NULL),
  ('Rose',             'Floral', 30, NULL),
  ('Jasmine',          'Floral', 40, NULL),
  ('Honeysuckle',      'Floral', 50, NULL),

  -- Fruity — Berry
  ('Blackberry',       'Berry',  10, NULL),
  ('Raspberry',        'Berry',  20, NULL),
  ('Blueberry',        'Berry',  30, NULL),
  ('Strawberry',       'Berry',  40, NULL),
  ('Cranberry',        'Berry',  50, NULL),

  -- Fruity — Citrus
  ('Grapefruit',       'Citrus', 10, NULL),
  ('Orange',           'Citrus', 20, NULL),
  ('Lemon',            'Citrus', 30, NULL),
  ('Lime',             'Citrus', 40, NULL),
  ('Bergamot',         'Citrus', 50, NULL),

  -- Fruity — Stone / Other
  ('Peach',            'Stone Fruit', 10, NULL),
  ('Apricot',          'Stone Fruit', 20, NULL),
  ('Cherry',           'Stone Fruit', 30, NULL),
  ('Plum',             'Stone Fruit', 40, NULL),
  ('Apple',            'Other Fruit', 10, NULL),
  ('Pear',             'Other Fruit', 20, NULL),
  ('Pineapple',        'Other Fruit', 30, NULL),
  ('Mango',            'Other Fruit', 40, NULL),
  ('Papaya',           'Other Fruit', 50, NULL),
  ('Grape',            'Other Fruit', 60, NULL),
  ('Pomegranate',      'Other Fruit', 70, NULL),
  ('Coconut',          'Other Fruit', 80, NULL),

  -- Fruity — Dried
  ('Raisin',           'Dried Fruit', 10, NULL),
  ('Prune',            'Dried Fruit', 20, NULL),
  ('Date',             'Dried Fruit', 30, NULL),
  ('Fig',              'Dried Fruit', 40, NULL),

  -- Sour / Fermented
  ('Sour',             'Sour / Fermented', 10, NULL),
  ('Acidic',           'Sour / Fermented', 20, NULL),
  ('Winey',            'Sour / Fermented', 30, NULL),
  ('Whiskey',          'Sour / Fermented', 40, NULL),
  ('Fermented',        'Sour / Fermented', 50, NULL),
  ('Overripe',         'Sour / Fermented', 60, NULL),

  -- Green / Vegetative
  ('Green',            'Green / Vegetative', 10, NULL),
  ('Hay-like',         'Green / Vegetative', 20, NULL),
  ('Herb-like',        'Green / Vegetative', 30, NULL),
  ('Beany',            'Green / Vegetative', 40, NULL),
  ('Fresh',            'Green / Vegetative', 50, NULL),

  -- Roasted
  ('Roasted',          'Roasted',  10, NULL),
  ('Smoky',            'Roasted',  20, NULL),
  ('Burnt',            'Roasted',  30, NULL),
  ('Tobacco',          'Roasted',  40, NULL),
  ('Pipe Tobacco',     'Roasted',  50, NULL),
  ('Cereal',           'Roasted',  60, NULL),
  ('Malt',             'Roasted',  70, NULL),
  ('Grain',            'Roasted',  80, NULL),

  -- Spices
  ('Black Pepper',     'Spices', 10, NULL),
  ('Pungent',          'Spices', 20, NULL),
  ('Anise',            'Spices', 30, NULL),
  ('Nutmeg',           'Spices', 40, NULL),
  ('Cinnamon',         'Spices', 50, NULL),
  ('Clove',            'Spices', 60, NULL),
  ('Cardamom',         'Spices', 70, NULL),

  -- Nutty / Cocoa
  ('Almond',           'Nutty / Cocoa', 10, NULL),
  ('Hazelnut',         'Nutty / Cocoa', 20, NULL),
  ('Peanut',           'Nutty / Cocoa', 30, NULL),
  ('Walnut',           'Nutty / Cocoa', 40, NULL),
  ('Pecan',            'Nutty / Cocoa', 50, NULL),
  ('Cocoa',            'Nutty / Cocoa', 60, NULL),
  ('Chocolate',        'Nutty / Cocoa', 70, NULL),
  ('Dark Chocolate',   'Nutty / Cocoa', 80, NULL),
  ('Milk Chocolate',   'Nutty / Cocoa', 90, NULL),

  -- Sweet
  ('Brown Sugar',      'Sweet', 10, NULL),
  ('Molasses',         'Sweet', 20, NULL),
  ('Maple Syrup',      'Sweet', 30, NULL),
  ('Caramel',          'Sweet', 40, NULL),
  ('Caramelized',      'Sweet', 50, NULL),
  ('Honey',            'Sweet', 60, NULL),
  ('Vanilla',          'Sweet', 70, NULL),
  ('Vanillin',         'Sweet', 80, NULL),
  ('Toffee',           'Sweet', 90, NULL),

  -- Other / off-flavors
  ('Papery',           'Other', 10, NULL),
  ('Musty',            'Other', 20, NULL),
  ('Earthy',           'Other', 30, NULL),
  ('Woody',            'Other', 40, NULL),
  ('Petroleum',        'Other', 50, NULL),
  ('Medicinal',        'Other', 60, NULL),
  ('Chemical',         'Other', 70, NULL)
ON CONFLICT DO NOTHING;

COMMENT ON TABLE flavor_note IS
  'SCA Coffee Taster''s Flavor Wheel descriptors. company_id IS NULL = '
  'global; non-null = tenant-specific addition.';

COMMENT ON TABLE coffee_source_flavor_note IS
  'Many-to-many link between coffee_source and flavor_note. ON DELETE '
  'RESTRICT on flavor_note prevents accidental orphaning if the seed '
  'list is reorganized — coffee_source.flavor_notes (text col) remains '
  'as a non-normalized backup.';
