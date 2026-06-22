-- ============================================================================
-- Loring profile sync → STRATA reference profiles (2026-06-22)
-- ----------------------------------------------------------------------------
-- The near-live Loring integration turns each Roast Architect .lrcp profile into
-- a STRATA reference profile (roast_sessions.is_profile_template=true + the
-- target curve in roast_temp_nodes). roast_sessions already carries the anchor
-- targets (fc_time_secs/fc_temp, dry_end_*, tp_*, target_dev_secs/pct). Three
-- columns are still missing:
--   target_drop_temp   — the .lrcp EORTemp (end-of-roast/drop target BT, °F).
--                        No existing column held a TARGET drop temp.
--   loring_recipe_name — the source Loring RecipeName; the dedup / re-sync key
--                        so a re-pull updates the same reference profile in place.
--   reference_source   — provenance of a reference profile ('loring' | 'manual'
--                        | 'artisan'), so the UI can label + the sync can scope.
--
-- All nullable + additive; no backfill. Idempotent.
-- ============================================================================

BEGIN;

ALTER TABLE public.roast_sessions
    ADD COLUMN IF NOT EXISTS target_drop_temp   numeric,
    ADD COLUMN IF NOT EXISTS loring_recipe_name text,
    ADD COLUMN IF NOT EXISTS reference_source   text;

-- Lookup/upsert key for Loring-sourced reference profiles (partial: only the
-- handful of template rows carry a recipe name, not the thousands of roasts).
CREATE INDEX IF NOT EXISTS idx_roast_sessions_loring_recipe
    ON public.roast_sessions (facility_id, loring_recipe_name)
    WHERE loring_recipe_name IS NOT NULL;

COMMIT;
