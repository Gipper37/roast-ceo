-- Migrate coffee_source.certifications from text to text[]
-- so multiple certifications can be stored (e.g. Organic + Fair Trade).
-- Existing non-null single values are wrapped into a 1-element array;
-- NULL stays NULL; empty string becomes an empty array.

ALTER TABLE coffee_source
  ALTER COLUMN certifications TYPE text[]
  USING CASE
    WHEN certifications IS NULL OR certifications = '' THEN '{}'::text[]
    ELSE ARRAY[certifications]
  END;

ALTER TABLE coffee_source
  ALTER COLUMN certifications SET DEFAULT '{}';

ALTER TABLE coffee_source
  ALTER COLUMN certifications SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_coffee_source_certifications_gin
  ON coffee_source USING gin (certifications);
