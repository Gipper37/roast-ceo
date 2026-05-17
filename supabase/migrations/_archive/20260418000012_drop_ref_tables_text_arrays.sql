-- ─────────────────────────────────────────────────────────────────────
-- Replace varietal / flavor_note / coffee_process / certification ref
-- tables with simple text[] columns + TS-side constants.
--
-- Rationale: all four lists are global-only (no per-company customs),
-- and the app only ever needs them for picker UIs. The ref-table +
-- junction pattern was over-engineered for that case — keeping the
-- option list in code:
--   • Removes 4 tables + 2 junctions
--   • Removes 4 round-trips per inventory page load
--   • Adding a new option = one TS line + deploy (acceptable cadence)
--
-- Schema after this migration:
--   coffee_source.varietals     text[]   (was: junction → varietal)
--   coffee_source.flavor_notes  text[]   (was: text comma-string +
--                                          junction → flavor_note)
--   coffee_source.process       text     (unchanged — already text)
--   coffee_source.certifications text     (unchanged — already text)
--
-- Data migration: aggregate junction-linked names into the new
-- text[] columns before dropping. Anything previously stored as a
-- comma-string in `flavor_notes` is preserved by splitting on comma.
-- ─────────────────────────────────────────────────────────────────────

-- ── 1. Add varietals text[] (column doesn't exist yet) ─────────────
ALTER TABLE coffee_source
  ADD COLUMN IF NOT EXISTS varietals text[] NOT NULL DEFAULT '{}';

-- ── 2. Backfill varietals from the junction ────────────────────────
UPDATE coffee_source cs
SET varietals = sub.names
FROM (
  SELECT csv.coffee_source_id,
         array_agg(v.name ORDER BY v.category, v.sort_order, v.name) AS names
  FROM coffee_source_varietal csv
  JOIN varietal v ON v.varietal_id = csv.varietal_id
  GROUP BY csv.coffee_source_id
) sub
WHERE cs.coffee_source_id = sub.coffee_source_id;

-- ── 3. Replace flavor_notes (text → text[]) ────────────────────────
-- Add a staging column, backfill from BOTH the legacy comma-string col
-- and the junction (junction wins where present), then swap.
ALTER TABLE coffee_source
  ADD COLUMN flavor_notes_new text[] NOT NULL DEFAULT '{}';

-- Junction wins: aggregate flavor_note names per source.
UPDATE coffee_source cs
SET flavor_notes_new = sub.names
FROM (
  SELECT csfn.coffee_source_id,
         array_agg(fn.name ORDER BY fn.category, fn.sort_order, fn.name) AS names
  FROM coffee_source_flavor_note csfn
  JOIN flavor_note fn ON fn.flavor_note_id = csfn.flavor_note_id
  GROUP BY csfn.coffee_source_id
) sub
WHERE cs.coffee_source_id = sub.coffee_source_id;

-- Legacy comma-string fallback for sources with no junction rows but
-- non-null `flavor_notes`. Split on comma, trim whitespace, drop blanks.
UPDATE coffee_source
SET flavor_notes_new = ARRAY(
  SELECT trim(part)
  FROM unnest(string_to_array(flavor_notes, ',')) AS part
  WHERE trim(part) <> ''
)
WHERE (flavor_notes_new IS NULL OR cardinality(flavor_notes_new) = 0)
  AND flavor_notes IS NOT NULL
  AND trim(flavor_notes) <> '';

-- Swap.
ALTER TABLE coffee_source DROP COLUMN flavor_notes;
ALTER TABLE coffee_source RENAME COLUMN flavor_notes_new TO flavor_notes;

-- ── 4. Indexes for filtering ───────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_coffee_source_varietals_gin
  ON coffee_source USING GIN (varietals);
CREATE INDEX IF NOT EXISTS idx_coffee_source_flavor_notes_gin
  ON coffee_source USING GIN (flavor_notes);

-- ── 5. Drop the ref + junction tables ──────────────────────────────
DROP TABLE IF EXISTS coffee_source_varietal;
DROP TABLE IF EXISTS coffee_source_flavor_note;
DROP TABLE IF EXISTS coffee_source_certification;  -- created 00011, never used
DROP TABLE IF EXISTS varietal;
DROP TABLE IF EXISTS flavor_note;
DROP TABLE IF EXISTS coffee_process;
DROP TABLE IF EXISTS certification;

COMMENT ON COLUMN coffee_source.varietals IS
  'text[] of varietal names. Option list lives in lib/coffee-options.ts on '
  'the frontend. No FK enforcement — typed enum on the client makes typos '
  'effectively impossible in practice.';

COMMENT ON COLUMN coffee_source.flavor_notes IS
  'text[] of SCA Flavor Wheel descriptors. Option list lives in '
  'lib/coffee-options.ts. Migrated from the previous junction model in '
  '20260418000012.';
