-- ============================================================================
-- Rename roastmaster_imports → data_imports + add source column.
--
-- Why: about to add Artisan importer alongside Roastmaster, with
-- Cropster + others on the horizon. Each one needs its own import-
-- history rows but they all share the same shape (status, counts,
-- session_ids, errors, undo). One table with a `source` discriminator
-- beats N parallel tables — single history surface, generic
-- ImportRunner abstraction in the TS layer, no duplicated DDL.
--
-- Existing rows are stamped source='roastmaster' so nothing changes
-- from the user's perspective. The NOT NULL default on `source`
-- ensures future inserts have to declare their importer.
-- ============================================================================

BEGIN;

ALTER TABLE roastmaster_imports RENAME TO data_imports;

ALTER TABLE data_imports
  ADD COLUMN IF NOT EXISTS source text NOT NULL DEFAULT 'roastmaster';

COMMENT ON COLUMN data_imports.source IS
  'Which importer produced this row: roastmaster, artisan, cropster, '
  'probat, etc. The TS ImportRunner uses it to scope history fetches '
  'and to dispatch the right revert/undo handler. Always non-null; '
  'every importer must declare itself at insert time.';

-- Existing index from the original table got carried along by the
-- rename, but be explicit about its name pattern matching the new
-- table for clarity. Postgres auto-renamed it; this is a no-op
-- unless someone hand-renamed indexes elsewhere.
ALTER INDEX IF EXISTS idx_roastmaster_imports_facility
  RENAME TO idx_data_imports_facility;

-- New index — history queries filter by (facility_id, source) so a
-- compound index speeds up Artisan's "show me my Artisan-only history"
-- and the unified "all sources" view (single-col facility_id index
-- already covers the all-sources case).
CREATE INDEX IF NOT EXISTS idx_data_imports_facility_source
  ON data_imports (facility_id, source, created_at DESC);

COMMIT;
